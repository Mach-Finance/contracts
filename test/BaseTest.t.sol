// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import "./mocks/MockERC20.sol";
import "../src/CErc20Delegator.sol";
import "../src/CErc20Delegate.sol";
import "../src/CSonic.sol";
import "../src/ComptrollerInterface.sol";
import "../src/InterestRateModel.sol";
import "../src/Comptroller.sol";
import "../src/JumpRateModelV2.sol";
import "../src/Oracles/IOracleSource.sol";

interface IError {
    // Error thrown when an unauthorized account tries to call an Ownable function
    error OwnableUnauthorizedAccount(address account);
}

interface IEvents {
    // Emitted when the oracle list for a token is updated
    event TokenOraclesUpdated(address indexed token, IOracleSource[] newOracles);
    event UnderlyingSymbolSet(address indexed token, string symbol);
    event UnderlyingTokenPriceFeedSet(address indexed token, bytes32 priceFeedId);
}

contract BaseTest is Test, IError, IEvents {
    CSonic public cSonic;
    CErc20Delegator public cWbtcDelegator;
    CErc20Delegate public cErc20Delegate;
    Comptroller public comptroller;
    JumpRateModelV2 public interestRateModel;
    ERC20Mock public wbtc;

    uint256 internal baseRatePerYear = 0;
    uint256 internal multiplierPerYear = 0.25e18;
    uint256 internal jumpMultiplierPerYear = 5e18;
    uint256 internal kink_ = 0.8e18;

    address public admin = makeAddr("admin");

    function _deployBaselineContracts() internal {
        vm.label(admin, "admin");

        vm.startPrank(admin);
        comptroller = new Comptroller();
        interestRateModel = new JumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, admin);
        wbtc = new MockERC20(8);
        cErc20Delegate = new CErc20Delegate();
        cWbtcDelegator = new CErc20Delegator(
            address(wbtc), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            1e18, // initialExchangeRateMantissa
            "Compound Wrapped Bitcoin", // name
            "cWBTC", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
        cSonic = new CSonic(comptroller, interestRateModel, 1e18, "Sonic", "cSonic", 18, payable(admin));

        vm.assertEq(wbtc.decimals(), 8);

        comptroller._supportMarket(CToken(address(cWbtcDelegator)));
        comptroller._supportMarket(cSonic);
        vm.stopPrank();
    }
}
