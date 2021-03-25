import { ethers } from "hardhat";
import { DeployOptions } from "hardhat-deploy/dist/types";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeploymentConfig, transformArgs } from "../misc/deployment-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const { deployment } = await getDeploymentConfig(hre.network.name);

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
};

func.tags = ["price-oracles"];
export default func;
