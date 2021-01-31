import { deployContract, deployMockContract, MockContract } from "ethereum-waffle";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import BalancerPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import GyroPriceOracleV1Artifact from "../artifacts/contracts/GyroPriceOracle.sol/GyroPriceOracle.json"
import GyroFundArtifact from "../artifacts/contracts/GyroFund.sol/GyroFundV1.json";
import BalancerExternalTokenRouterArtifact from "../artifacts/contracts/BalancerGyroRouter.sol/BalancerExternalTokenRouter.json";
import { BalancerExternalTokenRouter } from "../typechain/BalancerExternalTokenRouter";
import { DummyPriceWrapper } from "../typechain/DummyPriceWrapper";
import { GyroPriceOracleV1 } from "../typechain/GyroPriceOracleV1";
import { ERC20 } from "../typechain/ERC20";
import { GyroFundV1__factory as GyroFundV1Factory } from "../typechain/factories/GyroFundV1__factory"
import { BalancerExternalTokenRouter__factory as BalancerExternalTokenRouterFactory } from "../typechain/factories/BalancerExternalTokenRouter__factory";
import { ERC20__factory as ERC20Factory } from "../typechain/factories/ERC20__factory";
import { expect } from "./chai";
import { GyroFund } from "../typechain/GyroFund";
import { utils, BigNumber, BigNumberish } from "ethers";
import { GyroFundV1 } from "../typechain/GyroFundV1";
import { GyroPriceOracleV1__factory } from "../typechain/factories/GyroPriceOracleV1__factory";
import { DummyPriceWrapper__factory } from "../typechain/factories/DummyPriceWrapper__factory";


describe("GyroFund", function () {
  let accounts: Signer[];
  let router: BalancerExternalTokenRouter;
  let mockPools: MockContract[];
  let tokens: ERC20[];
  let gyroFund: GyroFundV1;
  let dummyPriceOracle: DummyPriceWrapper;
  let gyroPriceOracle: GyroPriceOracleV1;

  const underlyingTokenSymbols = ['WETH', 'DAI', 'USDC'].map(symbol => utils.formatBytes32String(symbol));

  const scaling = BigNumber.from(10).pow(18);

  function scale(value: BigNumberish): BigNumber {
    return BigNumber.from(value).mul(scaling);
  }

  const portfolioWeightEpsilon = scale(1).div(10);
  const initialPoolWeights = [scale(5).div(10), scale(5).div(10)];


  const repeat = (value: any, n: number) => {
    const result = [];
    for (let i = 0; i < n; i++) {
      result.push(value);
    }
    return result;
  };



  beforeEach(async function () {
    accounts = await ethers.getSigners();
    const wallet = accounts[0];
  
    tokens = await Promise.all([
      new ERC20Factory(wallet).deploy("token1", "WETH"),
      new ERC20Factory(wallet).deploy("token2", "USDC"),
      new ERC20Factory(wallet).deploy("token3", "DAI"),
    ]);

    const tokenAddresses = tokens.map((p) => p.address);

    const mockPool1 = await deployMockContract(wallet, BalancerPoolArtifact.abi);
    await mockPool1.mock.isFinalized.returns(true);
    await mockPool1.mock.getFinalTokens.returns([tokenAddresses[0], tokenAddresses[1]]);

    const mockPool2 = await deployMockContract(wallet, BalancerPoolArtifact.abi);
    await mockPool2.mock.isFinalized.returns(true);
    await mockPool2.mock.getFinalTokens.returns([tokenAddresses[0], tokenAddresses[2]]);


    mockPools = await Promise.all([
      mockPool1, mockPool2
    ]);
    

    router = await new BalancerExternalTokenRouterFactory(wallet).deploy();
    dummyPriceOracle = await new DummyPriceWrapper__factory(wallet).deploy();

    const gyroPriceOracle = await deployMockContract(wallet, GyroPriceOracleV1Artifact.abi);
    await gyroPriceOracle.mock.getBPTPrice.returns(200);


    const underlyingTokenOracleAddresses = repeat(dummyPriceOracle.address, tokens.length);

    await router.initializeOwner();
    gyroFund = await new GyroFundV1Factory(wallet).deploy(
      portfolioWeightEpsilon,
      initialPoolWeights,
      mockPools.map((p) => p.address),
      gyroPriceOracle.address,
      router.address,
      tokenAddresses,
      underlyingTokenOracleAddresses,
      underlyingTokenSymbols,
      [tokenAddresses[1], tokenAddresses[2]],
      BigNumber.from("999993123563518195"),
    )

  });

  describe("check stablecoin health", function () {
    it("should check that only stablecoins near the peg are accepted", async function () {
      console.log("test");
      const stablecoinhealth = await gyroFund.checkStablecoinHealth(1.06e15, '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a');
      expect(stablecoinhealth).to.equal(false);

    });
  });
});