//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Ownable.sol";
import "./compound/CTokenInterfaces.sol";
import "./compound/ComptrollerInterface.sol";
import "./BPTKeeper.sol";
import "./Exponential.sol";
import "./CompoundCore.sol";
import "./compound/UniswapAnchoredView.sol";
import "./balancer/BPool.sol";

contract BPTFund is Ownable, ERC20, Exponential {
    using SafeMath for uint256;

    BPool private balancerPool;

    address public balAddress;
    address public wethAddress;

    struct BorrowRatio {
        uint256 minimum;
        uint256 target;
        uint256 maximum;
        uint256 epsilon;
    }
    uint256 constant slippageRatio = 0.97e18;

    BorrowRatio public intendedBorrowRatio;

    constructor(
        address _balancerPoolAddress,
        address _balAddress,
        address _wethAddress
    ) ERC20("Fund BPT", "gBPT") {
        balancerPool = BPool(_balancerPoolAddress);
        balAddress = _balAddress;
        wethAddress = _wethAddress;

        intendedBorrowRatio.minimum = 0.95e18;
        intendedBorrowRatio.target = 0.97e18;
        intendedBorrowRatio.maximum = 0.99e18;
        intendedBorrowRatio.epsilon = 0.005e18;
    }

    /**
     * Calculate the net asset value of the entire vault
     * @return nav in units of BPT
     */
    function nav() internal view returns (uint256) {
        return balancerPool.balanceOf(address(this));
    }

    function transferFromSender(uint256 _amount) internal returns (bool _success) {
        _success = balancerPool.transferFrom(msg.sender, address(this), _amount);
        return _success;
    }

    function transferToSender(uint256 _amount) internal returns (bool _success) {
        _success = balancerPool.transfer(msg.sender, _amount);
        return _success;
    }

    /**
     * Deposit funds
     * Given an input amount of BPT
     * @param _amount the number of BP tokens to deposit
     */
    function deposit(uint256 _amount) public {
        bool success = transferFromSender(_amount);
        require(success, "transfer from sender failed");

        uint256 _shares = 0;
        uint256 _currentSupply = totalSupply();
        if (_currentSupply == 0) {
            _shares = _amount;
        } else {
            uint256 _nav = nav();
            // nav / currentSupply == amount / share
            // share == amount * currentSupply / nav
            _shares = mustDivExp(mustMulExp(_amount, _currentSupply), _nav);
        }
        _mint(msg.sender, _shares);
    }

    /**
     * Withdraws the deposited funds
     * @param _sharesToRedeem is the number of shares to be redeemed
     */
    function withdraw(uint256 _sharesToRedeem) external {
        withdraw(_sharesToRedeem, address(0x0));
    }

    /**
     * Withdraws `_sharesToRedeem` from the funds
     * @param _sharesToRedeem is the number of shares to be redeemed
     * @dev second parameter needed to comply with the Fund interface but not used here
     */
    function withdraw(uint256 _sharesToRedeem, address) public {
        uint256 _nav = nav();
        uint256 _amountToWithdraw = mustDivExp(mustMulExp(_nav, _sharesToRedeem), totalSupply());
        _burn(msg.sender, _sharesToRedeem);
        transferToSender(_amountToWithdraw);
    }

    fallback() external {
        revert("fallback function should not be called");
    }

    function getPrice()
        public
        pure
        returns (
            //address _baseAddress, address _quoteAddress)
            uint256
        )
    {
        return 1;
    }

    function rebalance(address _keeperAddress) public {
        // TODO: check that pool is balanced
        // and find token with highest volume
        uint256 _highestVolumeTokenIndex = 0;

        uint256 _balBalance = balancerPool.balanceOf(msg.sender);

        uint256 _wethAmount =
            mustDivExp(
                _balBalance,
                getPrice() //(wethAddress, balAddress)
            );

        address[] memory _tokens = balancerPool.getFinalTokens();
        uint256 _weight = balancerPool.getNormalizedWeight(_tokens[_highestVolumeTokenIndex]);

        uint256 _outAmount =
            mustMulExp3(
                getPrice(), //(wethAddress, _tokens[0]), // TODO: double-check base/quote order
                _wethAmount,
                _weight
            );

        // TODO: make the slippage ratio dependent on the amount of BAL to sell
        uint256 _poolSupply = balancerPool.totalSupply();
        uint256 _firstAssetBalance = balancerPool.getBalance(_tokens[_highestVolumeTokenIndex]);
        uint256 _supplyRatio = mustDivExp(_outAmount, _firstAssetBalance);
        uint256 _targetAmountOut = mustMulExp3(_supplyRatio, _poolSupply, expScale - slippageRatio);
        uint256 _currentBalance = balancerPool.balanceOf(address(this));
        BPTKeeper(_keeperAddress).rebalance();
        uint256 _newBalance = balancerPool.balanceOf(address(this));
        require(
            _currentBalance.add(_targetAmountOut) <= _newBalance,
            "keeper did not generate enough BPT"
        );
    }
}
