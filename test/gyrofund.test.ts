import { deployContract, deployMockContract, MockContract } from "ethereum-waffle";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import BalancerPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import GyroFundArtifact from "../artifacts/contracts/GyroFund.sol/GyroFundV1.json";
import BalancerExternalTokenRouterArtifact from "../artifacts/contracts/BalancerGyroRouter.sol/BalancerExternalTokenRouter.json";
import { BalancerExternalTokenRouter } from "../typechain/BalancerExternalTokenRouter";
import { ERC20 } from "../typechain/ERC20";
import { BalancerExternalTokenRouter__factory as BalancerExternalTokenRouterFactory } from "../typechain/factories/BalancerExternalTokenRouter__factory";
import { ERC20__factory as ERC20Factory } from "../typechain/factories/ERC20__factory";
import { expect } from "./chai";
import { GyroFund } from "../typechain/GyroFund";
import { utils, BigNumber, BigNumberish } from "ethers";


describe("GyroFund", function () {
  let accounts: Signer[];
  let router: BalancerExternalTokenRouter;
  let mockPools: MockContract[];
  let tokens: ERC20[];
  let gyroFund: GyroFund;
  let mockOracle: MockContract;

  const initialPoolWeights = [1, 1];

  //weth/dai and usdc/weth (actual pool addresses on mainnet)
  const gyroPoolAddresses = ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', '0x8a649274e4d777ffc6851f13d23a86bbfa2f2fbf'];

  const oracleAddresses = ['0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a', '0x8a649274e4d777ffc6851f13d23a86bbfa2f2fbf'];

  const weth = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
  const dai = '0x6b175474e89094c44da98b954eedeac495271d0f';
  const usdc = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';

  const underlyingTokens = [weth, dai, usdc];
  const underlyingTokenSymbols = ['WETH', 'DAI', 'USDC'];
  const stablecoinAddresses = ['0x6b175474e89094c44da98b954eedeac495271d0f', '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48'];

  const scaling = BigNumber.from(10).pow(18);

  function scale(value: BigNumberish): BigNumber {
    return BigNumber.from(value).mul(scaling);
  }

  function descale(value: BigNumberish): BigNumber {
    return BigNumber.from(value).div(scaling);
  }

  function percent(value: number): BigNumber {
    return scale(value).div(100);
  }

  function perThousand(value: number): BigNumber {
    return scale(value).div(1000);
  }

  const portfolioWeightEpsilon = percent(5);


  beforeEach(async function () {
    accounts = await ethers.getSigners();
    const wallet = accounts[0];

    mockPools = await Promise.all([
      deployMockContract(wallet, BalancerPoolArtifact.abi),
      deployMockContract(wallet, BalancerPoolArtifact.abi),
      deployMockContract(wallet, BalancerPoolArtifact.abi),
    ]);

    tokens = await Promise.all([
      new ERC20Factory(wallet).deploy("token1", "TOK1"),
      new ERC20Factory(wallet).deploy("token2", "TOK2"),
      new ERC20Factory(wallet).deploy("token3", "TOK3"),
    ]);

    gyroFund = (await deployContract(wallet, GyroFundArtifact, [
        portfolioWeightEpsilon,
        initialPoolWeights,
        gyroPoolAddresses,
        '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a',
        '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a',
        underlyingTokens,
        oracleAddresses,
        underlyingTokenSymbols,
        stablecoinAddresses]
      )) as GyroFund;

  });

  describe("checkStablecoinHealth", () => {

    const stablecoinprices = [scale(100), scale(200)];
    function checkStablecoinHealth() {
      return gyroFund.checkStablecoinHealth(
        stablecoinprices,
        stablecoinAddresses,
      );
    }

    it("should fail if a stablecoin is not healthy", async () => {
        expect(checkStablecoinHealth()).to.equal(false);

    });

});

});