import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy } = deployments;
  const { deployment } = await getDeploymentConfig(hre.network.name);
  if (deployment.bfactory) {
    return;
  }

  await deploy("BFactory", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
};

export default func;
func.tags = ["bfactory"];
