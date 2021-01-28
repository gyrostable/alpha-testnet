//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Exponential.sol";
import "./uniswap/UniswapExchangeInterface.sol";
import "./balancer/BPool.sol";

import "./Keeper.sol";
import "./CDaiVault.sol";
import "./Exponential.sol";

import "hardhat/console.sol";

contract BPTKeeper is Exponential {
    using SafeMath for uint256;

    uint256 public constant slippage = 0.5e18;

    BPool private balancerPool;

    BPool public ethBalPool;

    address[] public tokenPools;

    address public balAddress;
    address public wethAddress;

    constructor(
        address _balancerPoolAddress,
        address _balAddress,
        address _wethAddress,
        address _ethBalPoolAddress,
        address[] memory _tokenPools
    ) {
        balancerPool = BPool(_balancerPoolAddress);
        address[] memory tokens = balancerPool.getFinalTokens();
        require(
            tokens.length == _tokenPools.length,
            "_tokenPools should have the same number of tokens as the balancer pool"
        );
        balAddress = _balAddress;
        wethAddress = _wethAddress;
        ethBalPool = BPool(_ethBalPoolAddress);
        tokenPools = _tokenPools;
    }

    /**
     * Rebalances the assets
     */
    function rebalance() external {
        // TODO: claim BAL rewards
        uint256 _balBalance = balancerPool.balanceOf(msg.sender);

        (uint256 _wethAmount, ) = ethBalPool.swapExactAmountIn(
            balAddress,
            _balBalance,
            wethAddress,
            0,
            0 // TODO: get this from oracle
        );

        address[] memory _tokens = balancerPool.getFinalTokens();
        uint256[] memory _swappedAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _weight = balancerPool.getNormalizedWeight(_tokens[i]);
            uint256 _tokenWethAmount = mustMulExp(_wethAmount, _weight);
            // TODO: check if we want to use uniswap here instead
            BPool _pool = BPool(tokenPools[i]);

            (uint256 _outAmount, ) = _pool.swapExactAmountIn(
                wethAddress,
                _tokenWethAmount,
                _tokens[i],
                0,
                0 // TODO: get this from oracle
            );
            _swappedAmounts[i] = _outAmount;
        }

        uint256 _poolSupply = balancerPool.totalSupply();
        uint256 _firstAssetBalance = balancerPool.getBalance(_tokens[0]);
        uint256 _supplyRatio = mustDivExp(
            _swappedAmounts[0],
            _firstAssetBalance
        );
        uint256 _targetAmountOut = mustMulExp3(
            _supplyRatio,
            _poolSupply,
            expScale - slippage
        );
        balancerPool.joinPool(_targetAmountOut, _swappedAmounts);

        balancerPool.transfer(msg.sender, _targetAmountOut);
    }
}
