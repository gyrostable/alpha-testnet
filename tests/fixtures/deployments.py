import math
from decimal import Decimal

import brownie
import pytest
from tests.utils import scale

from .accounts import *

ETH_USD = 2_000
BPOOL_AMOUNT = 50_000
PRICES = {"WETH": ETH_USD}


@pytest.fixture
def math_testing(MathTesting, admin):
    return admin.deploy(MathTesting)


@pytest.fixture
def gyro_price_oracle_v1(GyroPriceOracleV1, admin):
    return admin.deploy(GyroPriceOracleV1)


@pytest.fixture
def dummy_price_oracle(DummyPriceWrapper, admin):
    return admin.deploy(DummyPriceWrapper)


@pytest.fixture
def balancer_token_router(BalancerTokenRouter, admin):
    router = admin.deploy(BalancerTokenRouter)
    router.initializeOwner()
    return router


@pytest.fixture
def external_token_router(BalancerExternalTokenRouter, admin, pools):
    router = admin.deploy(BalancerExternalTokenRouter)
    router.initializeOwner()
    for pool in pools:
        router.addPool(pool.address)
    return router


@pytest.fixture
def gyro_fund_v1(
    GyroFundV1,
    admin,
    balancer_token_router,
    gyro_price_oracle_v1,
    dummy_price_oracle,
    tokens,
    pools,
):
    fund = admin.deploy(GyroFundV1)
    fund.initializeOwner()
    init_args = [
        scale("0.1"),  # portfolio_weight_epsilon
        gyro_price_oracle_v1.address,
        balancer_token_router.address,
        scale("0.999993123563518195"),  # memory param
    ]
    fund.initialize(*init_args)
    for token in tokens:
        is_stable = token.symbol() != "WETH"
        fund.addToken(token.address, dummy_price_oracle.address, is_stable)
    for i, pool in enumerate(pools):
        raw_weight = 100 / len(pools)
        weight = math.ceil(raw_weight) if i == 0 else math.floor(raw_weight)
        fund.addPool(pool.address, scale(weight, 16))
        pool.approve(fund.address, 10 ** 50)

    return fund


@pytest.fixture
def gyrolib(GyroLib, admin, gyro_fund_v1, external_token_router, tokens):
    lib = admin.deploy(GyroLib, gyro_fund_v1.address, external_token_router.address)
    lib.initializeOwner()
    return lib


def create_pool(admin, bfactory, BPool, tokens):
    deploy_tx = bfactory.newBPool()
    bpool = BPool.at(deploy_tx.events["LOG_NEW_POOL"]["pool"], owner=admin)

    for token_info in tokens:
        token = token_info["contract"]
        token_price = PRICES.get(token.symbol(), 1)
        raw_balance = token_info.get("balance", BPOOL_AMOUNT)
        balance = scale(raw_balance // token_price, token.decimals())
        token.approve(bpool.address, balance)
        bpool.bind(token.address, balance, scale(token_info.get("weight", 5)))

    bpool.setSwapFee(scale("0.0001"))
    bpool.finalize()

    return bpool


def create_token(admin, TokenFaucet, name, symbol, decimals, mint_amount):
    token = admin.deploy(TokenFaucet, name, symbol, decimals, scale(mint_amount))
    token.initializeOwner()
    token.mintAsOwner(admin, scale(mint_amount * 1_000))
    return token


@pytest.fixture
def dai(admin, TokenFaucet):
    return create_token(admin, TokenFaucet, "Dai Stablecoin", "DAI", 18, 1_000)


@pytest.fixture
def busd(admin, TokenFaucet):
    return create_token(admin, TokenFaucet, "Binance USD", "BUSD", 18, 1_000)


@pytest.fixture
def usdc(admin, TokenFaucet):
    return create_token(admin, TokenFaucet, "USD Coin", "USDC", 6, 1_000)


@pytest.fixture
def weth(admin, TokenFaucet):
    return create_token(admin, TokenFaucet, "Wrapped Ether", "WETH", 18, 1)


@pytest.fixture
def bfactory(admin, BFactory):
    return admin.deploy(BFactory)


@pytest.fixture
def weth_dai_pool(admin, bfactory, BPool, weth, dai):
    eth_token = {"contract": weth}
    dai_token = {"contract": dai}
    return create_pool(admin, bfactory, BPool, [eth_token, dai_token])


@pytest.fixture
def usdc_busd_pool(admin, bfactory, BPool, usdc, busd):
    usdc_token = {"contract": usdc}
    busd_token = {"contract": busd}
    return create_pool(admin, bfactory, BPool, [usdc_token, busd_token])


@pytest.fixture
def tokens(usdc, dai, weth, busd):
    return [usdc, dai, weth, busd]


@pytest.fixture
def pools(usdc_busd_pool, weth_dai_pool):
    return [usdc_busd_pool, weth_dai_pool]
