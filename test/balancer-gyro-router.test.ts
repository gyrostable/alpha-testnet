import { deployContract, deployMockContract, MockContract } from "ethereum-waffle";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import BalancerPoolArtifact from "../artifacts/contracts/balancer/BPool.sol/BPool.json";
import BalancerExternalTokenRouterArtifact from "../artifacts/contracts/BalancerGyroRouter.sol/BalancerExternalTokenRouter.json";
import { BalancerExternalTokenRouter } from "../typechain/BalancerExternalTokenRouter";
import { ERC20 } from "../typechain/ERC20";
import { BalancerExternalTokenRouter__factory as BalancerExternalTokenRouterFactory } from "../typechain/factories/BalancerExternalTokenRouter__factory";
import { ERC20__factory as ERC20Factory } from "../typechain/factories/ERC20__factory";
import { expect } from "./chai";

describe("BalancerGyroRouter", function () {
  let accounts: Signer[];
  let router: BalancerExternalTokenRouter;
  let mockPools: MockContract[];
  let tokens: ERC20[];

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
    router = await new BalancerExternalTokenRouterFactory(wallet).deploy();

    await router.initializeOwner();
  });

  describe("addPool", function () {
    it("should add a pool with all its tokens", async function () {
      const [pool1, pool2] = mockPools.slice(0, 2);
      const [token1, token2, token3] = tokens.map((v) => v.address);
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
