import hre from "hardhat";
import {
  getBPoolAddress,
  getDeploymentConfig,
  getOracleAddress,
  getTokenAddress,
  scale,
} from "../misc/deployment-utils";
import { PriceOracle__factory } from "../typechain";
import { BPool__factory } from "../typechain/factories/BPool__factory";
import { ERC20__factory } from "../typechain/factories/ERC20__factory";

async function main() {
  const { ethers, deployments, network } = hre;
  const { deployment, pools, tokens } = await getDeploymentConfig(network.name);
  for (const poolConfig of deployment.pools) {
    const [signer] = await ethers.getSigners();
    const poolAddress = await getBPoolAddress(poolConfig, deployment, deployments);
    const poolContract = BPool__factory.connect(poolAddress, signer);
    const pool = pools[poolConfig.name];

    if (await poolContract.isFinalized()) {
      continue;
    }

    console.log(`binding pool ${poolConfig.name}`);

    for (const asset of pool.assets) {
      const token = tokens[asset.symbol];
      const priceOracleAddress = await getOracleAddress(
        deployment.tokenOracles[asset.symbol],
        deployment,
        deployments
      );
      const oracle = PriceOracle__factory.connect(priceOracleAddress, signer);
      const tokenPrice = await oracle.getPrice(token.symbol);

      // token.decimals and tokenPrice have the same scale
      const balance = scale(asset.amount, token.decimals * 2).div(tokenPrice);
      const tokenAddress = await getTokenAddress(token.symbol, deployment, deployments);
      const denorm = scale(asset.weight, 18);
      const tokenContract = ERC20__factory.connect(tokenAddress, signer);
      await tokenContract.approve(poolAddress, balance);
      await poolContract.bind(tokenAddress, balance, denorm);
    }

    const swapFee = scale(pool.swap_fee, 12);
    await poolContract.setSwapFee(swapFee);
    await poolContract.finalize();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
