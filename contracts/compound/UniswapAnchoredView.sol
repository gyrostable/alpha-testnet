//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface UniswapAnchoredView {
    function price(string calldata symbol) external view returns (uint256);
}
