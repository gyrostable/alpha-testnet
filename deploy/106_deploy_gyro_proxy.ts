// import deploymentsConfig from "../config/deployments.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig, scale } from "../misc/deployment-utils";
import { GyroFundV1__factory } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy } = deployments;

  const gyroFundDeployment = await deployments.get("GyroFundV1");
  const gyroProxyAdminDeployment = await deployments.get("GyroProxyAdmin");
  const oracleDeployment = await deployments.get("GyroPriceOracle");
  const routerDeployment = await deployments.get("GyroRouter");

  const { deployment } = await getDeploymentConfig(hre.network.name);
  const gyroProxyDeployment = await deploy("GyroProxy", {
    from: deployer.address,
    args: [gyroFundDeployment.address, gyroProxyAdminDeployment.address, []],
    log: true,
    deterministicDeployment: true,
  });

  if (gyroProxyDeployment.newlyDeployed) {
    const proxiedGyroFund = GyroFundV1__factory.connect(gyroProxyDeployment.address, deployer);
    await proxiedGyroFund.initializeOwner();
    await proxiedGyroFund.initialize(
      scale(1).div(10), // uint256 _portfolioWeightEpsilon,
      oracleDeployment.address, // address _priceOracleAddress,
      routerDeployment.address, // address _routerAddress,
      BigNumber.from(deployment.memoryParam) // uint256 _memoryParam
    );
  }
};

func.tags = ["gyro-proxy"];
export default func;
