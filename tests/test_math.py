import pytest
from decimal import Decimal

from brownie.test import given, strategy


def scale(n, decimals=18):
    return n * 10 ** decimals


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
