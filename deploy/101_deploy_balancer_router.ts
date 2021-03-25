// import deploymentsConfig from "../config/deployments.json";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const balancerExternalTokenRouterDeployment = await deploy("BalancerExternalTokenRouter", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  if (balancerExternalTokenRouterDeployment.newlyDeployed) {
    await execute("BalancerExternalTokenRouter", { from: deployer.address }, "initializeOwner");
  }
};

func.tags = ["balancer-router"];
export default func;
