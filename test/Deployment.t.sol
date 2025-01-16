// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CErc20} from "../src/CErc20.sol";
import {CSonic} from "../src/CSonic.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {PythOracle} from "../src/Oracles/Pyth/PythOracle.sol";
import {API3Oracle} from "../src/Oracles/API3/API3Oracle.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {IOracleSource} from "../src/Oracles/IOracleSource.sol";
import {console} from "forge-std/console.sol";

contract DeploymentTest is Test {
    address public constant SAFE_MULTISIG_ADDRESS = 0x43410B419191AB7Df9d2e943995699f80898A058;

    Comptroller comptrollerImplementation = Comptroller(0x147A9deA1DA08cFBb3D496A4e34C0D8C3b73Eaf8);
    Unitroller unitroller = Unitroller(payable(0x646F91AbD5Ab94B76d1F9C5D9490A2f6DDf25730));
    Comptroller comptroller = Comptroller(payable(address(unitroller)));

    PythOracle pythOracle = PythOracle(0x69625Ca76EA8d3C6Ea9dB5Df7c49250ed14Bf03f);
    API3Oracle api3Oracle = API3Oracle(0xD458d8CA6e52E4D8E6938B6720bf7d9E1A42d175);
    PriceOracleAggregator priceOracleAggregator = PriceOracleAggregator(0x139Bf94a9cA4a3DB61a7Ce2022F7AECa12cEAa9d);

    // @notice - Deployer address
    address public constant admin = 0x9A74A959Ab5F706c1DFf414F580560287FcB7576;
    address public constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Pyth price feed ids
    bytes32 constant FTM_PRICE_FEED_ID = 0x5c6c0d2386e3352356c3ab84434fafb5ea067ac2678a38a338c4a69ddc4bdb0c;
    bytes32 constant S_PRICE_FEED_ID = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    // API3 addresses
    address constant FTM_API3_PROXY_ADDRESS = 0x41Efded5ec14C2783a42dA9e8c7970aC313d5576;
    address constant S_API3_PROXY_ADDRESS = 0x726D2E87d73567ecA1b75C063Bd09c1493655918;
    address constant NEW_S_API3_PROXY_ADDRESS = 0x2551A2a96988829D2a55c3b02b88E138023D1cE8;

    // Deployed tokens
    CSonic public constant cSonic = CSonic(payable(0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6));
    CErc20 public constant cUsdc = CErc20(0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445);
    CErc20 public constant cWeth = CErc20(0x15eF11b942Cc14e582797A61e95D47218808800D);

    CErc20Delegator cUsdcDelegator = CErc20Delegator(payable(address(cUsdc)));
    CErc20Delegator cWethDelegator = CErc20Delegator(payable(address(cWeth)));

    string SONIC_MAINNET_RPC_URL = vm.envString("SONIC_MAINNET_RPC_URL");
    uint256 sonicMainnetFork;

    function setUp() public {
        sonicMainnetFork = vm.createSelectFork(SONIC_MAINNET_RPC_URL);
    }

    // These steps are to be used for simulation, before broadcasting them to the chain
    function test_setSafeAsAdmin() public {
        vm.prank(admin);
        unitroller._setPendingAdmin(payable(SAFE_MULTISIG_ADDRESS));
        vm.prank(SAFE_MULTISIG_ADDRESS);
        unitroller._acceptAdmin();

        // Check admin is set
        assertEq(unitroller.admin(), SAFE_MULTISIG_ADDRESS);

        // Old admin address should fail
        vm.startPrank(admin);
        require(comptroller._setCollateralFactor(cSonic, 0.3e18) == 1, "Old admin should fail");
        vm.stopPrank();

        // Try admin only functions for comptroller
        vm.startPrank(SAFE_MULTISIG_ADDRESS);
        require(comptroller._setCollateralFactor(cSonic, 0.3e18) == 0, "Failed to set collateral factor");
        require(comptroller._setCollateralFactor(cUsdc, 0.4e18) == 0, "Failed to set collateral factor");
        require(comptroller._setCollateralFactor(cWeth, 0.5e18) == 0, "Failed to set collateral factor");

        (, uint256 cSonicCollateralFactorMantissa) = comptroller.markets(address(cSonic));
        (, uint256 cUsdcCollateralFactorMantissa) = comptroller.markets(address(cUsdc));
        (, uint256 cWethCollateralFactorMantissa) = comptroller.markets(address(cWeth));

        assertEq(cSonicCollateralFactorMantissa, 0.3e18);
        assertEq(cUsdcCollateralFactorMantissa, 0.4e18);
        assertEq(cWethCollateralFactorMantissa, 0.5e18);
        vm.stopPrank();
    }

    function test_updateCSonicOracle() public {
        vm.startPrank(SAFE_MULTISIG_ADDRESS);

        // Check "getUnderlyingPrice" for $Sonic
        uint256 ftmPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        console.log("FTM price", ftmPrice);

        // Check previous price feed
        require(pythOracle.priceFeedIds(NATIVE_ASSET) == FTM_PRICE_FEED_ID, "Previous price feed is not FTM");

        // Update Pyth Oracle to support $S
        pythOracle.setPriceFeedId(NATIVE_ASSET, S_PRICE_FEED_ID);
        require(pythOracle.priceFeedIds(NATIVE_ASSET) == S_PRICE_FEED_ID, "New price feed is not S");

        // Check previous API3 price feed
        require(
            api3Oracle.tokenToApi3ProxyAddress(NATIVE_ASSET) == FTM_API3_PROXY_ADDRESS, "Previous price feed is not FTM"
        );
        // Update API3 Oracle to support $S
        api3Oracle.setApi3ProxyAddress(NATIVE_ASSET, S_API3_PROXY_ADDRESS);
        require(api3Oracle.tokenToApi3ProxyAddress(NATIVE_ASSET) == S_API3_PROXY_ADDRESS, "New price feed is not S");

        // Get underlying price
        uint256 sonicPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        console.log("Sonic price", sonicPrice);

        // Get price from Pyth and API3
        (uint256 pythPrice,) = pythOracle.getPrice(NATIVE_ASSET);
        (uint256 api3Price,) = api3Oracle.getPrice(NATIVE_ASSET);
        console.log("Sonic price (PYTH)", pythPrice);
        console.log("Sonic price (API3)", api3Price);

        require(sonicPrice > 0, "Sonic price is 0");
        require(sonicPrice != ftmPrice, "Sonic price is the same as FTM price");
        vm.stopPrank();
    }

    function test_updateCSonicApi3Feed() public {
        vm.startPrank(SAFE_MULTISIG_ADDRESS);

        require(api3Oracle.tokenToApi3ProxyAddress(NATIVE_ASSET) == S_API3_PROXY_ADDRESS, "Previous price feed is $S");
        // Update API3 Oracle to support OeV $S
        api3Oracle.setApi3ProxyAddress(NATIVE_ASSET, NEW_S_API3_PROXY_ADDRESS);
        require(
            api3Oracle.tokenToApi3ProxyAddress(NATIVE_ASSET) == NEW_S_API3_PROXY_ADDRESS, "New price feed is not $S"
        );

        // Get underlying price
        uint256 sonicPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        console.log("Sonic price", sonicPrice);

        // Get price from Pyth and API3
        (uint256 pythPrice,) = pythOracle.getPrice(NATIVE_ASSET);
        (uint256 api3Price,) = api3Oracle.getPrice(NATIVE_ASSET);
        console.log("Sonic price (PYTH)", pythPrice);
        console.log("Sonic price (API3)", api3Price);

        require(sonicPrice > 0, "Sonic price is 0");
        require(pythPrice > 0, "Pyth price is 0");
        require(api3Price > 0, "API3 price is 0");
        vm.stopPrank();
    }
}
