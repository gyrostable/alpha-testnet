//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface GyroRouter {
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        returns (address[] memory, uint256[] memory);

    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        returns (address[] memory, uint256[] memory);
}
