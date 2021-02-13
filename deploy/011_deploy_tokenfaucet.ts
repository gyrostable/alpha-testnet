import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import initConfig from "../config/initialization.json";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const [deployer] = await ethers.getSigners();
  const { deployments } = hre;
  const { deploy, execute } = deployments;
  if (hre.network.live) {
    return;
  }
const token = {"symbol": "DAI", "name": "DAI", "decimals":18, "mintAmt":100}

const deploymentName = `${token.symbol}faucet`;
const deploymentResult = await deploy(deploymentName, {
    contract: "TokenFaucet",
    from: deployer.address,
    args: [token.name, token.symbol, token.decimals, token.mintAmt],
    log: true,
    deterministicDeployment: true,
});
if (deploymentResult.newlyDeployed) {
    await execute(deploymentName, { from: deployer.address }, "initializeOwner");
}

await execute(
    deploymentName,
    { from: deployer.address },
    "mintAsOwner",
    deployer.address,
    BigNumber.from(10).pow(token.decimals + 6) // 1M of each token
);
};

export default func;
