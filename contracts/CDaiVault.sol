//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./compound/CTokenInterfaces.sol";
import "./compound/ComptrollerInterface.sol";
import "./Keeper.sol";
import "./Exponential.sol";
import "./CompoundCore.sol";
import "./Ownable.sol";
import "./compound/UniswapAnchoredView.sol";

contract CDaiVault is CompoundCore, Ownable, ERC20 {
    using SafeMath for uint256;

    CTokenInterface private cdai;
    ERC20 private dai;
    ComptrollerInterface private comptroller;
    UniswapAnchoredView private uniswapanchor;
    ERC20 private comp;

    struct BorrowRatio {
        uint256 minimum;
        uint256 target;
        uint256 maximum;
        uint256 epsilon;
    }
    uint256 constant slippageRatio = 0.97e18;

    BorrowRatio public intendedBorrowRatio;

    constructor(
        address _cdaiAddress,
        address _comptrollerAddress,
        address _compUniswapAnchorAddress
    ) ERC20("Vault DAI", "vDAI") CompoundCore(_cdaiAddress, _comptrollerAddress) {
        intendedBorrowRatio.minimum = 0.95e18;
        intendedBorrowRatio.target = 0.97e18;
        intendedBorrowRatio.maximum = 0.99e18;
        intendedBorrowRatio.epsilon = 0.005e18;

        uniswapanchor = UniswapAnchoredView(_compUniswapAnchorAddress);
    }

    /**
     * Calculate the net asset value of the entire vault
     * @return nav in units of cDai
     */
    function nav() internal view returns (uint256) {
        (
            uint256 oErr,
            uint256 cdaiHeld, // units of cdai
            uint256 daiOwed, // units of dai
            uint256 exchangeRate
        ) = cdai.getAccountSnapshot(address(this));
        require(oErr == 0, "nav: getAccountSnapshot failed");
        return cdaiHeld.sub(mustMulExp(daiOwed, exchangeRate));
    }

    /**
     * Calculate the net asset value of the entire vault
     * @return nav in units of cDai
     */
    function nav(
        uint256 cdaiHeld,
        uint256 daiOwed,
        uint256 exchangeRate
    ) internal pure returns (uint256) {
        return cdaiHeld.sub(mustMulExp(daiOwed, exchangeRate));
    }

    /**
     * Deposit funds
     * Given an input amount of cDai, return the corresponding vdai
     * @param _amount the number of cDai tokens to deposit
     */
    function deposit(uint256 _amount) public {
        bool success = cdai.transferFrom(msg.sender, address(this), _amount);
        require(success, "cdai transfer failed");

        uint256 shares = 0; //vdai
        uint256 currentSupply = totalSupply(); //vdai
        if (currentSupply == 0) {
            shares = _amount;
        } else {
            uint256 _nav = nav();
            // nav / currentSupply == amount / share
            // share == amount * currentSupply / nav
            shares = mustDivExp(mustMulExp(_amount, currentSupply), _nav);
        }
        _mint(msg.sender, shares);
    }

    /**
     * Withdraws the deposited funds
     * Given an input amount of vdai, return the corresponding cdai
     * @param _shares the number of vdai tokens held
     */
    function withdraw(uint256 _shares) external {
        withdraw(_shares, address(0x0));
    }

    struct withdrawLocalVars {
        uint256 err;
        uint256 cdaiHeld;
        uint256 daiOwed;
        uint256 daiCdaiExchangeRate;
        uint256 nav;
        uint256 cdaiToWithdraw;
        uint256 percentShares;
        uint256 collateralFactor;
        uint256 scalingFactor;
    }

    function withdraw(uint256 _sharesToRedeem, address _keeperAddress) public {
        withdrawLocalVars memory vars;

        (
            vars.err,
            vars.cdaiHeld, // units of cdai
            vars.daiOwed, // units of dai
            vars.daiCdaiExchangeRate
        ) = cdai.getAccountSnapshot(address(this));
        require(vars.err == 0, "rebalance: getAccountSnapshot failed");

        // NOTE: this value does not take into account potential COMP held
        vars.nav = nav(vars.cdaiHeld, vars.daiOwed, vars.daiCdaiExchangeRate);
        vars.cdaiToWithdraw = mustDivExp(mustMulExp(vars.nav, _sharesToRedeem), totalSupply());
        _burn(msg.sender, _sharesToRedeem);

        BorrowRatio memory _intendedBorrowRatio = intendedBorrowRatio;

        vars.percentShares = mustDivExp(_sharesToRedeem, totalSupply());
        //Units: [0,1], typically around 0.75 scaled with 1e18
        vars.collateralFactor = getCdaiCollateralFactor();

        // scalingFactor calculates modified target, taking into account that we need cdaiToWithdraw = slack level. After final withdrawal, will achieve target
        // scalingFactor = 1 / (1 + percentShares * (1-Target))
        // derived from NAV def (constant across steps per share) = dai supplied - dai borrowed (at end or start),
        // share value in dai = percentShares * NAV,
        // identity target = dai borrow at end / dai supplied at end,
        // and identity modified target = dai borrow at end / (dai supplied at end + share value in Dai)
        vars.scalingFactor = mustDivExp(
            expScale,
            (expScale +
                mustMulExp(
                    vars.percentShares,
                    expScale - mustMulExp(_intendedBorrowRatio.target, vars.collateralFactor)
                ))
        );

        //Units: [0,1]
        uint256 _borrowRatio =
            computeBorrowRatio(
                vars.cdaiHeld,
                vars.daiOwed,
                vars.daiCdaiExchangeRate,
                vars.collateralFactor
            );

        //Units: [0,1]
        uint256 _slack = 0;
        if (_borrowRatio < _intendedBorrowRatio.maximum) {
            _slack = _intendedBorrowRatio.maximum.sub(_borrowRatio);
        }

        //Units: cdai tokens (e.g., 1000)
        uint256 _cdaiSlack = mustMulExp3(_slack, vars.collateralFactor, vars.cdaiHeld);

        uint256 compPriceInDai =
            mustDivExp(uniswapanchor.price("COMP"), uniswapanchor.price("DAI"));

        // COMP->Dai price * COMP held * (1-slippage factor)
        uint256 _compDaiValue =
            mustMulExp3(comp.balanceOf(msg.sender), compPriceInDai, slippageRatio);

        if (_cdaiSlack < vars.cdaiToWithdraw) {
            require(
                _keeperAddress != address(0x0),
                "rebalancing required but no keeper address provided"
            );

            // TODO: check if this reverts automatically or not
            // TO-REMEBER: This could be optimized in the future by potentially passing more arguments
            Keeper(_keeperAddress).rebalance(
                mustMulExp(vars.scalingFactor, _intendedBorrowRatio.minimum),
                mustMulExp(vars.scalingFactor, _intendedBorrowRatio.target),
                mustMulExp(vars.scalingFactor, _intendedBorrowRatio.maximum),
                _intendedBorrowRatio.epsilon,
                _compDaiValue
            );
        }

        // check NAV
        //old NAV/share = _nav / (totalsupply() + sharesToRedeem)
        uint256 oldNavPerShare = mustDivExp(vars.nav, (totalSupply().add(_sharesToRedeem)));

        (
            vars.err,
            vars.cdaiHeld, // units of cdai
            vars.daiOwed, // units of dai
            vars.daiCdaiExchangeRate
        ) = cdai.getAccountSnapshot(address(this));
        require(vars.err == 0, "rebalance: getAccountSnapshot failed");

        // check old NAV/share - new NAV/share increases by at least _compDaiValue/totalsupply()
        uint256 newNavPerShare =
            mustDivExp(nav(vars.cdaiHeld, vars.daiOwed, vars.daiCdaiExchangeRate), totalSupply());
        require(
            newNavPerShare.sub(oldNavPerShare) > mustDivExp(_compDaiValue, totalSupply()),
            "Keeper returned insufficient NAV/share."
        );

        // check leverage (post-withdraw)
        //Units: [0,1]
        _borrowRatio = computeBorrowRatio(
            vars.cdaiHeld,
            vars.daiOwed,
            vars.daiCdaiExchangeRate,
            vars.collateralFactor
        );
        uint256 _scaledTargetBorrowRatio =
            mustMulExp(vars.scalingFactor, intendedBorrowRatio.target);
        // check currentBorrowRatio (pre-withdraw) within epsilon of scalingFactor * indendedBorrowRatio.target
        if (_borrowRatio > _scaledTargetBorrowRatio) {
            require(
                _borrowRatio - _scaledTargetBorrowRatio < intendedBorrowRatio.epsilon,
                "Keeper returned insufficient borrow ratio."
            );
        } else {
            require(
                _scaledTargetBorrowRatio - _borrowRatio < intendedBorrowRatio.epsilon,
                "Keeper returned insufficient borrow ratio."
            );
        }
        // should be same as checking currentBorrowRatio (post-withdraw) within epsilon of intendedBorrowRatio.target

        cdai.transfer(msg.sender, vars.cdaiToWithdraw);
    }

    fallback() external {
        revert("fallback function should not be called");
    }

    function rebalance(address _keeperAddress) public {
        (
            uint256 _oErr,
            uint256 _cdaiHeld, // units of cdai
            uint256 _daiOwed, // units of dai
            uint256 _daiCdaiExchangeRate
        ) = cdai.getAccountSnapshot(address(this));
        require(_oErr == 0, "rebalance: getAccountSnapshot failed");

        // NOTE: this value does not take into account potential COMP held
        uint256 _nav = nav(_cdaiHeld, _daiOwed, _daiCdaiExchangeRate);

        BorrowRatio memory _intendedBorrowRatio = intendedBorrowRatio;

        //Units: [0,1], typically around 0.75 scaled with 1e18
        uint256 _collateralFactor = getCdaiCollateralFactor();

        //Units: [0,1]
        uint256 _borrowRatio =
            computeBorrowRatio(_cdaiHeld, _daiOwed, _daiCdaiExchangeRate, _collateralFactor);

        // COMP->Dai price * COMP held * (1-slippage factor)
        uint256 _compDaiValue =
            mustMulExp3(
                comp.balanceOf(msg.sender),
                mustDivExp(uniswapanchor.price("COMP"), uniswapanchor.price("DAI")), // comp price in DAI
                slippageRatio
            );

        // TODO: check if this reverts automatically or not
        // TO-REMEBER: This could be optimized in the future by potentially passing more arguments
        Keeper(_keeperAddress).rebalance(
            _intendedBorrowRatio.minimum,
            _intendedBorrowRatio.target,
            _intendedBorrowRatio.maximum,
            _intendedBorrowRatio.epsilon,
            _compDaiValue
        );

        // check NAV
        //old NAV/share = _nav / (totalsupply() + sharesToRedeem)
        uint256 oldNavPerShare = mustDivExp(_nav, totalSupply());

        (
            _oErr,
            _cdaiHeld, // units of cdai
            _daiOwed, // units of dai
            _daiCdaiExchangeRate
        ) = cdai.getAccountSnapshot(address(this));
        require(_oErr == 0, "rebalance: getAccountSnapshot failed");

        // check old NAV/share - new NAV/share increases by at least _compDaiValue/totalsupply()
        uint256 newNavPerShare =
            mustDivExp(nav(_cdaiHeld, _daiOwed, _daiCdaiExchangeRate), totalSupply());
        require(
            newNavPerShare.sub(oldNavPerShare) > mustDivExp(_compDaiValue, totalSupply()),
            "Keeper returned insufficient NAV/share."
        );

        // check leverage (post-withdraw)
        //Units: [0,1]
        _borrowRatio = computeBorrowRatio(
            _cdaiHeld,
            _daiOwed,
            _daiCdaiExchangeRate,
            _collateralFactor
        );
        if (_borrowRatio > _intendedBorrowRatio.target) {
            require(
                _borrowRatio - _intendedBorrowRatio.target < intendedBorrowRatio.epsilon,
                "Keeper returned insufficient borrow ratio."
            );
        } else {
            require(
                _intendedBorrowRatio.target - _borrowRatio < intendedBorrowRatio.epsilon,
                "Keeper returned insufficient borrow ratio."
            );
        }
    }
}
