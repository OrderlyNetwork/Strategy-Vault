# Strategy Vault

## Specification
https://wootraders.atlassian.net/wiki/spaces/ORDER/pages/872644767/Strategy+Vault+Contract+Design+MVP

## Dependences

```shell
$ yarn
```

## Build

```shell
$ forge build
```
or 

```shell
$ npx hardhat vars set PRIVATE_KEY
$ npx hardhat vars set DEPLOY_KEY
$ npx hardhat compile
```

## Test

```shell
$ forge test
```

## Deploy

```shell
$ npx hardhat deploy-evm --env < env > --network < network >
$ npx hardhat deploy-orderly --env < env > --network < network >
```

