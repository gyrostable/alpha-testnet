from decimal import Decimal
from typing import Union


def scale(n: Union[int, str, Decimal], decimals: int = 18):
    return Decimal(n) * 10 ** decimals
