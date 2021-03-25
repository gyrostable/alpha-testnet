// import deploymentsConfig from "../config/deployments.json";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const gyroProxyDeployment = await deployments.get("GyroProxy");

  const balancerExternalTokenRouterDeployment = await deployments.get(
    "BalancerExternalTokenRouter"
  );

  const gyroLibDeployment = await deploy("GyroLib", {
    from: deployer.address,
    args: [gyroProxyDeployment.address, balancerExternalTokenRouterDeployment.address],
    log: true,
    deterministicDeployment: true,
  });
  if (gyroLibDeployment.newlyDeployed) {
    await execute("GyroLib", { from: deployer.address }, "initializeOwner");
  }
};

func.tags = ["gyro-lib"];
export default func;
