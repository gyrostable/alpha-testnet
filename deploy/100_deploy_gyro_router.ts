import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const routerDeployment = await deploy("GyroRouter", {
    from: deployer.address,
    contract: "BalancerTokenRouter",
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  if (routerDeployment.newlyDeployed) {
    await execute("GyroRouter", { from: deployer.address }, "initializeOwner");
  }
};

func.tags = ["gyro-router"];
export default func;
