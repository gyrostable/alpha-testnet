import { BigNumber } from "ethers";
import hre from "hardhat";
import { GyroFund__factory as GyroFundFactory } from "../typechain/factories/GyroFund__factory";
const { deployments, ethers } = hre;

async function main() {
  const poolNames = ["usdc_weth", "weth_dai"];
  const [account] = await ethers.getSigners();
  const gyroFundDeployment = await deployments.get("GyroFundV1");
  const poolsDeployments = await Promise.all(poolNames.map((p) => deployments.get(`BPool${p}`)));
  const poolAddresses = poolsDeployments.map((v) => v.address);

  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, account);
  const amounts = [1, 2].map((v) => BigNumber.from(v).mul(BigNumber.from(10).pow(16)));

  const maxRedeemed = BigNumber.from(50).mul(BigNumber.from(10).pow(18));

  const tx = await gyroFund.redeem(poolAddresses, amounts, maxRedeemed);
  await tx.wait();

  // const ten = new BN(10).pow(new BN(19)).toString();
  // const mintedAmount = new BN(10).pow(new BN(18)).mul(new BN(amountToMint)).toString();
  // await wethDaiPool.approve(gyroFund.address, ten);
  // const tx = await gyroFund.mintTest([wethDaiPool.address], [ten], mintedAmount);
  // await tx.wait();

  const balance = await gyroFund.balanceOf(account.address);
  const readableBalance = balance.div(BigNumber.from(10).pow(18));
  console.log(`GyroFund balance: ${readableBalance}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
