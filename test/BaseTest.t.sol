// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

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
    error SetProtocolSeizeShareOwnerCheck();
}

interface IEvents {
    // Emitted when the oracle list for a token is updated
    event TokenOraclesUpdated(address indexed token, IOracleSource[] newOracles);
    event UnderlyingSymbolSet(address indexed token, string symbol);
    event UnderlyingTokenPriceFeedSet(address indexed token, bytes32 priceFeedId);
    event UnderlyingTokenApi3ProxyAddressSet(address indexed token, address api3ProxyAddress);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);
}

contract BaseTest is Test, IError, IEvents {
    uint256 internal constant NO_ERROR = 0;

    CSonic public cSonic;
    CErc20Delegator public cWbtcDelegator;
    CErc20Delegator public cUsdcDelegator;
    CErc20Delegator public cWethDelegator;
    CErc20Delegate public cErc20Delegate;
    Comptroller public comptroller;
    JumpRateModelV2 public interestRateModel;
    ERC20Mock public wbtc;
    ERC20Mock public usdc;
    ERC20Mock public weth;

    uint256 internal baseRatePerYear = 0;
    uint256 internal multiplierPerYear = 0.25e18;
    uint256 internal jumpMultiplierPerYear = 5e18;
    uint256 internal kink_ = 0.8e18;
    uint8 internal cTokenDecimals = 8;
    uint256 internal nativeTokenDecimals = 18;

    address public admin = makeAddr("admin");

    // Ensure initially, 1 cToken = 0.02 underlying tokens
    function _deployBaselineContracts() internal {
        vm.label(admin, "admin");

        vm.startPrank(admin);
        comptroller = new Comptroller();
        interestRateModel = new JumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, admin);
        wbtc = new MockERC20(8);
        usdc = new MockERC20(6);
        weth = new MockERC20(18);
        cErc20Delegate = new CErc20Delegate();
        cWbtcDelegator = new CErc20Delegator(
            address(wbtc), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            (10 ** (wbtc.decimals() + 18 - cTokenDecimals)) / 50, // initialExchangeRateMantissa
            "Compound Wrapped Bitcoin", // name
            "cWBTC", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
        cUsdcDelegator = new CErc20Delegator(
            address(usdc), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            (10 ** (usdc.decimals() + 18 - cTokenDecimals)) / 50, // initialExchangeRateMantissa
            "Compound USDC", // name
            "cUSDC", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
        cWethDelegator = new CErc20Delegator(
            address(weth), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            (10 ** (weth.decimals() + 18 - cTokenDecimals)) / 50, // initialExchangeRateMantissa
            "Compound Wrapped Ethereum", // name
            "cWETH", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
        cSonic = new CSonic(
            comptroller,
            interestRateModel,
            (10 ** (nativeTokenDecimals + 18 - cTokenDecimals)) / 50, // initialExchangeRateMantissa
            "Sonic",
            "cSonic",
            18,
            payable(admin)
        );

        vm.assertEq(wbtc.decimals(), 8);
        vm.assertEq(usdc.decimals(), 6);
        vm.assertEq(weth.decimals(), 18);
        comptroller._supportMarket(CToken(address(cWbtcDelegator)));
        comptroller._supportMarket(CToken(address(cSonic)));
        vm.stopPrank();
    }
}
