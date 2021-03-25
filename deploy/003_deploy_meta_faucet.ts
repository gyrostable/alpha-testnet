import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig, getTokensAddresses } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const { deployment } = await getDeploymentConfig(hre.network.name);

  const tokenAddresses = await getTokensAddresses(deployment.tokens, deployment, deployments);

  const deploymentResult = await deploy("MetaFaucet", {
    from: deployer.address,
    args: [tokenAddresses],
    log: true,
    deterministicDeployment: true,
  });

  if (deploymentResult.newlyDeployed) {
    await execute("MetaFaucet", { from: deployer.address }, "initializeOwner");
  }
};

export default func;
func.tags = ["metafaucet"];
