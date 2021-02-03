import { deployMockContract, MockContract } from "ethereum-waffle";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { ethers } from "hardhat";
import { ABI } from "hardhat-deploy/types";
import GyroFundArtifact from "../artifacts/contracts/GyroFund.sol/GyroFundV1.json";
import BalancerExternalTokenRouterArtifact from "../artifacts/contracts/BalancerGyroRouter.sol/BalancerExternalTokenRouter.json";
import { BalancerExternalTokenRouter, GyroFundV1, GyroLib, GyroLib__factory } from "../typechain";
import { expect } from "./chai";

describe("GyroLib", () => {
  let gyroLib: GyroLib;
  let gyroFund: MockContract;
  let externalRouter: MockContract;

  const scale = (value: BigNumberish, decimals: BigNumberish = 18) => {
    return BigNumber.from(value).mul(BigNumber.from(10).pow(decimals));
  };

  async function deployTypedMockContract<T>(wallet: Signer, abi: ABI) {
    const deployed = await deployMockContract(wallet, abi);
    return (deployed as unknown) as T;
  }

  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    const wallet = accounts[0];
    externalRouter = await deployTypedMockContract(wallet, BalancerExternalTokenRouterArtifact.abi);
    gyroFund = await deployTypedMockContract(wallet, GyroFundArtifact.abi);
    gyroLib = await new GyroLib__factory(accounts[0]).deploy(
      gyroFund.address,
      externalRouter.address
    );
  });

  describe("estimateUnderlyingTokens", () => {
    const pools = [
      "0xbC2E60B7BCCFe5DB97984b534AA997932438051F",
      "0xA090B79EeD1301f5CD5fDC16476DBD702cfF2401",
    ];

    it("should forward arguments to router", async () => {
      const amounts = [scale(10), scale(20)];
      const msg = "failed estimateDeposit";
      await externalRouter.mock.estimateDeposit.withArgs(pools, amounts).revertsWithReason(msg);
      await expect(gyroLib.estimateUnderlyingTokens(pools, amounts)).to.be.revertedWith(msg);
    });

    it("should reorder pools", async () => {
      const amounts = [scale(10), scale(20), scale(15)];
      const callPools = [pools[1], pools[1], pools[0]];
      await externalRouter.mock.estimateDeposit.returns(callPools, amounts);
      await gyroFund.mock.poolAddresses.returns(pools);
      const expectedAmounts = [scale(15), scale(30)];
      await gyroFund.mock.estimateMint.withArgs(pools, expectedAmounts).returns(scale(30));
      const result = await gyroLib.estimateUnderlyingTokens([], []);
      expect(result.toString()).to.eq(scale(30).toString());
    });
  });
});
