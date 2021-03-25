import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;
  const gyroProxyAdminDeployment = await deploy("GyroProxyAdmin", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  if (gyroProxyAdminDeployment) {
    await execute("GyroProxyAdmin", { from: deployer.address }, "initializeOwner");
  }
};

func.tags = ["gyro-admin-proxy"];
export default func;
