import hre, { network } from "hardhat";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();

let i: number =1;
  while (i < 1000) {
      await network.provider.send("evm_mine")
      i++;
  }

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
