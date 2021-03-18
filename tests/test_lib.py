from tests.utils import scale


def test_mint(gyrolib, gyro_fund_v1, dai, usdc, admin):
    assert gyro_fund_v1.balanceOf(admin) == 0
    assert gyro_fund_v1.totalSupply() == 0

    dai_amount = scale(100)
    usdc_amount = scale(100, 6)

    dai_balance = dai.balanceOf(admin)
    dai.approve(gyrolib.address, dai_amount)
    usdc.approve(gyrolib.address, usdc_amount)

    tx = gyrolib.mintFromUnderlyingTokens(
        [dai.address, usdc.address], [dai_amount, usdc_amount], 0
    )
    new_dai_balance = dai.balanceOf(admin)

    assert new_dai_balance == dai_balance - dai_amount

    assert len(tx.events) > 0
    minted = tx.events["Mint"]["amount"]
    assert minted > 0
    assert gyro_fund_v1.balanceOf(admin) == minted


def test_redeem(gyrolib, gyro_fund_v1, dai, usdc, admin):
    dai_amount = scale(1000)
    usdc_amount = scale(1000, 6)

    dai.approve(gyrolib.address, dai_amount)
    usdc.approve(gyrolib.address, usdc_amount)

    mint_tx = gyrolib.mintFromUnderlyingTokens(
        [dai.address, usdc.address], [dai_amount, usdc_amount], 0
    )
    minted = mint_tx.events["Mint"]["amount"]

    dai_out = scale(2)
    dai_balance = dai.balanceOf(admin)
    max_out = dai_out  # no slippage expected
    gyro_fund_v1.approve(gyrolib, max_out)
    redeem_tx = gyrolib.redeemToUnderlyingTokens([dai], [dai_out], max_out)
    redeemed = redeem_tx.events["Redeem"]["amount"]

    new_dai_balance = dai.balanceOf(admin)
    assert new_dai_balance == dai_balance + dai_out
    assert gyro_fund_v1.balanceOf(admin) == minted - redeemed
