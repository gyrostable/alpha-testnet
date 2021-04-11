import { BigNumber } from "ethers";
import hre from "hardhat";
import { getBPoolAddress, getDeploymentConfig, scale } from "../misc/deployment-utils";
import {
  BPool,
  BPool__factory,
  DummyUniswapAnchoredView__factory,
  ERC20__factory,
} from "../typechain";

const { deployments, ethers } = hre;

async function main() {
  const [signer] = await ethers.getSigners();
  const { deployment, pools } = await getDeploymentConfig(hre.network.name);

  const dummyOracleAddress = (await deployments.get("UniswapAnchoredView")).address;
  const dummyOracle = DummyUniswapAnchoredView__factory.connect(dummyOracleAddress, signer);

  const tokenPrice = await dummyOracle.price("ETH");

  const symbolMapping: Record<string, string> = { WETH: "ETH", BUSD: "DAI", sUSD: "DAI", GYD: "DAI" };
  const oracleDecimals = 6;
  const defaultDecimals = 18;

  const getTokenInfo = async (pool: BPool, tokenAddress: string) => {
    const symbol = await ERC20__factory.connect(tokenAddress, signer).symbol();
    const decimals = await ERC20__factory.connect(tokenAddress, signer).decimals();
    const price = await dummyOracle.price(symbol in symbolMapping ? symbolMapping[symbol] : symbol);
    const balance = await pool.getBalance(tokenAddress);
    const scaledBalance = scale(balance, defaultDecimals - decimals);
    const weightDistortion = scale(2, 16);
    const weight = await pool.getNormalizedWeight(tokenAddress);

    const distortedWeight = symbol == "GYD" ? weight.sub(weightDistortion) : weight.add(weightDistortion);

    return {
      address: tokenAddress,
      weight: distortedWeight,
      decimals,
      balance: scaledBalance,
      price,
      value: scaledBalance.mul(price).div(BigNumber.from(10).pow(oracleDecimals)),
      symbol,
    };
  
  };

  const poolAddress = await getBPoolAddress("gyd_usdc", deployment, deployments);

  console.log("distorting pool ", poolAddress);
  const pool = BPool__factory.connect(poolAddress, signer);
  const tokenAddresses = await pool.getFinalTokens();
  const tokens = await Promise.all(tokenAddresses.map((t) => getTokenInfo(pool, t)));
  const totalValue = tokens.reduce((acc, token) => acc.add(token.value), BigNumber.from(0));


  let [deviationFirst, deviationSecond] = tokens.map((t) =>
    scale(1).sub(scale(scale(t.value).div(totalValue)).div(t.weight))
  );

  let [firstToken, secondToken] = tokens;

  if (deviationSecond.gt(deviationFirst)) {
    [secondToken, firstToken] = [firstToken, secondToken];
    [deviationSecond, deviationFirst] = [deviationFirst, deviationSecond];
  }

  const minDeviation = scale(1, 22); // 1%
  const scaledDeviationFirst = scale(deviationFirst);
  if (scaledDeviationFirst.gte(minDeviation)) {
    console.log("deviation already large enough, skipping");
  } else { 

    const targetValue = secondToken.value.mul(firstToken.weight).div(secondToken.weight);
    const targetBalance = scale(targetValue, oracleDecimals).div(firstToken.price);
    const balanceDelta = targetBalance.sub(firstToken.balance);
    const scaledBalanceDelta = balanceDelta.div(scale(1, defaultDecimals - firstToken.decimals));
  
    console.log(`transfering ${scaledBalanceDelta.toString()} ${firstToken.symbol} to the pool`);
  
    await ERC20__factory.connect(firstToken.address, signer).approve(
      pool.address,
      scaledBalanceDelta
    );
    await pool.joinswapExternAmountIn(firstToken.address, scaledBalanceDelta, 0);


  }



}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
