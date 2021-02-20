import { BigNumber, BigNumberish } from "ethers";
import { readFile } from "fs/promises";
import { DeploymentsExtension } from "hardhat-deploy/types";
import path from "path";
import yaml from "yaml";

export const deploymentConfigPath = path.join(path.dirname(__dirname), "config", "deployments.yml");

export interface Token {
  name: string;
  symbol: string;
  decimals: number;
  balance: number;
  price: number;
  mintAmount: number;
  stable: boolean;
}

export interface Pool {
  name: string;
  assets: { symbol: string; amount: number; weight: number }[];
  swap_fee: number;
}

export interface TokenConfig {
  symbol: string;
  address?: string;
}

export interface PoolConfig {
  name: string;
  address?: string;
}

export interface Deployment {
  pools: PoolConfig[];
  tokens: TokenConfig[];
  bfactory?: string;
  oracles: { name: string; args: string[] }[];
  tokenOracles: Record<string, string>;
  memoryParam: string;
}

export interface DeploymentConfig {
  tokens: Record<string, Token>;
  pools: Record<string, Pool>;
  deployment: Deployment;
}

export async function getDeploymentConfig(networkName: string): Promise<DeploymentConfig> {
  const rawConfig = await readFile(deploymentConfigPath, "utf-8");
  const config = yaml.parse(rawConfig);
  const deployment = config.deployments[networkName];
  if (!deployment) {
    throw new Error(`no deployment config found for network ${networkName}`);
  }
  return {
    tokens: config.tokens,
    pools: config.pools,
    deployment,
  };
}

export function getTokenDeploymentName(symbol: string): string {
  return `token-${symbol}`;
}

export function getPoolDeploymentName(poolName: string): string {
  return `pool-${poolName}`;
}

export function scale(n: BigNumberish, decimals: number = 18): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(decimals));
}

export async function getBFactoryAddress(
  deployment: Deployment,
  deployments: DeploymentsExtension
): Promise<string> {
  if (deployment.bfactory) {
    return deployment.bfactory;
  }
  const bfactoryDeployment = await deployments.get("BFactory");
  return bfactoryDeployment.address;
}

export async function getTokenAddress(
  token: string | { symbol: string },
  deployment: Deployment,
  deployments: DeploymentsExtension
): Promise<string> {
  const symbol = typeof token === "string" ? token : token.symbol;
  const tokenConfig = deployment.tokens.find((t) => t.symbol === symbol);
  if (!tokenConfig) {
    throw new Error(`no token ${symbol} in current deployment`);
  }
  if (tokenConfig.address) {
    return tokenConfig.address;
  }
  const tokenDeploymentName = getTokenDeploymentName(symbol);
  const tokenDeployment = await deployments.get(tokenDeploymentName);
  return tokenDeployment.address;
}

export async function getTokensAddresses(
  tokens: (string | { symbol: string })[],
  deployment: Deployment,
  deployments: DeploymentsExtension
): Promise<string[]> {
  return Promise.all(tokens.map((token) => getTokenAddress(token, deployment, deployments)));
}

export async function getBPoolAddress(
  pool: string | { name: string },
  deployment: Deployment,
  deployments: DeploymentsExtension
): Promise<string> {
  const poolName = typeof pool === "string" ? pool : pool.name;
  const poolConfig = deployment.pools.find((p) => p.name === poolName);
  if (!poolConfig) {
    throw new Error(`no pool ${poolName} in current deployment`);
  }
  if (poolConfig.address) {
    return poolConfig.address;
  }
  const poolDeploymentName = getPoolDeploymentName(poolName);
  const poolDeployment = await deployments.get(poolDeploymentName);
  return poolDeployment.address;
}

export async function getBPoolsAddresses(
  pools: (string | { name: string })[],
  deployment: Deployment,
  deployments: DeploymentsExtension
): Promise<string[]> {
  return Promise.all(pools.map((pool) => getBPoolAddress(pool, deployment, deployments)));
}

export async function transformArgs(
  args: string[],
  deployments: DeploymentsExtension
): Promise<string[]> {
  const transformed = [];
  for (const arg of args) {
    if (arg.startsWith("address:")) {
      const deploymentName = arg.replace("address:", "");
      const deployment = await deployments.get(deploymentName);
      transformed.push(deployment.address);
    } else {
      transformed.push(arg);
    }
  }
  return transformed;
}
