import pytest


@pytest.fixture(scope="session")
def admin(accounts):
    yield accounts[0]
