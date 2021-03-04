const [signer] = await ethers.getSigners();
const {
  CompoundPriceWrapper__factory,
} = require("./typechain/factories/CompoundPriceWrapper__factory");
const {
  UniswapAnchoredView__factory,
} = require("./typechain/factories/UniswapAnchoredView__factory");
const { ERC20__factory } = require("./typechain/factories/ERC20__factory");

const { GyroFundV1__factory } = require("./typechain/factories/GyroFundV1__factory");

const compoundPriceWrapper = CompoundPriceWrapper__factory.connect(
  (await deployments.get("CompoundPriceWrapper")).address,
  signer
);

const uniswapAnchor = UniswapAnchoredView__factory.connect(
  (await deployments.get("UniswapAnchoredView")).address,
  signer
);

const gyroFund = GyroFundV1__factory.connect((await deployments.get("GyroProxy")).address, signer);
