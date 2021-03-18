from tests.utils import scale


def test_underlying_addresses(gyro_fund_v1, tokens):
    underlying_addresses = gyro_fund_v1.getUnderlyingTokenAddresses()
    assert len(underlying_addresses) == len(tokens)
    assert underlying_addresses[0] == tokens[0].address


def test_pool_addresses(gyro_fund_v1, pools):
    pool_addresses = gyro_fund_v1.poolAddresses()
    assert len(pool_addresses) == len(pools)
    assert pool_addresses[0] == pools[0].address


def test_basic_mint(gyro_fund_v1, pools, admin):
    assert gyro_fund_v1.balanceOf(admin.address) == 0
    assert gyro_fund_v1.totalSupply() == 0

    amounts = [scale(10)] * len(pools)
    tx = gyro_fund_v1.mint(pools, amounts, 0)
    assert len(tx.events) > 0
    mint_event = tx.events["Mint"]
    assert mint_event["minter"] == admin.address
    minted = mint_event["amount"]
    assert minted > 0

    assert gyro_fund_v1.balanceOf(admin.address) == minted

    assert gyro_fund_v1.totalSupply() == minted


def test_basic_redeem(gyro_fund_v1, pools, admin):
    assert gyro_fund_v1.balanceOf(admin.address) == 0
    assert gyro_fund_v1.totalSupply() == 0

    mint_amounts = [scale(10)] * len(pools)
    tx_mint = gyro_fund_v1.mint(pools, mint_amounts, 0)
    minted = tx_mint.events["Mint"]["amount"]

    redeem_amounts = [scale(1)] * len(pools)
    max_redeemed = minted // 8
    tx_redeem = gyro_fund_v1.redeem(pools, redeem_amounts, max_redeemed)
    assert len(tx_redeem.events) > 0
    redeemed = tx_redeem.events["Redeem"]["amount"]
    assert redeemed <= max_redeemed

    assert gyro_fund_v1.balanceOf(admin.address) == minted - redeemed
