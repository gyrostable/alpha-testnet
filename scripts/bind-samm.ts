import hre from "hardhat";
import { bindPool, getDeploymentConfig } from "../misc/deployment-utils";

async function main() {
  const { deployments, network } = hre;
  const { deployment, pools } = await getDeploymentConfig(network.name);

  const poolName = "gyd_usdc";
  const pool = pools[poolName];
  await bindPool(pool, deployment, deployments);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
