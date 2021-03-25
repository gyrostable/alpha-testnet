import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy } = deployments;

  // gyro AMM price oracle
  await deploy("GyroPriceOracle", {
    from: deployer.address,
    contract: "GyroPriceOracleV1",
    args: [],
    log: true,
    deterministicDeployment: true,
  });
};

func.tags = ["gyro-oracle"];
export default func;
