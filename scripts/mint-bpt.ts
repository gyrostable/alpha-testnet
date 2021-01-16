import { Contract } from "ethers";
import hre from "hardhat";
const { deployments, ethers } = hre;

import BN from "bn.js";

import { ERC20 } from "../typechain/ERC20";
import { BPool } from "../typechain/BPool";

async function main() {
  const [account] = await ethers.getSigners();
  const wethDaiPoolDeployment = await deployments.get("BPoolweth_dai");
  const wethDeployment = await deployments.get("WETHERC20");
  const daiDeployment = await deployments.get("DAIERC20");

  const MILLION = new BN(10).pow(new BN(24));

  const dai = new Contract(daiDeployment.address, daiDeployment.abi, account) as ERC20;
  await dai.approve(wethDaiPoolDeployment.address, MILLION.toString());

  const weth = new Contract(wethDeployment.address, wethDeployment.abi, account) as ERC20;
  await weth.approve(wethDaiPoolDeployment.address, MILLION.toString());

  const wethDaiPool = new Contract(
    wethDaiPoolDeployment.address,
    wethDaiPoolDeployment.abi,
    account
  ) as BPool;

  const ethAmount = new BN(2).mul(new BN(10).pow(new BN(18))).toString();
  const daiAmount = new BN(2500).mul(new BN(10).pow(new BN(18))).toString();

  await wethDaiPool.joinswapExternAmountIn(weth.address, ethAmount, 0);
  await wethDaiPool.joinswapExternAmountIn(dai.address, daiAmount, 0);

  const poolBalance = await wethDaiPool.balanceOf(account.address);
  const readablePoolBalance = poolBalance.div(new BN(10).pow(new BN(18)).toString());
  console.log(`WETH/DAI pool balance: ${readablePoolBalance}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
