import hre from "hardhat";
import { MetaFaucet__factory } from "../typechain/factories/MetaFaucet__factory";
import { TokenFaucet__factory } from "../typechain/factories/TokenFaucet__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const metaFaucetDeployment = await deployments.get("MetaFaucet");
  const metaFaucet = MetaFaucet__factory.connect(metaFaucetDeployment.address, account);

  const tokens = await metaFaucet.getTokens();
  for (const tokenAddress of tokens) {
    const token = TokenFaucet__factory.connect(tokenAddress, account);
    console.log(`runnnig for token ${tokenAddress}`);
    const currentOwner = await token.owner();
    if (currentOwner !== metaFaucet.address) {
      console.log(`setting ownership for token ${tokenAddress}`);
      await token.transferOwnership(metaFaucet.address);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
