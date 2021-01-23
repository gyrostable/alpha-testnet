import { deployContract, deployMockContract, MockContract } from "ethereum-waffle";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import BalancerPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import BalancerExternalTokenRouterArtifact from "../artifacts/contracts/BalancerGyroRouter.sol/BalancerExternalTokenRouter.json";
import { BalancerGyroRouter } from "../typechain/BalancerGyroRouter";
import { Ownable } from "../typechain/Ownable";
import { expect } from "./chai";

describe("BalancerGyroRouter", function () {
  let accounts: Signer[];
  let router: BalancerGyroRouter & Ownable;
  let mockPools: MockContract[];

  const dummyAddresses = [
    "0x88a5c2d9919e46f883eb62f7b8dd9d0cc45bc290",
    "0x14791697260E4c9A71f18484C9f997B308e59325",
    "0xaC39b311DCEb2A4b2f5d8461c1cdaF756F4F7Ae9",
  ];

  beforeEach(async function () {
    accounts = await ethers.getSigners();
    const wallet = accounts[0];

    mockPools = await Promise.all([
      deployMockContract(wallet, BalancerPoolArtifact.abi),
      deployMockContract(wallet, BalancerPoolArtifact.abi),
      deployMockContract(wallet, BalancerPoolArtifact.abi),
    ]);

    router = (await deployContract(
      wallet,
      BalancerExternalTokenRouterArtifact
    )) as BalancerGyroRouter & Ownable;
    await router.initializeOwner();
  });

  describe("addPool", function () {
    it("should add a pool with all its tokens", async function () {
      const [pool1, pool2] = mockPools.slice(0, 2);
      const [token1, token2, token3] = dummyAddresses.slice(0, 3);
      await pool1.mock.isFinalized.returns(true);

      await pool1.mock.getFinalTokens.returns([token1, token2]);
      await router.addPool(pool1.address);
      let token1Pool1 = await router.pools(token1, 0);
      expect(token1Pool1).to.eq(pool1.address);
      let token2Pool1 = await router.pools(token2, 0);
      expect(token2Pool1).to.eq(pool1.address);

      await pool2.mock.isFinalized.returns(true);
      await pool2.mock.getFinalTokens.returns([token2, token3]);
      await router.addPool(pool2.address);
      token2Pool1 = await router.pools(token2, 0);
      expect(token2Pool1).to.eq(pool1.address);
      let token2Pool2 = await router.pools(token2, 1);
      expect(token2Pool2).to.eq(pool2.address);

      await router.addPool(pool2.address);
      token2Pool2 = await router.pools(token2, 1);
      expect(token2Pool2).to.eq(pool2.address);
      expect(router.pools(token2, 2)).to.be.rejected;
    });
  });
});
