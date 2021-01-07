//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface GyroRouter {
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external;

    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external;
}
