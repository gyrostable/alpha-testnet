# Gyroscope core

## Initial setup

First, install the dependencies and compile using


```
yarn install
yarn compile
```

and for development purposes, link the package using

```
yarn link
```

## Running a node

Start a node

```
yarn node
```

In another terminal, deploy the contracts and export the deployment information using

```
yarn deploy
yarn export
```

At this stage, the SDK should work properly, try running the tests following the instructions at: https://github.com/stablecoin-labs/gyro-sdk
