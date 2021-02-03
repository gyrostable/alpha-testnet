import { BigNumber } from "ethers";
import hre from "hardhat";
import { BPool__factory as BPoolFactory } from "../typechain/factories/BPool__factory";
import { GyroFund__factory as GyroFundFactory } from "../typechain/factories/GyroFund__factory";
const { deployments, ethers } = hre;

const amountToMint = 100;
const poolNames = ["usdc_weth", "weth_dai"];

async function main() {
  const [account] = await ethers.getSigners();
  const gyroFundDeployment = await deployments.get("GyroFundV1");
  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, account);
  const poolsDeployments = await Promise.all(poolNames.map((p) => deployments.get(`BPool${p}`)));
  const poolAddresses = poolsDeployments.map((p) => p.address);

  const ten = BigNumber.from(10).pow(BigNumber.from(19));
  await Promise.all(
    poolAddresses.map((a) => BPoolFactory.connect(a, account).approve(gyroFund.address, ten))
  );

  const mintedAmount = BigNumber.from(10).pow(18).mul(amountToMint);
  const tx = await gyroFund.mintTest(poolAddresses, [ten, ten], mintedAmount);
  await tx.wait();

  const balance = await gyroFund.balanceOf(account.address);
  const readableBalance = balance.div(BigNumber.from(10).pow(18)).toString();
  console.log(`GyroFund balance: ${readableBalance}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
