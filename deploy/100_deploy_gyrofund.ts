// import deploymentsConfig from "../config/deployments.json";
import { BigNumber, utils } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  getBPoolAddress,
  getBPoolsAddresses,
  getDeploymentConfig,
  getTokenAddress,
  getTokensAddresses,
  scale,
  TokenConfig,
  transformArgs,
} from "../misc/deployment-utils";
import { BalancerExternalTokenRouter__factory, ERC20__factory } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;

  const { deployment, tokens } = await getDeploymentConfig(hre.network.name);

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
  const balancerExternalTokenRouter = BalancerExternalTokenRouter__factory.connect(
    balancerExternalTokenRouterDeployment.address,
    deployer
  );
  if (balancerExternalTokenRouterDeployment.newlyDeployed) {
    await balancerExternalTokenRouter.initializeOwner();
  }

  const oracleDeployment = await deploy("GyroPriceOracle", {
    from: deployer.address,
    contract: "GyroPriceOracleV1",
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const oracles = deployment.oracles;
  const oracleDeployments: Record<string, Deployment> = {};
  for (const { name, args } of oracles) {
    const transformedArgs = await transformArgs(args, deployments);
    oracleDeployments[name] = await deploy(name, {
      from: deployer.address,
      args: transformedArgs,
      log: true,
      deterministicDeployment: true,
    });
  }

  const poolAddresses = await getBPoolsAddresses(deployment.pools, deployment, deployments);
  // const pools = await Promise.all(poolNames.map((name: string) => deployments.get(`BPool${name}`)));

  const oracleAddresses = deployment.tokens.map((token: TokenConfig) => {
    const oracleName = deployment.tokenOracles[token.symbol];
    return oracleDeployments[oracleName].address;
  });

  const memoryParam = BigNumber.from(deployment.memoryParam);

  const tokenAddresses = await getTokensAddresses(deployment.tokens, deployment, deployments);
  const stableTokens = deployment.tokens.filter((t) => !tokens[t.symbol].stable);
  const stableCoinAddresses = await getTokensAddresses(stableTokens, deployment, deployments);

  const fundParams = [
    scale(1).div(10), // uint256 _portfolioWeightEpsilon,
    [scale(5).div(10), scale(5).div(10)], // uint256[] memory _initialPoolWeights,
    poolAddresses, // address[] memory _gyroPoolAddresses,
    oracleDeployment.address, // address _priceOracleAddress,
    routerDeployment.address, // address _routerAddress,
    tokenAddresses, // address[] memory _underlyingTokenAddresses,
    oracleAddresses, // address[] memory _underlyingTokenOracleAddresses,
    deployment.tokens.map((t) => utils.formatBytes32String(t.symbol)), // bytes32[] memory _underlyingTokenSymbols,
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

  // const amountApproved = BigNumber.from(10).pow(50);

  for (const pool of deployment.pools) {
    const poolAddress = await getBPoolAddress(pool, deployment, deployments);
    await balancerExternalTokenRouter.addPool(poolAddress);

    // const tokenAddresses = await getTokensAddresses(deployment.tokens, deployment, deployments);
    // for (const tokenAddress of tokenAddresses) {
    //   const tokenContract = ERC20__factory.connect(tokenAddress, deployer);
    //   tokenContract.approve(gyroLibDeployment.address, amountApproved);
    // }
  }
};

func.tags = ["fund"];
export default func;
