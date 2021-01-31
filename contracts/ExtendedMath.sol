//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./abdk/ABDKMath64x64.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

library ExtendedMath {
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using SafeMath for uint256;

    uint256 constant decimalScale = 1e18;

    function powf(int128 _x, int128 _y) internal pure returns (int128 _xExpy) {
        // 2^(y * log2(x))
        return _y.mul(_x.log_2()).exp_2();
    }

    /**
     * @return value * (base ** exponent)
     */
    function mulPow(
        uint256 value,
        uint256 base,
        uint256 exponent,
        uint256 decimal
    ) internal pure returns (uint256) {
        int128 basef = base.fromScaled(decimal);
        int128 expf = exponent.fromScaled(decimal);
        return powf(basef, expf).mulu(value);
    }

    function scaledMul(
        uint256 a,
        uint256 b,
        uint256 decimals
    ) internal pure returns (uint256) {
        return a.mul(b).div(decimals);
    }

    function scaledMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return scaledMul(a, b, decimalScale);
    }

    function scaledDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return scaledDiv(a, b, decimalScale);
    }

    function scaledDiv(
        uint256 a,
        uint256 b,
        uint256 decimals
    ) internal pure returns (uint256) {
        return a.mul(decimals).div(b);
    }
}
