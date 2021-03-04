import { BigNumber } from "ethers";
import hre from "hardhat";
import { scale } from "../misc/deployment-utils";
import { BPool__factory as BPoolFactory } from "../typechain/factories/BPool__factory";
import { GyroFundV1__factory as GyroFundFactory } from "../typechain/factories/GyroFundV1__factory";
const { deployments, ethers } = hre;

async function main() {
  const [account] = await ethers.getSigners();
  const gyroFundDeployment = await deployments.get("GyroProxy");
  const gyroFund = GyroFundFactory.connect(gyroFundDeployment.address, account);

  const poolAddresses = await gyroFund.poolAddresses();

  const amountIn = scale(5);

  for (const poolAddress of poolAddresses) {
    const pool = BPoolFactory.connect(poolAddress, account);
    if ((await pool.allowance(account.address, gyroFund.address)).gte(amountIn)) {
      continue;
    }
    const balance = await pool.balanceOf(account.address);
    console.log(`balance in pool ${poolAddress}: ${balance.toString()}`);
    await pool.approve(gyroFund.address, BigNumber.from(10).pow(30));
  }

  const tx = await gyroFund.mintTest(
    poolAddresses,
    poolAddresses.map((_) => amountIn),
    { gasLimit: 3_000_000 }
  );
  // const tx = await gyroFund.mint(
  //   poolAddresses,
  //   poolAddresses.map((_) => amountIn),
  //   0,
  //   { gasLimit: 3_000_000 }
  // );
  await tx.wait();

  const balance = await gyroFund.balanceOf(account.address);
  const readableBalance = balance.div(BigNumber.from(10).pow(18)).toString();
  console.log(`GyroFund balance: ${readableBalance}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
