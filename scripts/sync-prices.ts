import hre from "hardhat";
import { INFURA_PROJECT_ID, INFURA_PROJECT_SECRET } from "../hardhat.config";
import { getDeploymentConfig, scale } from "../misc/deployment-utils";
import { DummyUniswapAnchoredView__factory } from "../typechain/factories/DummyUniswapAnchoredView__factory";
import { UniswapAnchoredView__factory } from "../typechain/factories/UniswapAnchoredView__factory";

const { deployments, ethers } = hre;

const mainnetUniswapAnchoredViewAddress = "0x922018674c12a7F0D394ebEEf9B58F186CdE13c1";

const gasPrice = scale(2, 9);

const infuraMainnetProvider = new ethers.providers.InfuraProvider("homestead", {
  projectId: INFURA_PROJECT_ID,
  projectSecret: INFURA_PROJECT_SECRET,
});

async function main() {
  const [signer] = await ethers.getSigners();
  const { tokens } = await getDeploymentConfig(hre.network.name);

  const dummyOracleAddress = (await deployments.get("UniswapAnchoredView")).address;

  const mainnetOracle = UniswapAnchoredView__factory.connect(
    mainnetUniswapAnchoredViewAddress,
    infuraMainnetProvider
  );
  const dummyOracle = DummyUniswapAnchoredView__factory.connect(dummyOracleAddress, signer);

  const doneSymbols: Record<string, boolean> = {};

  for (let symbol in tokens) {
    if (symbol === "GYD") {
      continue;
    }

    if (symbol === "WETH") {
      symbol = "ETH";
    }

    if (["sUSD", "BUSD"].includes(symbol)) {
      symbol = "DAI";
    }
    if (doneSymbols[symbol]) {
      console.log(`${symbol} already updated, skipping`);
    }
    const isRegistered = await dummyOracle.tokenRegistered(symbol);
    if (!isRegistered) {
      console.log(`Registering ${symbol}`);
      const config = await mainnetOracle.getTokenConfigBySymbol(symbol);
      await dummyOracle.addToken(symbol, config, { gasPrice });
    }
    console.log(`Setting price for ${symbol}`);
    const price = await mainnetOracle.price(symbol);
    await dummyOracle.setPrice(symbol, price, { gasPrice });
    doneSymbols[symbol] = true;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
