import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig, getTokenDeploymentName } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const { deployment, tokens } = await getDeploymentConfig(hre.network.name);

  for (const tokenConfig of deployment.tokens) {
    if (tokenConfig.symbol === "GYD") {
      continue;
    }

    if (tokenConfig.address) {
      return;
    }

    const token = tokens[tokenConfig.symbol];
    const deploymentName = getTokenDeploymentName(token.symbol);
    const deploymentResult = await deploy(deploymentName, {
      contract: "TokenFaucet",
      from: deployer.address,
      args: [token.name, token.symbol, token.decimals, token.mintAmount],
      log: true,
      deterministicDeployment: true,
    });

    if (deploymentResult.newlyDeployed) {
      await execute(deploymentName, { from: deployer.address }, "initializeOwner");
    }

    await execute(
      deploymentName,
      { from: deployer.address },
      "mintAsOwner",
      deployer.address,
      BigNumber.from(10).pow(token.decimals + 9) // 1B of each token
    );
  }
};

export default func;
func.tags = ["tokens"];
