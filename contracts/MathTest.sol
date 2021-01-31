// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./abdk/ABDKMath64x64.sol";
import "./ExtendedMath.sol";

contract MathTest {
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;
    using ExtendedMath for int128;
    using ExtendedMath for uint256;

    uint256 constant expScale = 1e18;

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
