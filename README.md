# Gyroscope core

This repository contains the core contracts and logic for Gyro reserves: https://gyro.finance

The documentation here is intended for contributors to this repository.
For the general Gyro documentation, please visit https://docs.gyro.finance


## Initial setup

First, install the dependencies and compile using

```
yarn install
yarn build
```

and for development purposes, link the package using

```
yarn link
```

## Running a node

Start a node

```
yarn run-node
```

This will print the accounts, including their private keys.
The first account holds many different tokens so we recommend importing
this account to MetaMask using its private key.

Then, in another terminal, deploy the contracts, export information and compile everything using

```
yarn build:full
```

At this stage, the SDK should work properly, try running the tests following the instructions at: https://github.com/stablecoin-labs/gyro-sdk


## Deploying to Kovan

```
yarn hardhat --network kovan deploy
yarn hardhat --network kovan run scripts/bind-pools.ts # bind balancer pools
yarn hardhat --network kovan run scripts/sync-prices.ts # set oracle prices
yarn hardhat --network kovan run scripts/setup-fund.ts # setup Gyro Fund
```

## Running tests

The tests are written using [Brownie](https://eth-brownie.readthedocs.io/).

Brownie needs to be installed first, using `pip install eth-brownie`

Tests can then be ran using

```
brownie test
```
