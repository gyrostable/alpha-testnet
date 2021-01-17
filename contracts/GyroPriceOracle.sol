//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
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

    function getBptPrice(
        address _bptAddress,
        uint256[] _underlyingPrices
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

    function getBptPrice(
        address _bptAddress,
        uint256[] _underlyingPrices
    ) external view returns (uint256 _bptPrice) {
        /* TODO:
            bptSupply = # of BPT tokens
            bpWeights = array of pool weights (require _underlyingPrices comes in same order)
            k = constant = product of reserves^weight
            bptPrice = (k * product of (p_i / w_i)^w_i ) / btpSupply

            functions from ABDKMath64x64 library
            -- exp_2 = binary exponent
            -- log_2 = binary logarithm
            -- mul = calculate x*y

            x^y = 2^(y log_2 x)
            exp_2( mul(y, log_2(x)) )
        */
        uint256 bptSupply;
        uint256[] bpWeights;
        uint256 _k = 1;
        for (uint256 i=0; i < bpWeights.length; i++) {
            _k = mustMulExp(_k, )
        }

    }
}
