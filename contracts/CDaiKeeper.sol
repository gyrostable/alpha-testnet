//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./compound/CToken.sol";
import "./Exponential.sol";
import "./compound/ComptrollerInterface.sol";
import "./uniswap/UniswapExchangeInterface.sol";

import "./Keeper.sol";
import "./CDaiVault.sol";
import "./CompoundCore.sol";

contract CDaiKeeper is CompoundCore, Keeper {
    using SafeMath for uint256;

    CToken private cdai;
    ERC20 private dai;
    ComptrollerInterface private comptroller;
    ERC20 private comp;
    UniswapExchangeInterface private daiCompPool;

    uint256 constant safeMaxRatio = 0.999e18;

    string constant CANNOT_REBALANCE = "cannot rebalance when the collateral ratio is within range";
    string constant NO_DAI_AVAILABLE = "no DAI is available for withdrawal";

    /// Minimum amount needed to recycle (1000 DAI)
    uint256 public recycleThreshold = 1000e18;

    event Repay(
        uint256 indexed amountRepaid,
        uint256 indexed newDaiHeld,
        uint256 indexed newDaiOwed
    );

    event Borrow(uint256 indexed newDaiHeld, uint256 indexed newDaiOwed);

    constructor(
        address cdaiAddress,
        address daiAddress,
        address compAddress,
        address comptrollerAddress,
        address daiCompPoolAddress
    ) CompoundCore(cdaiAddress, comptrollerAddress) {
        cdai = CToken(cdaiAddress);
        dai = ERC20(daiAddress);
        comp = ERC20(compAddress);
        comptroller = ComptrollerInterface(comptrollerAddress);
        daiCompPool = UniswapExchangeInterface(daiCompPoolAddress);
    }

    /**
     * This sells our COMP tokens to DAI through Uniswap
     *
     * @param minDai is the minimum amount of DAI we want in exchange for our COMP
     */
    function sellComp(uint256 minDai) internal returns (uint256) {
        uint256 compBalance = comp.balanceOf(msg.sender);
        if (compBalance == 0) {
            return 0;
        }
        // we can safely ignore the amount of dai bought returned
        return
            daiCompPool.tokenToTokenSwapInput(
                compBalance,
                minDai,
                0,
                block.timestamp + 1,
                address(dai)
            );
    }

    function isWithinBorrowRatioTarget(
        uint256 currentBorrowRatio,
        uint256 targetBorrowRatio,
        uint256 borrowRatioEpsilon
    ) internal pure returns (bool) {
        if (currentBorrowRatio > targetBorrowRatio) {
            return currentBorrowRatio - targetBorrowRatio <= borrowRatioEpsilon;
        } else {
            return targetBorrowRatio - currentBorrowRatio <= borrowRatioEpsilon;
        }
    }

    function borrowDai(
        uint256 _currentBorrowRatio,
        uint256 _targetBorrowRatio,
        uint256 _borrowRatioEpsilon
    ) internal {
        uint256 _maxAvailableDAI = cdai.getCash();
        require(_maxAvailableDAI > 0, NO_DAI_AVAILABLE);

        (
            uint256 _oErr,
            uint256 _cdaiHeld, // units of cdai
            uint256 _daiOwed, // units of dai
            uint256 _exchangeRate
        ) = cdai.getAccountSnapshot(msg.sender);
        require(_oErr == 0, "getAccountSnapshot failed");

        uint256 _daiHeld = cdaiToDai(_cdaiHeld, _exchangeRate);

        uint256 _collateralFactor = getCdaiCollateralFactor();

        uint256 _scaledSafeMaxRatio = mustMulExp(safeMaxRatio, _collateralFactor);

        uint256 _scaledTargetBorrowRatio = mustMulExp(_targetBorrowRatio, _collateralFactor);

        while (
            !isWithinBorrowRatioTarget(
                _currentBorrowRatio,
                _scaledTargetBorrowRatio,
                _borrowRatioEpsilon
            )
        ) {
            // take identity scaledSafeMaxRatio = (daiOwed + daiToBorrow) / daiHeld), solve for daiToBorrow
            uint256 _daiToBorrow = mustMulExp(_scaledSafeMaxRatio, _daiHeld).sub(_daiOwed);

            // _nextBorrowRatio in [0, 0.75]
            uint256 _nextBorrowRatio =
                mustDivExp(_daiOwed.add(_daiToBorrow), _daiHeld.add(_daiToBorrow));

            // check if this should be the last loop, if so, attain the target
            if (_nextBorrowRatio > _scaledTargetBorrowRatio) {
                // we want: R_final = T
                // T = collateral factor * target
                // R_final = (B + ΔB) / (H + ΔB)
                // ΔB = (T * H - B) / (1 - T)
                _daiToBorrow = mustDivExp(
                    mustMulExp(_scaledTargetBorrowRatio, _daiHeld).sub(_daiOwed),
                    expScale - _scaledTargetBorrowRatio
                );
            }

            if (_daiToBorrow > _maxAvailableDAI) {
                _daiToBorrow = _maxAvailableDAI;
            }

            uint256 _err = cdai.borrow(_daiToBorrow);
            require(_err == 0, "dai borrow failed");

            dai.approve(address(cdai), _daiToBorrow);

            _err = cdai.mint(_daiToBorrow);
            require(_err == 0, "cdai mint failed");

            _daiHeld += _daiToBorrow;
            _daiOwed += _daiToBorrow;
            _currentBorrowRatio = mustDivExp(_daiOwed, _daiHeld);
        }
        emit Borrow(_daiHeld, _daiOwed);
    }

    /**
     * Repays DAI borrow to Compound
     */
    function repayDai(
        uint256 _currentBorrowRatio,
        uint256 _targetBorrowRatio,
        uint256 _borrowRatioEpsilon
    ) internal {
        uint256 _maxAvailableDAI = cdai.getCash();
        require(_maxAvailableDAI > 0, NO_DAI_AVAILABLE);

        (
            uint256 _oErr,
            uint256 _cdaiHeld, // units of cdai
            uint256 _daiOwed, // units of dai
            uint256 _exchangeRate
        ) = cdai.getAccountSnapshot(msg.sender);
        require(_oErr == 0, "getAccountSnapshot failed");

        uint256 _daiHeld = cdaiToDai(_cdaiHeld, _exchangeRate);

        uint256 _collateralFactor = getCdaiCollateralFactor();

        uint256 _scaledSafeMaxRatio = mustMulExp(safeMaxRatio, _collateralFactor);
        uint256 _scaledTargetBorrowRatio = mustMulExp(_targetBorrowRatio, _collateralFactor);

        _currentBorrowRatio = mustMulExp(_currentBorrowRatio, _collateralFactor);

        uint256 _totalAmountRepaid = 0;
        while (
            !isWithinBorrowRatioTarget(
                _currentBorrowRatio,
                _scaledTargetBorrowRatio,
                _borrowRatioEpsilon
            )
        ) {
            // take identity scaledSafeMaxRatio = daiHeld / (daiOwed - daiToRepay), solve for daiToRepay
            uint256 _daiToRepay = _daiHeld.sub(mustDivExp(_daiOwed, _scaledSafeMaxRatio));

            // _nextBorrowRatio in [0, 0.75]
            uint256 _nextBorrowRatio =
                mustDivExp(_daiOwed.sub(_daiToRepay), _daiHeld.sub(_daiToRepay));

            // check if this should be the last loop, if so, attain the target
            if (_nextBorrowRatio < _scaledTargetBorrowRatio) {
                // we want: R_final = T
                // T = collateral factor * target
                // R_final = (B - ΔB) / (H - ΔB)
                // ΔB = (RH-B)/ (R-1) = (B-RH) / (1-R)
                _daiToRepay = mustDivExp(
                    _daiOwed - mustMulExp(_scaledTargetBorrowRatio, _daiHeld),
                    expScale - _scaledTargetBorrowRatio
                );
            }

            if (_daiToRepay > _maxAvailableDAI) {
                _daiToRepay = _maxAvailableDAI;
            }

            uint256 _err = cdai.redeemUnderlying(_daiToRepay);
            require(_err == 0, "redeemUnderlying failed");

            _err = cdai.repayBorrow(_daiToRepay);
            require(_err == 0, "repayBorrow failed");

            _totalAmountRepaid += _daiToRepay;

            _daiHeld -= _daiToRepay;
            _daiOwed -= _daiToRepay;
            _currentBorrowRatio = mustDivExp(_daiOwed, _daiHeld);
        }

        emit Repay(_totalAmountRepaid, _daiHeld, _daiOwed);
    }

    /**
     * Supplies all our DAI to Compound cDAI pool
     */
    function supplyDai() internal {
        uint256 daiBalance = dai.balanceOf(msg.sender);
        if (daiBalance == 0) {
            return;
        }
        dai.approve(address(cdai), daiBalance);
        uint256 error = cdai.mint(daiBalance);
        require(error == 0, "supplyDai: mint failed");
    }

    function computeCdaiTarget(
        uint256 tokensHeld,
        uint256 targetBorrowRatio,
        uint256 collateralFactor
    ) internal pure returns (uint256) {
        // cdaiTarget = (targetBorrowRatio * tokensHeld * collateralFactor)
        return mustMulExp3(targetBorrowRatio, tokensHeld, collateralFactor);
    }

    function cdaiToDai(uint256 cdaiAmount, uint256 exchangeRate) internal pure returns (uint256) {
        return mustDivExp(cdaiAmount, exchangeRate);
    }

    /**
     * Rebalances the assets
     * Only executes if the current borrow ratio is below the minimum borrow
     * ratio or above the target borrow ratio
     * After the rebalance, the borrow ratio should be equal to the target borrow ratio
     * @param _minBorrowRatio the minimum ratio to be borrowed between 0 to 1
     * @param _targetBorrowRatio the target ratio to be borrowed between 0 to 1
     * @param _maxBorrowRatio the maximum ratio to be borrowed between 0 to 1
     * @param _minimumDaiIncrease is the minimum amount of DAI to get in exchange for COMP tokens
     */
    function rebalance(
        uint256 _minBorrowRatio,
        uint256 _targetBorrowRatio,
        uint256 _maxBorrowRatio,
        uint256 _borrowRatioEpsilon,
        uint256 _minimumDaiIncrease
    ) external override {
        // TODO: check which contract is interacting with Compound
        // and send the cDAI back to the vault
        sellComp(_minimumDaiIncrease);
        supplyDai();

        uint256 _currentBorrowRatio = computeBorrowRatio(msg.sender);

        if (_currentBorrowRatio < _minBorrowRatio) {
            borrowDai(_currentBorrowRatio, _targetBorrowRatio, _borrowRatioEpsilon);
        } else if (_currentBorrowRatio > _maxBorrowRatio) {
            repayDai(_currentBorrowRatio, _targetBorrowRatio, _borrowRatioEpsilon);
        } else {
            revert(CANNOT_REBALANCE);
        }
    }
}
