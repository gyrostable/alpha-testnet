//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./abdk/ABDKMath64x64.sol";

library ExtendedMath {
    using ABDKMath64x64 for int128;

    function powf(int128 _x, int128 _y) external pure returns (int128 _xExpy) {
        // 2^(y * log2(x))
        return _y.mul(_x.log_2()).exp_2();
    }
}
