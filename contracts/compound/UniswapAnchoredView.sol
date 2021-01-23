//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.8;

interface UniswapAnchoredView {
    function price(string calldata symbol) external view returns (uint256);
}
