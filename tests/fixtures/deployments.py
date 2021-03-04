import pytest
import brownie

from .accounts import *


@pytest.fixture
def math(MathTesting, admin):
    return admin.deploy(MathTesting)
