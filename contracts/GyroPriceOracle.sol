//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "./balancer/bPool.sol";
import "./abdk/ABDKMath64x64.sol";

interface GyroPriceOracle {
    function getAmountToMint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn
    ) external view returns (uint256);

    function getAmountsToPayback(
        uint256 _gyroAmount,
        address[] memory _tokensOut
    ) external view returns (uint256[] memory _amountsOut);

    function fracPow(
        int128 _x,
        int128 _y
    ) external view returns (int128 _xExpy);

    function getBptPrice(
        address _bPoolAddress,
        mapping(address => uint256) _underlyingPrices
    ) external view returns (uint256 _bptPrice);
}

contract DummyGyroPriceOracle is GyroPriceOracle {
    function getAmountToMint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn
    ) external pure override returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            result += _amountsIn[i];
        }
        return result;
    }

    function getAmountsToPayback(
        uint256 _gyroAmount,
        address[] memory _tokensOut
    ) external pure override returns (uint256[] memory _amountsOut) {
        uint256[] memory amounts = new uint256[](_tokensOut.length);
        for (uint256 i = 0; i < _tokensOut.length; i++) {
            amounts[i] = _gyroAmount / _tokensOut.length;
        }
        return amounts;
    }

    // calculates _x^_y where _x,_y are decimals
    function fracPow(
        int128 _x,
        int128 _y
    ) external view returns (int128 _xExpy) {
        _xExpy = exp_2( mul(_y, log_2(_x)) );
        return _xExpy;
    }

    function getBptPrice(
        address _bPoolAddress,
        mapping(address => uint256) _underlyingPrices
    ) external view returns (uint256 _bptPrice) {
        /* calculations:
            bptSupply = # of BPT tokens
            bPoolWeights = array of pool weights (require _underlyingPrices comes in same order)
            k = constant = product of reserves^weight
            bptPrice = (k * product of (p_i / w_i)^w_i ) / bptSupply

            functions from ABDKMath64x64 library
            -- exp_2 = binary exponent
            -- log_2 = binary logarithm
            -- mul = calculate x*y

            x^y = 2^(y log_2 x)
            exp_2( mul(y, log_2(x)) )
        */
        BPool _bPool = BPool(_bPoolAddress);
        uint256 _bptSupply = bPool.totalSupply();
        address[] memory _tokens = balancerPool.getFinalTokens();
        int128 _weight;
        int128 _price;
        int128 _tokenBalance;
        int128 _k = fromUInt(1); // check that these are the right to get value 1
        int128 _weightedProd = fromUInt(1);
        for (uint256 i=0; i< _tokens.length; i++) {
            _weight = fromUInt(_bPool.getNormalizedWeight(_tokens[i]));
            _price = fromUint(_underlyingPrices[_tokens[i]]);
            _tokenBalance = fromUInt(_bPool.getBalance(_tokens[i]));
            _k = mul(_k, fracPow(_tokenBalance, _weight));
            _weightedProd = mul(_weightedProd, fracPow( div(_price, _weight), _weight) );
        }
        int128 _priceBPT = div( mul(_k, _weightedProd), _bptSupply );
        return _priceBPT;

    }
}
