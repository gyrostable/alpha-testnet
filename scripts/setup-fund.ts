import hre from "hardhat";
import {
  getBPoolAddress,
  getDeploymentConfig,
  getOracleAddress,
  getTokenAddress,
  scale,
} from "../misc/deployment-utils";
import { GyroFundV1__factory as GyroFundFactory } from "../typechain/factories/GyroFundV1__factory";
import { BalancerExternalTokenRouter__factory } from "../typechain/factories/BalancerExternalTokenRouter__factory";

const { deployments, ethers } = hre;

async function main() {
  const [signer] = await ethers.getSigners();
  const { deployment, pools, tokens } = await getDeploymentConfig(hre.network.name);

  const gyroFundDeployment = await deployments.get("GyroProxy");
  const balancerExternalTokenRouterDeployment = await deployments.get(
    "BalancerExternalTokenRouter"
  );

  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, signer);
  const balancerExternalTokenRouter = BalancerExternalTokenRouter__factory.connect(
    balancerExternalTokenRouterDeployment.address,
    signer
  );

  const tokenAddresses = await gyroFund.getUnderlyingTokenAddresses();

  for (const tokenConfig of deployment.tokens) {
    const token = tokens[tokenConfig.symbol];
    if (!token) {
      throw new Error(`could not find config for token ${tokenConfig.symbol}`);
    }
    const tokenAddress = await getTokenAddress(tokenConfig, deployment, deployments);
    if (tokenAddresses.includes(tokenAddress)) {
      console.log(`${token.symbol} already registered, skipping`);
      continue;
    }
    const oracleName = deployment.tokenOracles[token.symbol];
    const oracleAddress = await getOracleAddress(oracleName, deployment, deployments);
    await gyroFund.addToken(tokenAddress, oracleAddress, token.stable);
  }

  const totalWeight = deployment.pools.map((p) => p.weight).reduce((acc, elem) => acc + elem, 0);
  if (totalWeight !== 100) {
    throw new Error(`pools weights sum to ${totalWeight} instead of 100`);
  }

  const poolAddresses = await gyroFund.poolAddresses();

  for (const poolConfig of deployment.pools) {
    if (poolConfig.weight === 0) {
      continue;
    }
    const pool = pools[poolConfig.name];
    if (!pool) {
      throw new Error(`could not find config for pool ${poolConfig.name}`);
    }
    const poolAddress = await getBPoolAddress(poolConfig, deployment, deployments);
    if (poolAddresses.includes(poolAddress)) {
      console.log(`${pool.name} already registered, skipping`);
      continue;
    }
    const weight = scale(poolConfig.weight).div(100); // poolConfig.weight is a percentage
    console.log(`adding ${pool.name}`);
    await gyroFund.addPool(poolAddress, weight);
    await balancerExternalTokenRouter.addPool(poolAddress);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
