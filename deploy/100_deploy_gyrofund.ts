// import deploymentsConfig from "../config/deployments.json";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DeployOptions } from "hardhat-deploy/dist/types";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig, scale, transformArgs } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const { deployment } = await getDeploymentConfig(hre.network.name);

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

  const balancerExternalTokenRouterDeployment = await deploy("BalancerExternalTokenRouter", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  if (balancerExternalTokenRouterDeployment.newlyDeployed) {
    await execute("BalancerExternalTokenRouter", { from: deployer.address }, "initializeOwner");
  }

  // gyro AMM price oracle
  const oracleDeployment = await deploy("GyroPriceOracle", {
    from: deployer.address,
    contract: "GyroPriceOracleV1",
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  // ERC20 token price oracles
  for (const oracleConfig of deployment.oracles) {
    if (oracleConfig.address) {
      continue;
    }
    const transformedArgs = await transformArgs(oracleConfig.args, deployments);
    const oracleDeploymentConfig: DeployOptions = {
      from: deployer.address,
      args: transformedArgs,
      log: true,
      deterministicDeployment: true,
    };
    if (oracleConfig.contract) {
      oracleDeploymentConfig["contract"] = oracleConfig.contract;
    }
    const priceOracleDeployment = await deploy(oracleConfig.name, oracleDeploymentConfig);
    if (priceOracleDeployment.newlyDeployed && oracleConfig.ownable) {
      await execute(oracleConfig.name, { from: deployer.address }, "initializeOwner");
    }
  }

  const fundParams = [
    scale(1).div(10), // uint256 _portfolioWeightEpsilon,
    oracleDeployment.address, // address _priceOracleAddress,
    routerDeployment.address, // address _routerAddress,
    BigNumber.from(deployment.memoryParam), // uint256 _memoryParam
  ];
  console.log("deploying with args:", fundParams);

  const gyroFundDeployment = await deploy("GyroFundV1", {
    from: deployer.address,
    args: fundParams,
    log: true,
    deterministicDeployment: true,
  });
  if (gyroFundDeployment.newlyDeployed) {
    await execute("GyroFundV1", { from: deployer.address }, "initializeOwner");
  }

  await deploy("GyroLib", {
    from: deployer.address,
    args: [gyroFundDeployment.address, balancerExternalTokenRouterDeployment.address],
    log: true,
    deterministicDeployment: true,
  });
};

func.tags = ["fund"];
export default func;
