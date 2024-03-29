import hre from "hardhat";
import { bindPool, getDeploymentConfig } from "../misc/deployment-utils";

async function main() {
  const { deployments, network } = hre;
  const { deployment, pools } = await getDeploymentConfig(network.name);

  for (const poolConfig of deployment.pools) {
    if (poolConfig.weight === 0) {
      continue;
    }

    const pool = pools[poolConfig.name];
    await bindPool(pool, deployment, deployments);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
