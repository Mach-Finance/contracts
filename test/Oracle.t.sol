// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {BaseTest} from "./BaseTest.t.sol";
import {PythOracle} from "../src/Oracles/Pyth/PythOracle.sol";
import {CToken} from "../src/CToken.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {BandOracle} from "../src/Oracles/Band/BandOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {IOracleSource} from "../src/Oracles/IOracleSource.sol";
import {MockPriceOracleAggregatorV2} from "./mocks/MockPriceOracleAggregatorV2.sol";
import {API3Oracle} from "../src/Oracles/API3/API3Oracle.sol";
import {IApi3ReaderProxy} from "@api3/contracts/interfaces/IApi3ReaderProxy.sol";
import {IStdReference} from "../src/Oracles/Band/IStdReference.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Helper functions for upgrading contracts from OpenZeppelin, works with Foundry
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import "forge-std/console.sol";

contract OracleTest is BaseTest {
    address constant SONIC_BLAZE_TESTNET_API3_FTM_PROXY = 0x8927DA1377C78D25E78c335F48a6f8e42Cce0C09;
    address constant SONIC_BLAZE_TESTNET_API3_WBTC_PROXY = 0x041a131Fa91Ad61dD85262A42c04975986580d50;
    address constant SONIC_BLAZE_TESTNET_API3_USDC_PROXY = 0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f;
    address constant SONIC_BLAZE_TESTNET_API3_SOLV_PROXY = 0xadf6e9419E483Cc214dfC9EF1887f3aa7e85cA09;
    address constant SONIC_BLAZE_TESTNET_API3_ETH_PROXY = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;

    address constant SONIC_BLAZE_TESTNET_PYTH_ORACLE = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    address constant SONIC_BLAZE_TESTNET_BAND_ORACLE = 0x8c064bCf7C0DA3B3b090BAbFE8f3323534D84d68;

    uint256 constant SONIC_BLAZE_TESTNET_CHAIN_ID = 57054;

    bytes32 constant FTM_PRICE_FEED_ID = 0x5c6c0d2386e3352356c3ab84434fafb5ea067ac2678a38a338c4a69ddc4bdb0c;
    bytes32 constant WBTC_PRICE_FEED_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    bytes32 constant USDC_PRICE_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant ETH_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant SOLVBTC_PRICE_FEED_ID = 0xf253cf87dc7d5ed5aa14cba5a6e79aee8bcfaef885a0e1b807035a0bbecc36fa;

    address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint8 constant PRICE_SCALE = 36;

    // Set block.number to the time of the PythPriceFeedData.txt feed update (25 December 2024 16:03:48 UTC) - Merry Christmas!
    uint256 constant SONIC_BLAZE_TESTNET_FORK_BLOCK_NUMBER = 6925940;
    uint256 constant SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP = 1735142628;
    uint256 constant PYTH_STALE_PRICE_THRESHOLD = 1 hours;
    uint256 constant API3_STALE_PRICE_THRESHOLD = 24 hours;

    string SONIC_BLAZE_TESTNET_RPC_URL = vm.envString("SONIC_BLAZE_TESTNET_RPC_URL");

    bytes[] pythPriceUpdate;

    /// Dynamic variables
    address pythOracleAddress;
    IPyth pyth;

    address bandOracleAddress;

    // Fork chain variables
    uint256 sonicBlazeTestnetFork;

    PythOracle public pythOracle;
    BandOracle public bandOracle;
    API3Oracle public api3Oracle;
    PriceOracleAggregator public priceOracleAggregator;

    function setUp() public {
        sonicBlazeTestnetFork = vm.createFork(SONIC_BLAZE_TESTNET_RPC_URL, SONIC_BLAZE_TESTNET_FORK_BLOCK_NUMBER);

        vm.selectFork(sonicBlazeTestnetFork);
        vm.warp(SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP);
        pythOracleAddress = SONIC_BLAZE_TESTNET_PYTH_ORACLE;
        pyth = IPyth(pythOracleAddress);
        bandOracleAddress = SONIC_BLAZE_TESTNET_BAND_ORACLE;

        vm.label(SONIC_BLAZE_TESTNET_PYTH_ORACLE, "SONIC_BLAZE_TESTNET_PYTH_ORACLE");
        vm.label(SONIC_BLAZE_TESTNET_BAND_ORACLE, "SONIC_BLAZE_TESTNET_BAND_ORACLE");
        vm.label(SONIC_BLAZE_TESTNET_API3_FTM_PROXY, "SONIC_BLAZE_TESTNET_API3_FTM_PROXY");
        vm.label(SONIC_BLAZE_TESTNET_API3_WBTC_PROXY, "SONIC_BLAZE_TESTNET_API3_WBTC_PROXY");
        vm.label(SONIC_BLAZE_TESTNET_API3_USDC_PROXY, "SONIC_BLAZE_TESTNET_API3_USDC_PROXY");
        vm.label(SONIC_BLAZE_TESTNET_API3_SOLV_PROXY, "SONIC_BLAZE_TESTNET_API3_SOLV_PROXY");
        vm.label(SONIC_BLAZE_TESTNET_API3_ETH_PROXY, "SONIC_BLAZE_TESTNET_API3_ETH_PROXY");

        _deployBaselineContracts();
        _deployPythOracle();
        _deployBandOracle();
        _deployAPI3Oracle();
        _deployPriceOracleAggregator();
    }

    function _deployPythOracle() internal {
        vm.startPrank(admin);
        address[] memory underlyingTokens = new address[](4);
        underlyingTokens[0] = address(wbtc);
        underlyingTokens[1] = NATIVE_ASSET;
        underlyingTokens[2] = address(usdc);
        underlyingTokens[3] = address(weth);

        bytes32[] memory priceFeedIds = new bytes32[](4);
        priceFeedIds[0] = WBTC_PRICE_FEED_ID;
        priceFeedIds[1] = FTM_PRICE_FEED_ID;
        priceFeedIds[2] = USDC_PRICE_FEED_ID;
        priceFeedIds[3] = ETH_PRICE_FEED_ID;

        pythOracle =
            new PythOracle(admin, pythOracleAddress, underlyingTokens, priceFeedIds, PYTH_STALE_PRICE_THRESHOLD);
        vm.stopPrank();

        // Ensure Pyth price feeds are not stale
        _updatePythPriceFeeds();
    }

    /**
     * @dev Update Pyth price feed for supported tokens (USDC, WBTC, FTM, SOLVBTC, ETH) from Hermes
     * @notice Off-chain agents are responsible for updating the price feed (Pull Oracle model)
     */
    function _updatePythPriceFeeds() internal {
        // Data retrieved from Pyth Hermes -> https://hermes.pyth.network/docs/#/rest/latest_price_updates) on 25 December 2024 16:03:48 UTC
        string memory updateDataStr = vm.readFile("./test/mocks/PythPriceFeedData.txt");
        string memory updateDataPrefixedStr = string.concat("0x", updateDataStr);
        bytes memory updateDataBytes = vm.parseBytes(updateDataPrefixedStr);

        bytes[] memory updateData = new bytes[](1);
        updateData[0] = updateDataBytes;

        // Update Pyth price feed for supported tokens (USDC, WBTC, FTM, SOLVBTC, ETH)
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: fee}(updateData);
    }

    function _deployBandOracle() internal {
        vm.startPrank(admin);
        address[] memory underlyingTokens = new address[](3);
        underlyingTokens[0] = address(wbtc);
        underlyingTokens[1] = NATIVE_ASSET;
        underlyingTokens[2] = address(usdc);

        string[] memory bandSymbols = new string[](3);
        bandSymbols[0] = "WBTC";
        bandSymbols[1] = "FTM";
        bandSymbols[2] = "USDC";

        bandOracle = new BandOracle(admin, bandOracleAddress, underlyingTokens, bandSymbols);
        vm.stopPrank();
    }

    function _deployAPI3Oracle() internal {
        vm.startPrank(admin);

        address[] memory underlyingTokens = new address[](4);
        underlyingTokens[0] = NATIVE_ASSET;
        underlyingTokens[1] = address(wbtc);
        underlyingTokens[2] = address(usdc);
        underlyingTokens[3] = address(weth);

        address[] memory api3ProxyAddresses = new address[](4);
        api3ProxyAddresses[0] = SONIC_BLAZE_TESTNET_API3_FTM_PROXY;
        api3ProxyAddresses[1] = SONIC_BLAZE_TESTNET_API3_WBTC_PROXY;
        api3ProxyAddresses[2] = SONIC_BLAZE_TESTNET_API3_USDC_PROXY;
        api3ProxyAddresses[3] = SONIC_BLAZE_TESTNET_API3_ETH_PROXY;

        api3Oracle = new API3Oracle(admin, underlyingTokens, api3ProxyAddresses);

        vm.assertEq(api3Oracle.stalePriceThreshold(), API3_STALE_PRICE_THRESHOLD);
        vm.stopPrank();
    }

    function _deployPriceOracleAggregator() internal {
        vm.startPrank(admin);

        address priceOracleAggregatorProxyAddress = Upgrades.deployUUPSProxy(
            "PriceOracleAggregator.sol", abi.encodeCall(PriceOracleAggregator.initialize, (admin))
        );
        priceOracleAggregator = PriceOracleAggregator(payable(priceOracleAggregatorProxyAddress));

        IOracleSource[] memory oracles = new IOracleSource[](3);
        oracles[0] = pythOracle;
        oracles[1] = api3Oracle;
        oracles[2] = bandOracle;

        priceOracleAggregator.updateTokenOracles(address(wbtc), oracles);
        priceOracleAggregator.updateTokenOracles(NATIVE_ASSET, oracles);
        priceOracleAggregator.updateTokenOracles(address(usdc), oracles);
        vm.stopPrank();
    }

    function test_pythOracle_getUnderlyingPrice() public {
        // BTC hovers around 10k - 100k
        // BTC decimals = 8
        // adjustedPrice = (price * 10^(decimals - exponent)) * 10^(36 - decimals) = price * 10^28
        // A 33-digit number would be between 10^32 and 10^33
        (uint256 btcPrice, bool isBtcPriceValid) = pythOracle.getPrice(address(wbtc));
        vm.assertGt(btcPrice, 1e32);
        vm.assertLt(btcPrice, 1e33);
        vm.assertTrue(isBtcPriceValid);
        console.log("btcPrice", btcPrice);

        // FTM decimals = 18
        // adjustedPrice = (price * 10^(exponent)) * 10^(36 - decimals - exponent) = price * 10^18
        (uint256 ftmPrice, bool isFtmPriceValid) = pythOracle.getPrice(NATIVE_ASSET);
        vm.assertGt(ftmPrice, 0.8e18);
        vm.assertLt(ftmPrice, 1.3e18);
        vm.assertTrue(isFtmPriceValid);

        console.log("ftmPrice", ftmPrice);

        // USDC decimals = 6
        // adjustedPrice = (price * 10^(exponent)) * 10^(36 - decimals - exponent) = price * 10^30
        (uint256 usdcPrice, bool isUsdcPriceValid) = pythOracle.getPrice(address(usdc));
        vm.assertGt(usdcPrice, 0.9e30);
        vm.assertLt(usdcPrice, 1.1e30);
        vm.assertTrue(isUsdcPriceValid);
        console.log("usdcPrice", usdcPrice);
    }

    function test_bandOracle_getUnderlyingPrice() public {
        (uint256 btcPrice, bool isBtcPriceValid) = bandOracle.getPrice(address(wbtc));

        // Assert price between 75k and 125k
        vm.assertGt(btcPrice, 7.5e32);
        vm.assertLt(btcPrice, 1.25e33);
        vm.assertTrue(isBtcPriceValid);
        console.log("btcPrice", btcPrice);

        (uint256 ftmPrice, bool isFtmPriceValid) = bandOracle.getPrice(NATIVE_ASSET);
        vm.assertGt(ftmPrice, 0.8e18);
        vm.assertLt(ftmPrice, 1.3e18);
        vm.assertTrue(isFtmPriceValid);
        console.log("ftmPrice", ftmPrice);

        (uint256 usdcPrice, bool isUsdcPriceValid) = bandOracle.getPrice(address(usdc));
        vm.assertGt(usdcPrice, 0.9e30);
        vm.assertLt(usdcPrice, 1.1e30);
        vm.assertTrue(isUsdcPriceValid);
        console.log("usdcPrice", usdcPrice);
    }

    function test_api3Oracle_getUnderlyingPrice() public {
        (uint256 wbtcPrice, bool isWbtcPriceValid) = api3Oracle.getPrice(address(wbtc));

        // Assert price between 75k and 125k
        vm.assertGt(wbtcPrice, 7.5e32);
        vm.assertLt(wbtcPrice, 1.25e33);
        vm.assertTrue(isWbtcPriceValid);
        console.log("wbtcPrice", wbtcPrice);

        // ETH hovers around $3.3-3.5k during the forked block
        (uint256 wethPrice, bool isWethPriceValid) = api3Oracle.getPrice(address(weth));
        vm.assertGt(wethPrice, 3300e18);
        vm.assertLt(wethPrice, 3500e18);
        vm.assertTrue(isWethPriceValid);
        console.log("wethPrice", wethPrice);

        // FTM was around ~$1 during the forked block
        (uint256 ftmPrice, bool isFtmPriceValid) = api3Oracle.getPrice(NATIVE_ASSET);
        vm.assertGt(ftmPrice, 0.9e18);
        vm.assertLt(ftmPrice, 1.1e18);
        vm.assertTrue(isFtmPriceValid);
        console.log("ftmPrice", ftmPrice);
    }

    function testFuzz_pythOracle_getPrice_withDifferingDecimals(uint8 decimals) public {
        // Set feed decimals to 8 to match Pyth oracle configuration
        uint8 feedDecimals = 8;

        // Ensure decimals don't exceed max allowed (PRICE_SCALE - feedDecimals) to avoid "0" price due to round down division
        vm.assume((PRICE_SCALE - feedDecimals) >= decimals);

        ERC20 usdc = new MockERC20(decimals); // Mock USDC with fuzzed decimal places

        vm.prank(admin);
        pythOracle.setPriceFeedId(address(usdc), USDC_PRICE_FEED_ID); // Configure price feed for mock token

        (uint256 price, bool isValid) = pythOracle.getPrice(address(usdc)); // Get scaled price from oracle

        // Price should be between $0.90 and $1.10 scaled to appropriate decimals
        vm.assertGe(price, (9 * 10 ** (PRICE_SCALE - decimals)) / 10); // Assert >= $0.90
        vm.assertLe(price, (11 * 10 ** (PRICE_SCALE - decimals)) / 10); // Assert <= $1.10

        vm.assertTrue(isValid);
    }

    function testFuzz_api3Oracle_getPrice_withDifferingDecimals(uint8 decimals, uint256 priceInUsd) public {
        vm.assume(decimals <= 18);
        // Constraint priceInUsd from $1 to $100 million
        priceInUsd = bound(priceInUsd, 1, 1e8);

        uint256 API3_SCALING_FACTOR = 18;

        MockERC20 mockToken = new MockERC20(decimals);
        address mockApi3Proxy = makeAddr("mockApi3ProxyAddress");

        int224 mockedPrice = int224(uint224(priceInUsd * 1e18));
        vm.mockCall(
            mockApi3Proxy,
            abi.encodeWithSelector(IApi3ReaderProxy.read.selector),
            abi.encode(mockedPrice, block.timestamp) // timestamp returned is not "block.timestamp", its just a placeholder
        );

        vm.prank(admin);
        api3Oracle.setApi3ProxyAddress(address(mockToken), mockApi3Proxy);

        (uint256 api3OraclePrice, bool isValid) = api3Oracle.getPrice(address(mockToken));
        vm.assertEq(api3OraclePrice, priceInUsd * 10 ** (API3_SCALING_FACTOR + 18 - decimals));
        vm.assertTrue(isValid);
    }

    function testFuzz_api3Oracle_getPrice_negativeValues(uint8 decimals, uint256 priceInUsd) public {
        vm.assume(decimals <= 18);
        priceInUsd = bound(priceInUsd, 1, 1e8);

        MockERC20 mockToken = new MockERC20(decimals);
        address mockApi3Proxy = makeAddr("mockApi3ProxyAddress");

        int224 mockedNegativePrice = -1 * int224(uint224(priceInUsd * 1e18));
        vm.mockCall(
            mockApi3Proxy,
            abi.encodeWithSelector(IApi3ReaderProxy.read.selector),
            abi.encode(mockedNegativePrice, block.timestamp)
        );

        (uint256 api3OraclePrice, bool isValid) = api3Oracle.getPrice(address(mockToken));
        vm.assertEq(api3OraclePrice, 0);
        vm.assertFalse(isValid);
    }

    function testFuzz_bandOracle_getPrice_withDifferingDecimals(uint8 decimals, uint256 priceInUsd) public {
        vm.assume(decimals <= 18);
        priceInUsd = bound(priceInUsd, 1, 1e8);

        uint256 BAND_SCALING_FACTOR = 18;

        MockERC20 mockToken = new MockERC20(decimals);
        address mockBandProxy = makeAddr("mockBandProxyAddress");

        int224 mockedPrice = int224(uint224(priceInUsd * 1e18));
        vm.mockCall(
            SONIC_BLAZE_TESTNET_BAND_ORACLE,
            abi.encodeWithSelector(IStdReference.getReferenceData.selector),
            abi.encode(mockedPrice, block.timestamp, block.timestamp)
        );

        vm.prank(admin);
        bandOracle.setUnderlyingSymbol(address(mockToken), "USDT");

        (uint256 bandOraclePrice, bool isValid) = bandOracle.getPrice(address(mockToken));
        vm.assertEq(bandOraclePrice, priceInUsd * 10 ** (BAND_SCALING_FACTOR + 18 - decimals));
        vm.assertTrue(isValid);
    }

    function test_priceOracleAggregator_getUnderlyingPrice() public {
        // Check underlyingPrice for BTC for Pyth price feed update on (25 December 2024 16:03:48 UTC)
        uint256 btcPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cWbtcDelegator)));
        vm.assertGt(btcPrice, 98.1e31);
        vm.assertLt(btcPrice, 98.2e31);

        // Check underlyingPrice for FTM for Pyth price feed update on (25 December 2024 16:03:48 UTC)
        uint256 ftmPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        vm.assertGt(ftmPrice, 0.98e18);
        vm.assertLt(ftmPrice, 0.99e18);
    }

    function test_whenNoOracleSourceFoundForToken() public {
        // Deploy CErc20Delegator with no oracle source
        MockERC20 mockErc20 = new MockERC20(12);
        vm.prank(admin);
        CErc20Delegator cErc20Delegator = new CErc20Delegator(
            address(mockErc20), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            2 * 10 ** (mockErc20.decimals() + 18 - cTokenDecimals - 2), // initialExchangeRateMantissa
            "Compound Mock", // name
            "cMock", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
        uint256 price = priceOracleAggregator.getUnderlyingPrice(CToken(address(cErc20Delegator)));
        vm.assertEq(price, 0);
    }

    function test_pythOracle_getPrice_stalePrice() public {
        address[] memory cTokens = new address[](4);
        cTokens[0] = address(wbtc);
        cTokens[1] = address(weth);
        cTokens[2] = address(usdc);
        cTokens[3] = NATIVE_ASSET;

        for (uint256 i = 0; i < cTokens.length; i++) {
            address cToken = cTokens[i];

            // Shouldn't be stale yet
            vm.warp(SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP + PYTH_STALE_PRICE_THRESHOLD / 2);
            (uint256 price, bool isValid) = pythOracle.getPrice(cToken);
            vm.assertGt(price, 0);
            vm.assertTrue(isValid);

            // Fast forward as much as stale price threshold
            vm.warp(SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP + PYTH_STALE_PRICE_THRESHOLD + 1 seconds);
            (price, isValid) = pythOracle.getPrice(cToken);
            vm.assertEq(price, 0);
            vm.assertFalse(isValid);

            // Update Stale Pirce threshold to longer, to make sure prices are not-stale
            vm.prank(admin);
            pythOracle.setStalePriceThreshold(PYTH_STALE_PRICE_THRESHOLD * 2 + 1);
            (price, isValid) = pythOracle.getPrice(cToken);
            vm.assertGt(price, 0);
            vm.assertTrue(isValid);

            // Update Stale Price threshold to shorter, to make sure prices are stale
            vm.prank(admin);
            pythOracle.setStalePriceThreshold(PYTH_STALE_PRICE_THRESHOLD - 1 seconds);
            (price, isValid) = pythOracle.getPrice(cToken);
            vm.assertEq(price, 0);
            vm.assertFalse(isValid);
        }
    }

    function test_api3Oracle_getPrice_stalePrice() public {
        address[] memory underlyingTokens = new address[](3);
        underlyingTokens[0] = address(wbtc);
        underlyingTokens[1] = address(weth);
        underlyingTokens[2] = NATIVE_ASSET;

        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            address underlyingToken = underlyingTokens[i];

            // Shouldn't be stale yet
            vm.warp(SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP);
            (uint256 price, bool isValid) = api3Oracle.getPrice(underlyingToken);
            vm.assertGt(price, 0);
            vm.assertTrue(isValid);

            // Fast forward as much as stale price threshold
            vm.warp(SONIC_BLAZE_TESTNET_FORK_BLOCK_TIMESTAMP + API3_STALE_PRICE_THRESHOLD + 1 seconds);
            (price, isValid) = api3Oracle.getPrice(underlyingToken);
            vm.assertEq(price, 0);
            vm.assertFalse(isValid);

            // Update Stale Price threshold to longer, to make sure prices are not-stale
            vm.prank(admin);
            api3Oracle.setStalePriceThreshold(API3_STALE_PRICE_THRESHOLD * 2 + 1);
            (price, isValid) = api3Oracle.getPrice(underlyingToken);
            vm.assertGt(price, 0);
            vm.assertTrue(isValid);

            // Update Stale Price threshold to shorter, to make sure prices are stale
            vm.prank(admin);
            api3Oracle.setStalePriceThreshold(API3_STALE_PRICE_THRESHOLD - 1 seconds);
            (price, isValid) = api3Oracle.getPrice(underlyingToken);
            vm.assertEq(price, 0);
            vm.assertFalse(isValid);
        }
    }

    function test_oracleSourceReturnsInvalidPrice() public {
        // Deploy CErc20Delegator with no oracle source
        MockERC20 mockErc20 = new MockERC20(12);
        vm.prank(admin);
        CErc20Delegator cErc20Delegator = new CErc20Delegator(
            address(mockErc20), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            2 * 10 ** (mockErc20.decimals() + 18 - cTokenDecimals - 2), // initialExchangeRateMantissa
            "Compound Mock", // name
            "cMock", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = pythOracle;
        oracles[1] = api3Oracle;

        vm.prank(admin);
        priceOracleAggregator.updateTokenOracles(address(mockErc20), oracles);
        uint256 price = priceOracleAggregator.getUnderlyingPrice(CToken(address(cErc20Delegator)));
        vm.assertEq(price, 0);
    }

    function test_priceOracleAggregator_getUnderlyingPrice_stalePriceFallback() public {
        vm.startPrank(admin);

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = api3Oracle;
        oracles[1] = pythOracle;

        // USDC is stale for API3 on SONIC Testnet (subscription expired), but not for Pyth
        priceOracleAggregator.updateTokenOracles(address(usdc), oracles);

        // Get USDC prices from Pyth & API3
        (uint256 pythUsdcPrice, bool isPythUsdcPriceValid) = pythOracle.getPrice(address(usdc));
        (uint256 api3UsdcPrice, bool isApi3UsdcPriceValid) = api3Oracle.getPrice(address(usdc));

        vm.assertTrue(isPythUsdcPriceValid);
        vm.assertFalse(isApi3UsdcPriceValid);

        // Get USDC price from priceOracleAggregator
        uint256 usdcPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cUsdcDelegator)));
        vm.assertEq(usdcPrice, pythUsdcPrice);
        vm.assertNotEq(usdcPrice, api3UsdcPrice);

        vm.stopPrank();
    }

    function test_priceOracleAggregator_getUnderlyingPrice_enforcePriority() public {
        vm.startPrank(admin);

        IOracleSource[] memory btcOracles = new IOracleSource[](2);
        btcOracles[0] = pythOracle;
        btcOracles[1] = api3Oracle;

        IOracleSource[] memory ftmOracles = new IOracleSource[](2);
        ftmOracles[0] = api3Oracle;
        ftmOracles[1] = pythOracle;

        priceOracleAggregator.updateTokenOracles(address(wbtc), btcOracles);
        priceOracleAggregator.updateTokenOracles(NATIVE_ASSET, ftmOracles);
        vm.stopPrank();

        (uint256 btcPythOraclePrice, bool isBtcPythOraclePriceValid) = pythOracle.getPrice(address(wbtc));
        (uint256 ftmApi3OraclePrice, bool isFtmApi3OraclePriceValid) = api3Oracle.getPrice(NATIVE_ASSET);

        uint256 btcPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cWbtcDelegator)));
        uint256 ftmPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);

        vm.assertEq(btcPrice, btcPythOraclePrice);
        vm.assertEq(ftmPrice, ftmApi3OraclePrice);

        vm.assertTrue(isBtcPythOraclePriceValid);
        vm.assertTrue(isFtmApi3OraclePriceValid);
    }

    function testRevert_priceOracleAggregator_whenOracleUpdatesAreNotCalledByAdmin(address user) public {
        vm.assume(user != admin);

        IOracleSource[] memory btcOracles = new IOracleSource[](2);
        btcOracles[0] = pythOracle;
        btcOracles[1] = api3Oracle;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        priceOracleAggregator.updateTokenOracles(address(wbtc), btcOracles);
    }

    function test_pythOracle_setPriceFeedId() public {
        address newToken = address(new MockERC20(18));
        bytes32 newPriceFeedId = SOLVBTC_PRICE_FEED_ID;

        vm.prank(admin);
        pythOracle.setPriceFeedId(newToken, newPriceFeedId);

        assertEq(pythOracle.priceFeedIds(newToken), newPriceFeedId);
    }

    function test_pythOracle_bulkSetPriceFeedIds() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(8));
        tokens[2] = address(new MockERC20(18));

        bytes32[] memory feedIds = new bytes32[](3);
        feedIds[0] = ETH_PRICE_FEED_ID;
        feedIds[1] = WBTC_PRICE_FEED_ID;
        feedIds[2] = SOLVBTC_PRICE_FEED_ID;

        vm.prank(admin);
        pythOracle.bulkSetPriceFeedIds(tokens, feedIds);

        assertEq(pythOracle.priceFeedIds(tokens[0]), feedIds[0]);
        assertEq(pythOracle.priceFeedIds(tokens[1]), feedIds[1]);
        assertEq(pythOracle.priceFeedIds(tokens[2]), feedIds[2]);
    }

    function test_bandOracle_setUnderlyingSymbol() public {
        address newToken = address(new MockERC20(18));
        string memory newSymbol = "TEST";

        vm.prank(admin);
        bandOracle.setUnderlyingSymbol(newToken, newSymbol);

        assertEq(bandOracle.tokenToBandSymbol(newToken), newSymbol);
    }

    function test_bandOracle_bulkSetUnderlyingSymbols() public {
        address[] memory tokens = new address[](4);
        tokens[0] = address(new MockERC20(6));
        tokens[1] = address(new MockERC20(6));
        tokens[2] = address(new MockERC20(18));
        tokens[3] = address(new MockERC20(8));

        string[] memory symbols = new string[](4);
        symbols[0] = "USDT";
        symbols[1] = "USDC";
        symbols[2] = "ETH";
        symbols[3] = "WBTC";

        vm.prank(admin);
        bandOracle.bulkSetUnderlyingSymbols(tokens, symbols);

        assertEq(bandOracle.tokenToBandSymbol(tokens[0]), symbols[0]);
        assertEq(bandOracle.tokenToBandSymbol(tokens[1]), symbols[1]);
    }

    function test_api3Oracle_setApi3ProxyAddress() public {
        address newToken = address(new MockERC20(18));
        address newApi3Proxy = SONIC_BLAZE_TESTNET_API3_WBTC_PROXY;

        vm.prank(admin);
        api3Oracle.setApi3ProxyAddress(newToken, newApi3Proxy);

        assertEq(api3Oracle.tokenToApi3ProxyAddress(newToken), newApi3Proxy);
    }

    function test_api3Oracle_bulkSetApi3ProxyAddresses() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(8));
        tokens[2] = address(new MockERC20(18));

        address[] memory api3ProxyAddresses = new address[](3);
        api3ProxyAddresses[0] = SONIC_BLAZE_TESTNET_API3_WBTC_PROXY;
        api3ProxyAddresses[1] = SONIC_BLAZE_TESTNET_API3_USDC_PROXY;
        api3ProxyAddresses[2] = SONIC_BLAZE_TESTNET_API3_SOLV_PROXY;

        vm.prank(admin);
        api3Oracle.bulkSetApi3ProxyAddresses(tokens, api3ProxyAddresses);
    }

    function test_pythOracle_setStalePriceThreshold(uint256 newStalePriceThreshold) public {
        vm.assume(newStalePriceThreshold > 0);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit StalePriceThresholdSet(newStalePriceThreshold);
        pythOracle.setStalePriceThreshold(newStalePriceThreshold);
        assertEq(pythOracle.stalePriceThreshold(), newStalePriceThreshold);
    }

    function test_api3Oracle_setStalePriceThreshold(uint256 newStalePriceThreshold) public {
        vm.assume(newStalePriceThreshold > 0);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit StalePriceThresholdSet(newStalePriceThreshold);
        api3Oracle.setStalePriceThreshold(newStalePriceThreshold);
        assertEq(api3Oracle.stalePriceThreshold(), newStalePriceThreshold);
    }

    function testRevert_pythOracle_whenSetInvalidStalePriceThreshold() public {
        vm.prank(admin);
        vm.expectRevert("PythOracle: Stale price threshold must be greater than 0");
        pythOracle.setStalePriceThreshold(0);
    }

    function testRevert_api3Oracle_whenSetInvalidStalePriceThreshold() public {
        vm.prank(admin);
        vm.expectRevert("API3Oracle: Stale price threshold must be greater than 0");
        api3Oracle.setStalePriceThreshold(0);
    }

    function testRevert_pythOracle_whenNonOwnerSetsStalePriceThreshold(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        pythOracle.setStalePriceThreshold(1 days);
    }

    function testRevert_api3Oracle_whenNonOwnerSetsStalePriceThreshold(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        api3Oracle.setStalePriceThreshold(1 days);
    }

    function testRevert_pythOracle_whenNonAdminSetsPriceFeed(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        pythOracle.setPriceFeedId(address(0), bytes32(0));

        // Should also revert when bulk setting price feed ids
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(8));

        bytes32[] memory feedIds = new bytes32[](2);
        feedIds[0] = ETH_PRICE_FEED_ID;
        feedIds[1] = WBTC_PRICE_FEED_ID;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        pythOracle.bulkSetPriceFeedIds(tokens, feedIds);
    }

    function testRevert_bandOracle_whenNonAdminSetsSymbol(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        bandOracle.setUnderlyingSymbol(address(0), "TEST");

        // Should also revert when bulk setting symbols
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20(6));
        tokens[1] = address(new MockERC20(6));

        string[] memory symbols = new string[](2);
        symbols[0] = "USDT";
        symbols[1] = "USDC";

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        bandOracle.bulkSetUnderlyingSymbols(tokens, symbols);
    }

    function testRevert_api3Oracle_whenNonAdminSetsApi3ProxyAddress(address user) public {
        vm.assume(user != admin);

        address newToken = address(new MockERC20(18));
        address newApi3Proxy = SONIC_BLAZE_TESTNET_API3_WBTC_PROXY;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        api3Oracle.setApi3ProxyAddress(newToken, newApi3Proxy);

        // Bulk set API3 proxy addresses
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(8));

        address[] memory api3ProxyAddresses = new address[](2);
        api3ProxyAddresses[0] = SONIC_BLAZE_TESTNET_API3_WBTC_PROXY;
        api3ProxyAddresses[1] = SONIC_BLAZE_TESTNET_API3_USDC_PROXY;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        api3Oracle.bulkSetApi3ProxyAddresses(tokens, api3ProxyAddresses);
    }

    function testRevert_pythOracle_whenSetInvalidPriceFeedId() public {
        address invalidToken = address(new MockERC20(18));

        vm.prank(admin);
        vm.expectRevert();
        pythOracle.setPriceFeedId(invalidToken, bytes32(uint256(1234567890)));

        // Should also revert setting bytes32(0)
        vm.prank(admin);
        vm.expectRevert("PythOracle: Price feed id cannot be zero");
        pythOracle.setPriceFeedId(invalidToken, bytes32(0));
    }

    function testRevert_bandOracle_whenSetInvalidSymbol() public {
        address invalidToken = address(new MockERC20(18));

        vm.prank(admin);
        vm.expectRevert();
        bandOracle.setUnderlyingSymbol(invalidToken, "BOB");

        // Should also revert setting empty string
        vm.prank(admin);
        vm.expectRevert("BandOracle: Symbol cannot be empty");
        bandOracle.setUnderlyingSymbol(invalidToken, "");
    }

    function testRevert_api3Oracle_whenSetInvalidApi3ProxyAddress() public {
        address invalidToken = address(new MockERC20(18));

        vm.prank(admin);
        vm.expectRevert();
        api3Oracle.setApi3ProxyAddress(invalidToken, makeAddr("invalidApi3ProxyAddress"));

        vm.prank(admin);
        vm.expectRevert("API3Oracle: API3 proxy address cannot be zero");
        api3Oracle.setApi3ProxyAddress(address(wbtc), address(0));
    }

    function test_priceOracleAggregator_fallbackToSecondaryOracle() public {
        // Setup scenario where primary oracle fails but secondary succeeds
        address mockToken = address(new MockERC20(18));
        vm.prank(admin);
        CErc20Delegator cToken = new CErc20Delegator(
            mockToken,
            comptroller,
            interestRateModel,
            2 * 10 ** (ERC20(mockToken).decimals() + 18 - cTokenDecimals - 2),
            "Compound ETH",
            "cETH",
            8,
            payable(admin),
            address(cErc20Delegate),
            ""
        );

        // Setup oracles with mock token
        vm.startPrank(admin);
        bandOracle.setUnderlyingSymbol(mockToken, "ETH"); // Valid BAND symbol

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = pythOracle; // Will fail
        oracles[1] = bandOracle; // Should succeed

        priceOracleAggregator.updateTokenOracles(mockToken, oracles);
        vm.stopPrank();

        uint256 ethPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cToken)));
        vm.assertGt(ethPrice, 0);

        (uint256 bandEthPrice, bool isBandEthPriceValid) = bandOracle.getPrice(address(mockToken));
        vm.assertEq(ethPrice, bandEthPrice);
        vm.assertTrue(isBandEthPriceValid);
    }

    function test_priceOracle_emitEvents() public {
        vm.startPrank(admin);
        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = pythOracle;
        oracles[1] = bandOracle;

        vm.expectEmit(true, false, false, true);
        emit TokenOraclesUpdated(address(wbtc), oracles);
        priceOracleAggregator.updateTokenOracles(address(wbtc), oracles);

        vm.expectEmit(true, false, false, true);
        emit UnderlyingTokenPriceFeedSet(address(wbtc), WBTC_PRICE_FEED_ID);
        pythOracle.setPriceFeedId(address(wbtc), WBTC_PRICE_FEED_ID);

        vm.expectEmit(true, false, false, true);
        emit UnderlyingSymbolSet(NATIVE_ASSET, "ETH");
        bandOracle.setUnderlyingSymbol(NATIVE_ASSET, "ETH");

        // Prevent reverting when setting API3 proxy address
        vm.mockCall(
            SONIC_BLAZE_TESTNET_API3_WBTC_PROXY,
            abi.encodeWithSelector(IApi3ReaderProxy.read.selector),
            abi.encode(1e18, block.timestamp)
        );
        vm.expectEmit(true, false, false, true);
        emit UnderlyingTokenApi3ProxyAddressSet(address(wbtc), SONIC_BLAZE_TESTNET_API3_WBTC_PROXY);
        api3Oracle.setApi3ProxyAddress(address(wbtc), SONIC_BLAZE_TESTNET_API3_WBTC_PROXY);

        vm.stopPrank();
    }

    function test_pythOracle_transfer2StepOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(admin);
        pythOracle.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, newOwner));
        pythOracle.setPriceFeedId(address(wbtc), WBTC_PRICE_FEED_ID);

        // Accept ownership
        pythOracle.acceptOwnership();

        // Check that new owner can set price feed id
        vm.expectEmit(true, false, false, true);
        emit UnderlyingTokenPriceFeedSet(address(wbtc), WBTC_PRICE_FEED_ID);
        pythOracle.setPriceFeedId(address(wbtc), WBTC_PRICE_FEED_ID);

        // Check owner
        vm.assertEq(pythOracle.owner(), newOwner);
        vm.stopPrank();
    }

    function test_api3Oracle_transfer2StepOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(admin);
        api3Oracle.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, newOwner));
        api3Oracle.setApi3ProxyAddress(address(wbtc), SONIC_BLAZE_TESTNET_API3_WBTC_PROXY);

        // Accept ownership
        api3Oracle.acceptOwnership();

        // Check that new owner can set API3 proxy address
        vm.expectEmit(true, false, false, true);
        emit UnderlyingTokenApi3ProxyAddressSet(address(wbtc), SONIC_BLAZE_TESTNET_API3_WBTC_PROXY);
        api3Oracle.setApi3ProxyAddress(address(wbtc), SONIC_BLAZE_TESTNET_API3_WBTC_PROXY);

        // Check owner
        vm.assertEq(api3Oracle.owner(), newOwner);
        vm.stopPrank();
    }

    function test_bandOracle_transfer2StepOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(admin);
        bandOracle.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, newOwner));
        bandOracle.setUnderlyingSymbol(address(wbtc), "WBTC");

        // Accept ownership
        bandOracle.acceptOwnership();

        // Check that new owner can set underlying symbol
        vm.expectEmit(true, false, false, true);
        emit UnderlyingSymbolSet(address(wbtc), "WBTC");
        bandOracle.setUnderlyingSymbol(address(wbtc), "WBTC");

        // Check owner
        vm.assertEq(bandOracle.owner(), newOwner);
        vm.stopPrank();
    }

    function test_priceOracleAggregator_upgrade() public {
        address proxy = address(priceOracleAggregator);

        address previousImplementation = Upgrades.getImplementationAddress(proxy);
        address owner = priceOracleAggregator.owner();
        vm.assertEq(owner, admin);

        vm.startPrank(admin);
        Upgrades.upgradeProxy(proxy, "MockPriceOracleAggregatorV2.sol", "", admin);

        address newImplementation = Upgrades.getImplementationAddress(proxy);
        vm.assertNotEq(previousImplementation, newImplementation);

        // Invoke new function
        MockPriceOracleAggregatorV2(proxy).setCounter(10);
        vm.assertEq(MockPriceOracleAggregatorV2(proxy).getCounter(), 10);
        vm.stopPrank();
    }
}
