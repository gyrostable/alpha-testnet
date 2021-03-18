//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
import "../ExtendedMath.sol";

contract MathTesting {
    using ExtendedMath for uint256;

    function scaledPow(uint256 a, uint256 b) public pure returns (uint256) {
        return a.scaledPow(b);
    }

    function scaledPowTransact(uint256 a, uint256 b) public {
        scaledPow(a, b);
    }

    /**
     * @return value * (base ** exponent)
     */
    function mulPow(
        uint256 value,
        uint256 base,
        uint256 exponent,
        uint256 decimal
    ) external pure returns (uint256) {
        return value.mulPow(base, exponent, decimal);
    }
}
