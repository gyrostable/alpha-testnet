import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

import initConfig from "../config/initialization.json";
import { BigNumber, BigNumberish, utils } from "ethers";

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
    contract: "GyroPriceOracleV1",
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const dummyPriceOracleDeployment = await deploy("DummyPriceWrapper", {
    from: deployer.address,
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const scale = (n: BigNumberish) => BigNumber.from(n).mul(BigNumber.from(10).pow(18));

  // for (const pool of initConfig.balancer_pools) {
  //   const poolDeployment = await deployments.get(`BPool${pool.name}`);
  const poolNames = ["usdc_weth", "weth_dai"];
  const pools = await Promise.all(poolNames.map((name) => deployments.get(`BPool${name}`)));

  const tokensNames = ["WETH", "USDC", "DAI"];
  const tokens = await Promise.all(tokensNames.map((name) => deployments.get(`${name}ERC20`)));
  const tokenAddresses = tokens.map((t) => t.address);

  const repeat = (value: any, n: number) => {
    const result = [];
    for (let i = 0; i < n; i++) {
      result.push(value);
    }
    return result;
  };

  const fundParams = [
    scale(1).div(10), // uint256 _portfolioWeightEpsilon,
    [scale(5).div(10), scale(5).div(10)], // uint256[] memory _initialPoolWeights,
    pools.map((p) => p.address), // address[] memory _gyroPoolAddresses,
    oracleDeployment.address, // address _priceOracleAddress,
    routerDeployment.address, // address _routerAddress,
    tokenAddresses, // address[] memory _underlyingTokenAddresses,
    repeat(dummyPriceOracleDeployment.address, tokens.length), // address[] memory _underlyingTokenOracleAddresses,
    tokensNames.map((n) => utils.formatBytes32String(n)), // bytes32[] memory _underlyingTokenSymbols,
    [tokenAddresses[1], tokenAddresses[2]], // address[] memory _stablecoinAddresses,
    BigNumber.from("999993123563518195"), // uint256 _memoryParam
  ];
  console.log("deploying with args:", fundParams);

  const gyroFundDeployment = await deploy("GyroFundV1", {
    from: deployer.address,
    args: fundParams,
    log: true,
    deterministicDeployment: true,
  });
  // if (gyroFundDeployment.newlyDeployed) {
  //   await execute("GyroFundV1", { from: deployer.address }, "initializeOwner");
  // }

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
