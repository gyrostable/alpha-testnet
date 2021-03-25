import hre from "hardhat";
import { MetaFaucet__factory } from "../typechain/factories/MetaFaucet__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const metaFaucetDeployment = await deployments.get("MetaFaucet");
  const metaFaucet = MetaFaucet__factory.connect(metaFaucetDeployment.address, account);
  const tx = await metaFaucet.mint();

  const receipt = await tx.wait();

  for (const event of receipt.events || []) {
    console.log(event.event, event.args);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
