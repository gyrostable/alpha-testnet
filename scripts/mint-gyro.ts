import { Contract } from "ethers";
import hre from "hardhat";
const { deployments, ethers } = hre;

import BN from "bn.js";

import { ERC20 } from "../typechain/ERC20";
import { BPool } from "../typechain/BPool";
import { GyroFund } from "../typechain/GyroFund";

async function main() {
  const [account] = await ethers.getSigners();
  const wethDaiPoolDeployment = await deployments.get("BPoolweth_dai");
  const gyroFundDeployment = await deployments.get("GyroFundV1");
  const gyroFund = new Contract(
    gyroFundDeployment.address,
    gyroFundDeployment.abi,
    account
  ) as GyroFund;
  const wethDaiPool = new Contract(
    wethDaiPoolDeployment.address,
    wethDaiPoolDeployment.abi,
    account
  ) as BPool;

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
