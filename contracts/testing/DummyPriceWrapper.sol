// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "../GyroPriceOracle.sol";

/**
 * Dummy price oracle used for testing
 */
contract DummyPriceWrapper is PriceOracle {
    function getPrice(string memory tokenSymbol) public pure override returns (uint256) {
        bytes32 symbolHash = keccak256(bytes(tokenSymbol));
        if (symbolHash == keccak256(bytes("DAI"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("BUSD"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("sUSD"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("USDC"))) {
            return 1e6;
        } else if (symbolHash == keccak256(bytes("WETH"))) {
            return 2000e18; // NOTE: make sure this matches the hard-coded price in tests
        } else {
            revert("symbol not supported");
        }
    }
}
