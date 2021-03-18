import math
from decimal import Decimal, ROUND_FLOOR, getcontext

import pytest
from brownie.test import given, strategy

from tests.utils import scale


def test_single_scaled_pow(math_testing):
    base = 61339
    exp = 1_000_000
    scaled_base = Decimal(base) / Decimal(10 ** 18)
    result = math_testing.scaledPow(base, exp)
    scaled_result = Decimal(result) / Decimal(10 ** 18)
    assert scaled_result == pytest.approx(scaled_base ** exp)
    math_testing.scaledPowTransact(base, exp)


@given(
    base=strategy("uint256", max_value=10 ** 18),
    exp=strategy("uint256", min_value=1, max_value=50_000),
)
def test_scaled_pow(math_testing, base, exp):
    scaled_base = Decimal(base) / Decimal(10 ** 18)
    result = math_testing.scaledPow(base, exp)
    scaled_result = Decimal(result) / Decimal(10 ** 18)
    assert scaled_result == pytest.approx(scaled_base ** exp)


def test_mul_pow(math_testing):
    for decimal in range(2, 19):
        value = scale(180, decimal)
        base = scale("8.5", decimal)
        exponent = scale("0.6", decimal)

        getcontext().rounding = ROUND_FLOOR
        expected = float(round(180 * Decimal("8.5") ** Decimal("0.6"), decimal))
        result = math_testing.mulPow(value, base, exponent, decimal) / 10 ** decimal
        assert result == pytest.approx(expected)

    # should compute k correctly
    k = scale(1, 18)
    balance = scale(50_000, 18)
    weight = scale(5, 17)
    result = float(math_testing.mulPow(k, balance, weight, 18))
    expected = float(scale(50_000 ** Decimal("0.5")))
    assert result == pytest.approx(expected, rel=0.0001)

    expected = float(scale(50_000, 18))
    result = float(math_testing.mulPow(result, balance, weight, 18))
    assert result == pytest.approx(expected, rel=0.0001)
