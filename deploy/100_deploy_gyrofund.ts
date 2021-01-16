import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

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
  await execute("GyroRouter", { from: deployer.address }, "initializeOwner");

  const oracleDeployment = await deploy("GyroPriceOracle", {
    from: deployer.address,
    contract: "DummyGyroPriceOracle",
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  await deploy("GyroFundV1", {
    from: deployer.address,
    args: [oracleDeployment.address, routerDeployment.address],
    log: true,
    deterministicDeployment: true,
  });
  await execute("GyroFundV1", { from: deployer.address }, "initializeOwner");
};

export default func;
