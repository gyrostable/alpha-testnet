import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import BPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import {
  getBFactoryAddress,
  getDeploymentConfig,
  getPoolDeploymentName,
  getTokenAddress,
  scale,
} from "../misc/deployment-utils";
import { BPool__factory, ERC20__factory } from "../typechain";
import { BFactory__factory } from "../typechain/factories/BFactory__factory";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { save } = deployments;

  const { deployment, pools, tokens } = await getDeploymentConfig(hre.network.name);

  const allDeployments = await deployments.all();

  const bFactoryAddress = await getBFactoryAddress(deployment, deployments);
  const bFactory = BFactory__factory.connect(bFactoryAddress, deployer);

  for (const poolConfig of deployment.pools) {
    if (poolConfig.address) {
      continue;
    }

    const deploymentName = getPoolDeploymentName(poolConfig.name);
    if (deploymentName in allDeployments) {
      console.log(`reusing "${deploymentName}" at ${allDeployments[deploymentName].address}`);
      continue;
    }

    const pool = pools[poolConfig.name];
    if (!pool) {
      throw new Error(`no pool named ${poolConfig.name}`);
    }

    const tx = await bFactory.newBPool();
    console.log(`deploying "${deploymentName}" (tx: ${tx.hash})...:`);
    const receipt = await tx.wait();
    if (!receipt.logs) {
      console.error(`not log found for ${deploymentName}`);
      continue;
    }

    const parsedLog = bFactory.interface.parseLog(receipt.logs[0]);
    const address = parsedLog.args.pool;
    console.log(`deployed at ${address} with ${receipt.gasUsed} gas`);
    await save(deploymentName, {
      address,
      receipt,
      abi: BPoolArtifact.abi,
    });
  }
};

export default func;
func.tags = ["bpools"];
