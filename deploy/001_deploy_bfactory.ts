import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy } = deployments;
  if (hre.network.live) {
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
