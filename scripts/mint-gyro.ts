import BN from "bn.js";
import hre from "hardhat";
import { BPool__factory as BPoolFactory } from "../typechain/factories/BPool__factory";
import { GyroFund__factory as GyroFundFactory } from "../typechain/factories/GyroFund__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const wethDaiPoolDeployment = await deployments.get("BPoolweth_dai");
  const gyroFundDeployment = await deployments.get("GyroFundV1");
  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, account);
  const wethDaiPool = BPoolFactory.connect(wethDaiPoolDeployment.address, account);

  const ten = new BN(10).pow(new BN(19)).toString();
  await wethDaiPool.approve(gyroFund.address, ten);
  await gyroFund.mint([wethDaiPool.address], [ten], 0);

  const balance = await gyroFund.balanceOf(account.address);
  const readableBalance = balance.div(new BN(10).pow(new BN(18)).toString());
  console.log(`GyroFund balance: ${readableBalance}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
