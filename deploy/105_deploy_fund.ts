import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy } = deployments;

  await deploy("GyroFundV1", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
};

func.tags = ["gyro-fund-v1"];
export default func;
