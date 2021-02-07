import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import fs from "fs/promises";
import path from "path";

const abisPath = path.join(path.dirname(__dirname), "abis");

const tokens = [
  { symbol: "DAI", address: "0x1528f3fcc26d13f7079325fb78d9442607781c8c" },
  { symbol: "USDC", address: "0x2f375e94fc336cdec2dc0ccb5277fe59cbf1cae5" },
  { symbol: "WETH", address: "0xd0a1e359811322d97991e03f863a0c30c2cf029c" },
];

const pools = [
  { name: "usdc_weth", address: "0xdc6d6e66d690339a97dfb51d50c1f7415d30d8f6" },
  { name: "weth_dai", address: "0x56Ca37E2a2B6C9129d748415ec0c1e5E2Bc089de" },
];

const compoundUniswapOracleAddress = "0xbBdE93962Ca9fe39537eeA7380550ca6845F8db7";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { network, deployments } = hre;
  const { save, getArtifact } = deployments;
  if (network.name !== "kovan") {
    return;
  }

  for (const { address, symbol } of tokens) {
    const deploymentName = `${symbol}ERC20`;
    const abiPath = path.join(abisPath, `${symbol.toLowerCase()}.json`);
    const abi = JSON.parse(await fs.readFile(abiPath, "utf-8"));
    await save(deploymentName, {
      address,
      abi,
    });
  }

  const BPoolArtifact = await getArtifact("BPool");
  for (const { name, address } of pools) {
    const deploymentName = `BPool${name}`;
    await save(deploymentName, {
      address,
      abi: BPoolArtifact.abi,
    });
  }

  const compoundUniswapOracleAbiPath = path.join(abisPath, "uniswap-anchored-view.json");
  const compoundUniswapOracleAbi = JSON.parse(
    await fs.readFile(compoundUniswapOracleAbiPath, "utf-8")
  );
  await save("CompoundPriceWrapper", {
    address: compoundUniswapOracleAddress,
    abi: compoundUniswapOracleAbi,
  });
};

export default func;
func.tags = ["kovan"];
