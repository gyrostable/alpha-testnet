import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

import initConfig from "../config/initialization.json";
import { BigNumber } from "ethers";

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

  const balancerExternalTokenRouterDeployment = await deploy("BalancerExternalTokenRouter", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
  if (balancerExternalTokenRouterDeployment.newlyDeployed) {
    await execute("BalancerExternalTokenRouter", { from: deployer.address }, "initializeOwner");
  }

  const oracleDeployment = await deploy("GyroPriceOracle", {
    from: deployer.address,
    contract: "DummyGyroPriceOracle",
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const gyroFundDeployment = await deploy("GyroFundV1", {
    from: deployer.address,
    args: [oracleDeployment.address, routerDeployment.address],
    log: true,
    deterministicDeployment: true,
  });
  if (gyroFundDeployment.newlyDeployed) {
    await execute("GyroFundV1", { from: deployer.address }, "initializeOwner");
  }

  const gyroLibDeployment = await deploy("GyroLib", {
    from: deployer.address,
    args: [gyroFundDeployment.address, balancerExternalTokenRouterDeployment.address],
    log: true,
    deterministicDeployment: true,
  });

  const execOptions = { from: deployer.address, log: true };
  const amountApproved = BigNumber.from(10).pow(50);
  for (const pool of initConfig.balancer_pools) {
    const poolDeployment = await deployments.get(`BPool${pool.name}`);
    await execute("BalancerExternalTokenRouter", execOptions, "addPool", poolDeployment.address);

    for (const asset of pool.assets) {
      const ercDeployment = `${asset.symbol}ERC20`;
      await execute(
        ercDeployment,
        execOptions,
        "approve",
        gyroLibDeployment.address,
        amountApproved
      );
    }
  }
};

export default func;
