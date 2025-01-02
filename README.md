# Mach Finance

Mach Finance is a fork of Compound Finance v2 with additional features such as supply caps and one click mint to use as collateral.
The protocol will be deployed as a native application on the upcoming Sonic Network. 

## What is different about Mach Finance?
- **Supply Caps**: The protocol will have a maximum supply for each cToken.
- **Mint and use asset as collateral**: Users will be able to mint cTokens and use them as collateral for borrowing in a single function call for better UX.
- **block.timestamp vs block.number**: The protocol will use `block.timestamp` for all interest rate calculations, instead of `block.number`.
- **Reward Distribution**: Instead of the `Comptroller` updating & distributing rewards, a separate contract `RewardDistributor` (WIP) will be responsible for distributing rewards.
- **Price Oracle**: Via an Upgradable `PriceOracleAggregator.sol`, the protocol has a priority list of price feeds such as Pyth and API3 to fetch price data.
- **Protocol Seize Share**: Make `protocolSeizeShare` a modifiable variable by the admin.
- **Sweep**: Add `sweepToken` and `sweepNative` functions to allow the admin to sweep any ERC-20 tokens or $S (except the underlying asset) from the `cSonic` or `cErc20` contracts to the admin address

More details can be found in the [audit brief](audit/brief.md).

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --force
```

### Format

```shell
$ forge fmt
```

### Deploy on SONIC Testnet

```shell
$ forge script ./script/TestnetDeployment.s.sol --rpc-url sonic_testnet --force --sender <sender_address> --ledger --broadcast
```

```shell
$ forge script ./script/Deployment.s.sol --rpc-url sonic_mainnet --force --account <account_name>
```
