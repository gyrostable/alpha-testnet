//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./compound/Exponential.sol" as E;

contract Exponential is E.Exponential {
    function mustMulExp(uint256 a, uint256 b) internal pure returns (uint256) {
        (MathError err, Exp memory result) = mulExp(a, b);
        require(err == MathError.NO_ERROR, "math failed");
        return result.mantissa;
    }

    function mustMulExp3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return mustMulExp(mustMulExp(a, b), c);
    }

    function mustDivExp(uint256 a, uint256 b) internal pure returns (uint256) {
        (MathError err, Exp memory result) = divExp(
            Exp({mantissa: a}),
            Exp({mantissa: b})
        );
        require(err == MathError.NO_ERROR, "math failed");
        return result.mantissa;
    }
}
