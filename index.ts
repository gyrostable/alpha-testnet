// export type { GyroFund } from "./typechain/GyroFund";

export type { ERC20 } from "./typechain/ERC20";
export type { BalancerExternalTokenRouter } from "./typechain/BalancerExternalTokenRouter";
export type { BalancerTokenRouter } from "./typechain/BalancerTokenRouter";
export type { UniswapAnchoredView } from "./typechain/UniswapAnchoredView";
export type { GyroFund } from "./typechain/GyroFund";
export type { GyroFundV1 } from "./typechain/GyroFundV1";
export type { GyroLib } from "./typechain/GyroLib";
export type { GyroPriceOracle } from "./typechain/GyroPriceOracle";
export type { GyroRouter } from "./typechain/GyroRouter";

export { ERC20__factory } from "./typechain/factories/ERC20__factory";
export { BalancerExternalTokenRouter__factory } from "./typechain/factories/BalancerExternalTokenRouter__factory";
export { BalancerTokenRouter__factory } from "./typechain/factories/BalancerTokenRouter__factory";
export { UniswapAnchoredView__factory } from "./typechain/factories/UniswapAnchoredView__factory";
export { GyroFund__factory } from "./typechain/factories/GyroFund__factory";
export { GyroFundV1__factory } from "./typechain/factories/GyroFundV1__factory";
export { GyroLib__factory } from "./typechain/factories/GyroLib__factory";
export { GyroPriceOracle__factory } from "./typechain/factories/GyroPriceOracle__factory";
export { GyroRouter__factory } from "./typechain/factories/GyroRouter__factory";

import _deployment from "./artifacts/deployment.json";

export const deployment = _deployment;
