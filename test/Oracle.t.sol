// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {BaseTest} from "./BaseTest.t.sol";
import {PythOracle} from "../src/Oracles/PythOracle.sol";
import {CToken} from "../src/CToken.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {BandOracle} from "../src/Oracles/BandOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {IOracleSource} from "../src/Oracles/IOracleSource.sol";

import "forge-std/console.sol";

contract OracleTest is BaseTest {
    address constant SONIC_TESTNET_PYTH_ORACLE = 0x96124d1F6E44FfDf1fb5D6d74BB2DE1B7Fbe7376;
    address constant SONIC_TESTNET_BAND_ORACLE = 0x1744a64d95059e5281Ee573BF1C26813811d9BD3;

    address constant FTM_MAINNET_PYTH_ORACLE = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
    address constant FTM_MAINNET_BAND_ORACLE = 0xDA7a001b254CD22e46d3eAB04d937489c93174C3;

    uint256 constant SONIC_TESTNET_CHAIN_ID = 64165;
    uint256 constant FTM_MAINNET_CHAIN_ID = 250;

    uint256 constant SONIC_TESTNET_BLOCK_NUMBER = 10000000;
    uint256 constant FTM_MAINNET_BLOCK_NUMBER = 10000000;

    bytes32 constant FTM_PRICE_FEED_ID = 0x5c6c0d2386e3352356c3ab84434fafb5ea067ac2678a38a338c4a69ddc4bdb0c;
    bytes32 constant BTC_PRICE_FEED_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    bytes32 constant USDC_PRICE_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // https://scan.soniclabs.com/
    uint256 constant SONIC_TESTNET_FORK_BLOCK_NUMBER = 89140765;
    // https://ftmscan.com/
    uint256 constant FTM_MAINNET_FORK_BLOCK_NUMBER = 98722004;

    string SONIC_TESTNET_RPC_URL = vm.envString("SONIC_TESTNET_RPC_URL");
    string FTM_MAINNET_RPC_URL = vm.envString("FTM_MAINNET_RPC_URL");

    /// Dynamic variables
    address pythOracleAddress;
    address bandOracleAddress;
    uint256 sonicTestnetFork;
    uint256 ftmMainnetFork;

    PythOracle public pythOracle;
    BandOracle public bandOracle;
    PriceOracleAggregator public priceOracleAggregator;

    bool isSonicTestnet = false;

    function setUp() public {
        sonicTestnetFork = vm.createFork(SONIC_TESTNET_RPC_URL, SONIC_TESTNET_FORK_BLOCK_NUMBER);
        ftmMainnetFork = vm.createFork(FTM_MAINNET_RPC_URL, FTM_MAINNET_FORK_BLOCK_NUMBER);

        if (isSonicTestnet) {
            vm.selectFork(sonicTestnetFork);
            pythOracleAddress = SONIC_TESTNET_PYTH_ORACLE;
            bandOracleAddress = SONIC_TESTNET_BAND_ORACLE;
        } else {
            vm.selectFork(ftmMainnetFork);
            pythOracleAddress = FTM_MAINNET_PYTH_ORACLE;
            bandOracleAddress = FTM_MAINNET_BAND_ORACLE;
        }

        _deployBaselineContracts();
        _deployPythOracle();
        _deployBandOracle();
        _deployPriceOracleAggregator();
    }

    function _deployPythOracle() internal {
        vm.startPrank(admin);
        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = address(underlyingErc20Token);
        underlyingTokens[1] = NATIVE_ASSET;

        bytes32[] memory priceFeedIds = new bytes32[](2);
        priceFeedIds[0] = BTC_PRICE_FEED_ID;
        priceFeedIds[1] = FTM_PRICE_FEED_ID;

        pythOracle = new PythOracle(pythOracleAddress, underlyingTokens, priceFeedIds);
        vm.stopPrank();
    }

    function _deployBandOracle() internal {
        vm.startPrank(admin);
        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = address(underlyingErc20Token);
        underlyingTokens[1] = NATIVE_ASSET;

        string[] memory bandSymbols = new string[](2);
        bandSymbols[0] = "BTC";
        bandSymbols[1] = "FTM";

        bandOracle = new BandOracle(bandOracleAddress, underlyingTokens, bandSymbols);
        vm.stopPrank();
    }

    function _deployPriceOracleAggregator() internal {
        vm.startPrank(admin);
        priceOracleAggregator = new PriceOracleAggregator();

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = pythOracle;
        oracles[1] = bandOracle;

        priceOracleAggregator.updateTokenOracles(address(underlyingErc20Token), oracles);
        priceOracleAggregator.updateTokenOracles(NATIVE_ASSET, oracles);
        vm.stopPrank();
    }

    function test_pythOracle_getUnderlyingPrice() public {
        // BTC hovers around 10k - 100k
        // BTC decimals = 8
        // adjustedPrice = (price * 10^(decimals - exponent)) * 10^(36 - decimals) = price * 10^28
        // A 33-digit number would be between 10^32 and 10^33
        (uint256 btcPrice, bool isBtcPriceValid) = pythOracle.getPrice(address(underlyingErc20Token));
        vm.assertGt(btcPrice, 1e32);
        vm.assertLt(btcPrice, 1e33);
        vm.assertTrue(isBtcPriceValid);
        console.log("btcPrice", btcPrice);

        // FTM hovers around 1 - 10
        // FTM decimals = 18
        // adjustedPrice = (price * 10^(exponent)) * 10^(36 - decimals - exponent) = price * 10^18
        // A 18-digit number would be between 10^19 and 10^20
        (uint256 ftmPrice, bool isFtmPriceValid) = pythOracle.getPrice(NATIVE_ASSET);
        vm.assertGt(ftmPrice, 1e18);
        vm.assertLt(ftmPrice, 1e19);
        vm.assertTrue(isFtmPriceValid);

        console.log("ftmPrice", ftmPrice);
    }

    function test_bandOracle_getUnderlyingPrice() public {
        vm.skip(isSonicTestnet);

        (uint256 btcPrice, bool isBtcPriceValid) = bandOracle.getPrice(address(underlyingErc20Token));
        vm.assertGt(btcPrice, 1e32);
        vm.assertLt(btcPrice, 1e33);
        vm.assertTrue(isBtcPriceValid);
        console.log("btcPrice", btcPrice);

        (uint256 ftmPrice, bool isFtmPriceValid) = bandOracle.getPrice(NATIVE_ASSET);
        vm.assertGt(ftmPrice, 1e18);
        vm.assertLt(ftmPrice, 1e19);
        vm.assertTrue(isFtmPriceValid);
        console.log("ftmPrice", ftmPrice);
    }

    function testFuzz_pythOracle_getUnderlyingPrice_withDifferingDecimals(uint8 decimals) public {
        // Only test with valid decimal values (max 36)
        vm.assume(decimals <= 36);

        // Create mock USDC token with varying decimals
        ERC20 usdc = new MockERC20(decimals);

        // Set price feed ID for the mock USDC token
        vm.prank(admin);
        pythOracle.setPriceFeedId(address(usdc), USDC_PRICE_FEED_ID);

        // Get price from oracle and verify it's in expected range
        // USDC should be ~$1, scaled to 36-decimals precision
        (uint256 price, bool isValid) = pythOracle.getPrice(address(usdc));
        vm.assertGe(price, 10 ** (36 - decimals));
        vm.assertLt(price, 10 ** (36 - decimals + 1));
        vm.assertTrue(isValid);
        console.log("price", price);
    }

    function test_priceOracleAggregator_getUnderlyingPrice() public {
        // Check underlyingPrice for BTC
        uint256 btcPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cWbtcDelegator)));
        vm.assertGt(btcPrice, 1e32);
        vm.assertLt(btcPrice, 1e33);

        // Check underlyingPrice for FTM
        uint256 ftmPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        vm.assertGt(ftmPrice, 1e18);
        vm.assertLt(ftmPrice, 1e19);
    }

    function test_whenNoOracleSourceFoundForToken() public {
        // Deploy CErc20Delegator with no oracle source
        MockERC20 mockErc20 = new MockERC20(12);
        vm.prank(admin);
        CErc20Delegator cErc20Delegator = new CErc20Delegator(
            address(mockErc20), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            1e18, // initialExchangeRateMantissa
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

    function test_oracleSourceReturnsInvalidPrice() public {
        // Deploy CErc20Delegator with no oracle source
        MockERC20 mockErc20 = new MockERC20(12);
        vm.prank(admin);
        CErc20Delegator cErc20Delegator = new CErc20Delegator(
            address(mockErc20), // underlying
            comptroller, // comptroller
            interestRateModel, // interestRateModel
            1e18, // initialExchangeRateMantissa
            "Compound Mock", // name
            "cMock", // symbol
            8, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = pythOracle;
        oracles[1] = bandOracle;

        vm.prank(admin);
        priceOracleAggregator.updateTokenOracles(address(mockErc20), oracles);
        uint256 price = priceOracleAggregator.getUnderlyingPrice(CToken(address(cErc20Delegator)));
        vm.assertEq(price, 0);
    }

    function test_priceOracleAggregator_getUnderlyingPrice_enforcePriority() public {
        vm.startPrank(admin);

        IOracleSource[] memory btcOracles = new IOracleSource[](2);
        btcOracles[0] = pythOracle;
        btcOracles[1] = bandOracle;

        IOracleSource[] memory ftmOracles = new IOracleSource[](2);
        ftmOracles[0] = bandOracle;
        ftmOracles[1] = pythOracle;

        priceOracleAggregator.updateTokenOracles(address(underlyingErc20Token), btcOracles);
        priceOracleAggregator.updateTokenOracles(NATIVE_ASSET, ftmOracles);
        vm.stopPrank();

        (uint256 btcPythOraclePrice, bool isBtcPythOraclePriceValid) =
            pythOracle.getPrice(address(underlyingErc20Token));
        (uint256 ftmBandOraclePrice, bool isFtmBandOraclePriceValid) = bandOracle.getPrice(NATIVE_ASSET);

        uint256 btcPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(cWbtcDelegator)));
        uint256 ftmPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);

        vm.assertEq(btcPrice, btcPythOraclePrice);
        vm.assertEq(ftmPrice, ftmBandOraclePrice);

        vm.assertTrue(isBtcPythOraclePriceValid);
        vm.assertTrue(isFtmBandOraclePriceValid);
    }

    function testRevert_priceOracleAggregator_whenOracleUpdatesAreNotCalledByAdmin(address user) public {
        vm.assume(user != admin);

        IOracleSource[] memory btcOracles = new IOracleSource[](2);
        btcOracles[0] = pythOracle;
        btcOracles[1] = bandOracle;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        priceOracleAggregator.updateTokenOracles(address(underlyingErc20Token), btcOracles);
    }

    function test_pythOracle_setPriceFeedId() public {
        address newToken = address(new MockERC20(18));
        bytes32 newPriceFeedId = bytes32(uint256(1));

        vm.prank(admin);
        pythOracle.setPriceFeedId(newToken, newPriceFeedId);

        assertEq(pythOracle.priceFeedIds(newToken), newPriceFeedId);
    }

    function test_pythOracle_bulkSetPriceFeedIds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(18));

        bytes32[] memory feedIds = new bytes32[](2);
        feedIds[0] = bytes32(uint256(1));
        feedIds[1] = bytes32(uint256(2));

        vm.prank(admin);
        pythOracle.bulkSetPriceFeedIds(tokens, feedIds);

        assertEq(pythOracle.priceFeedIds(tokens[0]), feedIds[0]);
        assertEq(pythOracle.priceFeedIds(tokens[1]), feedIds[1]);
    }

    function test_bandOracle_setUnderlyingSymbol() public {
        address newToken = address(new MockERC20(18));
        string memory newSymbol = "TEST";

        vm.prank(admin);
        bandOracle.setUnderlyingSymbol(newToken, newSymbol);

        assertEq(bandOracle.tokenToBandSymbol(newToken), newSymbol);
    }

    function test_bandOracle_bulkSetUnderlyingSymbols() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(new MockERC20(18));
        tokens[1] = address(new MockERC20(18));

        string[] memory symbols = new string[](2);
        symbols[0] = "TEST1";
        symbols[1] = "TEST2";

        vm.prank(admin);
        bandOracle.bulkSetUnderlyingSymbols(tokens, symbols);

        assertEq(bandOracle.tokenToBandSymbol(tokens[0]), symbols[0]);
        assertEq(bandOracle.tokenToBandSymbol(tokens[1]), symbols[1]);
    }

    function testRevert_pythOracle_whenNonAdminSetsPriceFeed(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        pythOracle.setPriceFeedId(address(0), bytes32(0));
    }

    function testRevert_bandOracle_whenNonAdminSetsSymbol(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user));
        bandOracle.setUnderlyingSymbol(address(0), "TEST");
    }

    function test_priceOracleAggregator_fallbackLogic() public {
        // Setup scenario where primary oracle fails but secondary succeeds
        address mockToken = address(new MockERC20(18));
        vm.prank(admin);
        CErc20Delegator cToken = new CErc20Delegator(
            mockToken,
            comptroller,
            interestRateModel,
            1e18,
            "Compound ETH",
            "cETH",
            8,
            payable(admin),
            address(cErc20Delegate),
            ""
        );

        // Setup oracles with mock token
        vm.startPrank(admin);
        pythOracle.setPriceFeedId(mockToken, bytes32(0)); // Invalid feed ID
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
        emit TokenOraclesUpdated(address(underlyingErc20Token), oracles);
        priceOracleAggregator.updateTokenOracles(address(underlyingErc20Token), oracles);

        vm.expectEmit(true, false, false, true);
        emit UnderlyingTokenPriceFeedSet(address(underlyingErc20Token), bytes32(uint256(10)));
        pythOracle.setPriceFeedId(address(underlyingErc20Token), bytes32(uint256(10)));

        vm.expectEmit(true, false, false, true);
        emit UnderlyingSymbolSet(NATIVE_ASSET, "ETH");
        bandOracle.setUnderlyingSymbol(NATIVE_ASSET, "ETH");

        vm.stopPrank();
    }
}
