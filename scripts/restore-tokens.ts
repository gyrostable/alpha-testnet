import fs from "fs/promises";
import hre from "hardhat";
import path from "path";

import { GyroFundV1__factory as GyroFundFactory } from "../typechain/factories/GyroFundV1__factory";

const { deployments, ethers } = hre;

async function main() {
  const [signer] = await ethers.getSigners();
  const filePath = path.join(
    __dirname,
    "../tmp/export-tokenholders-for-contract-0x3E7374335a4Ff0aD4453B4D3aa35c6756cDF4d66.csv"
  );
  const oldFundAddress = "0x3E7374335a4Ff0aD4453B4D3aa35c6756cDF4d66";

  const gyroFundDeployment = await deployments.get("GyroProxy");
  const oldGyroFund = GyroFundFactory.connect(oldFundAddress, signer);
  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, signer);

  const rawHolders = await fs.readFile(filePath, "utf-8");
  const addresses = rawHolders
    .split("\n")
    .slice(1)
    .map((v) => v.split(",")[0].replace(/"/g, ""))
    .filter((v) => v.length > 0 && v.toLowerCase() !== signer.address.toLowerCase());

  const holders = await Promise.all(
    addresses.map((a) => oldGyroFund.balanceOf(a).then((b) => ({ address: a, balance: b })))
  );

  for (const { address, balance } of holders) {
    const currentBalance = await gyroFund.balanceOf(address);
    if (currentBalance.gte(balance)) {
      console.log(`skipping ${address}`);
      continue;
    }
    await gyroFund.transfer(address, balance);
    console.log(`transfered ${balance.toString()} to ${address}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
