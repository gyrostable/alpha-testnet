import BN from "bn.js";
import hre from "hardhat";
import { BPool__factory as BPoolFactory } from "../typechain/factories/BPool__factory";
import { ERC20__factory as ERC20Factory } from "../typechain/factories/ERC20__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const wethDaiPoolDeployment = await deployments.get("pool-dai_weth");
  const wethDeployment = await deployments.get("token-WETH");
  const daiDeployment = await deployments.get("token-DAI");

  const MILLION = new BN(10).pow(new BN(24));

  const dai = ERC20Factory.connect(daiDeployment.address, account);
  await dai.approve(wethDaiPoolDeployment.address, MILLION.toString());

  const weth = ERC20Factory.connect(wethDeployment.address, account);
  await weth.approve(wethDaiPoolDeployment.address, MILLION.toString());

  const wethDaiPool = BPoolFactory.connect(wethDaiPoolDeployment.address, account);

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
