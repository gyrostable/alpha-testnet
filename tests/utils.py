from decimal import Decimal
from typing import Union


def scale(n: Union[int, str], decimals: int = 18):
    return round(Decimal(n) * 10 ** decimals, 0)
