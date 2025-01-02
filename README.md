# MachFi

MachFi is a fork of Compound Finance v2 with additional features such as supply caps and one click mint to use as collateral.
The protocol will be deployed as a native application on the upcoming Sonic Network. 

## Audit Report

Security is a top priority at MachFi. To ensure the robustness and reliability of our smart contracts, MachFi has undergone a comprehensive audit contest conducted by Sherlock. You can review the detailed audit report [here](audit/Mach%20Finance%20Audit%20Report.pdf).

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

### Deployment scripts

```shell
$ forge script ./script/TestnetDeployment.s.sol --rpc-url sonic_testnet --force --sender <sender_address> --ledger --broadcast
```

```shell
$ forge script ./script/Deployment.s.sol --rpc-url sonic_mainnet --force --account <account_name>
```
