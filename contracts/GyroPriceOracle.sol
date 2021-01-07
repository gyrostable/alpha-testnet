//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";

contract GyroPriceOracle {
    function getAmountToMint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn
    ) public view returns (uint256) {}

    function getAmountsToPayback(
        uint256 _gyroAmount,
        address[] memory _tokensOut
    ) public view returns (uint256[] memory _amountsOut) {}
}
