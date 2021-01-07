//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";

interface GyroPriceOracle {
    function getAmountToMint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn
    ) external view returns (uint256);

    function getAmountsToPayback(
        uint256 _gyroAmount,
        address[] memory _tokensOut
    ) external view returns (uint256[] memory _amountsOut);
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
}
