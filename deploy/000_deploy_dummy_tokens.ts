import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import initConfig from "../config/initialization.json";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;
  if (hre.network.live) {
    return;
  }

  for (const token of initConfig.tokens) {
    const deploymentName = `${token.symbol}ERC20`;
    const deploymentResult = await deploy(deploymentName, {
      contract: "SimpleERC20",
      from: deployer.address,
      args: [token.name, token.symbol, token.decimals],
      log: true,
      deterministicDeployment: true,
    });
    if (deploymentResult.newlyDeployed) {
      await execute(deploymentName, { from: deployer.address }, "initializeOwner");
    }

    await execute(
      deploymentName,
      { from: deployer.address },
      "mint",
      deployer.address,
      BigNumber.from(10).pow(27)
    );
  }
};

export default func;
