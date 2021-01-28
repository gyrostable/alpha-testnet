//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface Keeper {
    function rebalance(
        uint256 _minBorrowRatio,
        uint256 _targetBorrowRatio,
        uint256 _maxBorrowRatio,
        uint256 _borrowRatioEpsilon,
        uint256 _minimumDaiIncrease
    ) external;
}
