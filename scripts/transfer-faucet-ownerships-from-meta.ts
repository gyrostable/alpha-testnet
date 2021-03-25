import hre from "hardhat";
import { MetaFaucet__factory } from "../typechain/factories/MetaFaucet__factory";
import { TokenFaucet__factory } from "../typechain/factories/TokenFaucet__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const metaFaucetDeployment = await deployments.get("MetaFaucet");
  const metaFaucet = MetaFaucet__factory.connect(metaFaucetDeployment.address, account);

  await metaFaucet.restoreAllFaucetsOwnership();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
