import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import BN from "bn.js";

import BPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import BFactoryArtifact from "../artifacts/contracts/balancer/BFactory.sol/BFactory.json";

import initConfig from "../initialization.json";

const TEN = new BN(10);

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

  const prices: Record<string, BN> = {};
  for (const token of initConfig.tokens) {
    prices[token.symbol] = new BN(token.price);
  }

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
      const balance = new BN(asset.amount)
        .mul(TEN.pow(new BN(24)))
        .div(prices[asset.symbol])
        .toString();
      const tokenAddress = tokenAddresses[asset.symbol];
      const denorm = new BN(asset.weight).mul(TEN.pow(new BN(18)));
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

    console.log(deploymentName);
    const swapFee = new BN(pool.swap_fee).mul(TEN.pow(new BN(12)));
    await execute(deploymentName, deployOptions, "setSwapFee", swapFee.toString());

    await execute(deploymentName, deployOptions, "finalize");
  }
};

export default func;
