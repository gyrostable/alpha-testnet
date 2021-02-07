import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction, Deployment } from "hardhat-deploy/types";
import { ethers, network } from "hardhat";

import initConfig from "../config/initialization.json";
import deploymentsConfig from "../config/deployments.json";
import { BigNumber, BigNumberish, utils } from "ethers";

type Networks = keyof typeof deploymentsConfig;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const networkName = <Networks>network.name;

  const deploymentConfig = deploymentsConfig[networkName];

  type TokenName = keyof typeof deploymentConfig.tokenOracles;
  const tokensNames = deploymentConfig.tokenNames.map((v) => <TokenName>v);
  const poolNames = deploymentConfig.poolNames;

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

  const oracles: any[] = deploymentConfig.oracles;
  const oracleDeployments: Record<string, Deployment> = Object.fromEntries(
    await Promise.all(
      oracles.map(async ({ name, args }) => {
        const deployment = await deploy(name, {
          from: deployer.address,
          args: args,
          log: true,
          deterministicDeployment: true,
        });
        return [name, deployment];
      })
    )
  );

  const scale = (n: BigNumberish) => BigNumber.from(n).mul(BigNumber.from(10).pow(18));

  const pools = await Promise.all(poolNames.map((name) => deployments.get(`BPool${name}`)));

  const tokens: Record<string, Deployment> = Object.fromEntries(
    await Promise.all(
      tokensNames.map(async (name) => {
        const deployment = await deployments.get(`${name}ERC20`);
        return [name, deployment];
      })
    )
  );
  const tokenAddresses = Object.values(tokens).map((t) => t.address);
  const stableCoinAddresses = deploymentConfig.stableCoins.map((t) => tokens[t].address);

  const oracleAddresses = tokensNames.map((name) => {
    const oracleName = deploymentConfig.tokenOracles[name];
    return oracleDeployments[oracleName].address;
  });

  const memoryParam = BigNumber.from(deploymentConfig.memoryParam);

  const fundParams = [
    scale(1).div(10), // uint256 _portfolioWeightEpsilon,
    [scale(5).div(10), scale(5).div(10)], // uint256[] memory _initialPoolWeights,
    pools.map((p) => p.address), // address[] memory _gyroPoolAddresses,
    oracleDeployment.address, // address _priceOracleAddress,
    routerDeployment.address, // address _routerAddress,
    tokenAddresses, // address[] memory _underlyingTokenAddresses,
    oracleAddresses, // address[] memory _underlyingTokenOracleAddresses,
    tokensNames.map((n) => utils.formatBytes32String(n)), // bytes32[] memory _underlyingTokenSymbols,
    stableCoinAddresses, // address[] memory _stablecoinAddresses,
    memoryParam, // uint256 _memoryParam
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

  const gyroLibDeployment = await deploy("GyroLib", {
    from: deployer.address,
    args: [gyroFundDeployment.address, balancerExternalTokenRouterDeployment.address],
    log: true,
    deterministicDeployment: true,
  });

  const execOptions = { from: deployer.address, log: true };
  const amountApproved = BigNumber.from(10).pow(50);

  for (const poolName of poolNames) {
    const pool = initConfig.balancer_pools.find((p) => p.name === poolName);
    if (!pool) {
      throw new Error(`${poolName} not found`);
    }
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

func.tags = ["fund"];
export default func;
