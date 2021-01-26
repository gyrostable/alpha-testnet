import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import BPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import BFactoryArtifact from "../artifacts/contracts/balancer/BFactory.sol/BFactory.json";

import initConfig from "../config/initialization.json";

const TEN = BigNumber.from(10);

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { execute, save } = deployments;
  if (hre.network.live) {
    return;
  }

  const allDeployments = await deployments.all();
  const tokenAddresses: Record<string, string> = {};
  for (const key in allDeployments) {
    if (key.endsWith("ERC20")) {
      tokenAddresses[key.replace("ERC20", "")] = allDeployments[key].address;
    }
  }

  const tokens = Object.fromEntries(initConfig.tokens.map((t) => [t.symbol, t]));

  const pools = initConfig.balancer_pools;
  const bFactoryInterface = new ethers.utils.Interface(BFactoryArtifact.abi);

  const deployOptions = { from: deployer.address, log: true };

  for (const pool of pools) {
    const deploymentName = `BPool${pool.name}`;
    if (deploymentName in allDeployments) {
      console.log(`reusing "${deploymentName}" at ${allDeployments[deploymentName].address}`);
      continue;
    }

    const receipt = await execute("BFactory", deployOptions, "newBPool");
    if (!receipt.logs) {
      console.error(`not log found for ${deploymentName}`);
      continue;
    }

    const parsedLog = bFactoryInterface.parseLog(receipt.logs[0]);
    const address = parsedLog.args.pool;
    await save(deploymentName, {
      address,
      receipt,
      abi: BPoolArtifact.abi,
    });

    for (const asset of pool.assets) {
      const token = tokens[asset.symbol];
      // 10 ^ (decimals + 6): 6 is the precision of price and is canceled by / token.price
      const balance = TEN.pow(token.decimals + 6)
        .mul(asset.amount)
        .div(token.price);
      console.log(`${asset.symbol} balance: ${balance.toString()}`);
      const tokenAddress = tokenAddresses[asset.symbol];
      const denorm = TEN.pow(18).mul(asset.weight);
      await execute(`${asset.symbol}ERC20`, deployOptions, "approve", address, balance);
      await execute(
        deploymentName,
        deployOptions,
        "bind",
        tokenAddress,
        balance,
        denorm.toString()
      );
    }

    const swapFee = TEN.pow(12).mul(pool.swap_fee);
    await execute(deploymentName, deployOptions, "setSwapFee", swapFee.toString());

    await execute(deploymentName, deployOptions, "finalize");
  }
};

export default func;
