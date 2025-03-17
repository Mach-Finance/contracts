// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CErc20} from "../src/CErc20.sol";
import {CSonic} from "../src/CSonic.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {OriginSonicAPI3Oracle} from "../src/Oracles/wOS/OriginSonicAPI3Oracle.sol";
import {OriginSonicPythOracle} from "../src/Oracles/wOS/OriginSonicPythOracle.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IError} from "./BaseTest.t.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "forge-std/console.sol";

contract OriginSonicTest is Test, IError {
    address public constant SAFE_MULTISIG_ADDRESS = 0x43410B419191AB7Df9d2e943995699f80898A058;

    Comptroller comptrollerImplementation = Comptroller(0x147A9deA1DA08cFBb3D496A4e34C0D8C3b73Eaf8);
    Unitroller unitroller = Unitroller(payable(0x646F91AbD5Ab94B76d1F9C5D9490A2f6DDf25730));
    Comptroller comptroller = Comptroller(payable(address(unitroller)));

    PriceOracleAggregator priceOracleAggregator = PriceOracleAggregator(0x139Bf94a9cA4a3DB61a7Ce2022F7AECa12cEAa9d);

    address public constant sApi3Proxy = 0x2551A2a96988829D2a55c3b02b88E138023D1cE8;
    address public constant wOS = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    bytes32 public constant S_PRICE_FEED_ID = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    // Deployed tokens
    CSonic public constant cSonic = CSonic(payable(0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6));
    CErc20 public constant cUsdc = CErc20(0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445);
    CErc20 public constant cWeth = CErc20(0x15eF11b942Cc14e582797A61e95D47218808800D);

    CErc20Delegator cUsdcDelegator = CErc20Delegator(payable(address(cUsdc)));
    CErc20Delegator cWethDelegator = CErc20Delegator(payable(address(cWeth)));

    string SONIC_MAINNET_RPC_URL = vm.envString("SONIC_MAINNET_RPC_URL");
    uint256 SONIC_BLOCK_NUMBER = 14066040;
    uint256 sonicMainnetFork;

    // Origin wOS oracles
    OriginSonicAPI3Oracle wOSAPI3Oracle;
    OriginSonicPythOracle wOSPythOracle;
    address public nonAdmin;

    function setUp() public {
        sonicMainnetFork = vm.createSelectFork(SONIC_MAINNET_RPC_URL, SONIC_BLOCK_NUMBER);
        wOSAPI3Oracle = new OriginSonicAPI3Oracle(SAFE_MULTISIG_ADDRESS, sApi3Proxy);
        wOSPythOracle = new OriginSonicPythOracle(SAFE_MULTISIG_ADDRESS, 1 hours);
        nonAdmin = makeAddr("nonAdmin");
    }

    function test_wOSPriceAPI3() public {
        uint256 sonicPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        (uint256 wOSPrice, bool isValid) = wOSAPI3Oracle.getPrice(wOS);
        vm.assertEq(isValid, true);

        // Calculate expected wOS price based on exchange rate
        uint8 wOSDecimals = 18; // Assuming wOS has 18 decimals
        uint256 rate = IERC4626(wOS).previewRedeem(10 ** wOSDecimals);
        uint256 expectedWOSPrice = rate * sonicPrice / 10 ** wOSDecimals;

        // Exchange rate should make 1 $wOS > 1 $SONIC if wOS is a yield-bearing token
        vm.assertGt(wOSPrice, sonicPrice);
        vm.assertApproxEqAbs(wOSPrice, expectedWOSPrice, 1e16);

        console.log("wOSPrice", wOSPrice);
        console.log("sonicPrice", sonicPrice);
    }

    function test_wOSPricePyth() public {
        uint256 sonicPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        (uint256 wOSPrice, bool isValid) = wOSPythOracle.getPrice(wOS);
        vm.assertEq(isValid, true);

        // Calculate expected wOS price based on exchange rate
        uint8 wOSDecimals = 18; // Assuming wOS has 18 decimals
        uint256 rate = IERC4626(wOS).previewRedeem(10 ** wOSDecimals);
        uint256 expectedWOSPrice = rate * sonicPrice / 10 ** wOSDecimals;

        // Exchange rate should make 1 $wOS > 1 $SONIC if wOS is a yield-bearing token
        vm.assertGt(wOSPrice, sonicPrice);
        vm.assertApproxEqAbs(wOSPrice, expectedWOSPrice, 1e16);

        console.log("wOSPythPrice", wOSPrice);
        console.log("sonicPrice", sonicPrice);
    }

    function test_invalidTokenPrice() public {
        address randomToken = makeAddr("randomToken");
        (uint256 price, bool isValid) = wOSAPI3Oracle.getPrice(randomToken);

        vm.assertEq(isValid, false);
        vm.assertEq(price, 0);

        (price, isValid) = wOSPythOracle.getPrice(randomToken);

        vm.assertEq(isValid, false);
        vm.assertEq(price, 0);
    }

    function test_updateStaleThresholdAPI3() public {
        uint256 staleThreshold = 24 hours;

        // Non admin should not be able to update stale threshold
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonAdmin));
        wOSAPI3Oracle.setStalePriceThreshold(staleThreshold);

        // Admin (SAFE_MULTISIG_ADDRESS) should be able to update stale threshold
        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSAPI3Oracle.setStalePriceThreshold(staleThreshold);
        vm.assertEq(wOSAPI3Oracle.stalePriceThreshold(), staleThreshold);

        // Test that price is valid before stale threshold
        (uint256 wOSPrice, bool isValid) = wOSAPI3Oracle.getPrice(wOS);
        vm.assertEq(isValid, true);
        vm.assertGt(wOSPrice, 0);

        // Warp time to trigger stale price
        vm.warp(block.timestamp + staleThreshold + 1);

        (wOSPrice, isValid) = wOSAPI3Oracle.getPrice(wOS);
        vm.assertEq(isValid, false);
        vm.assertEq(wOSPrice, 0);
    }

    function test_updateStaleThresholdPyth() public {
        uint256 staleThreshold = 30 minutes;

        // Non admin should not be able to update stale threshold
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonAdmin));
        wOSPythOracle.setStalePriceThreshold(staleThreshold);

        // Admin (SAFE_MULTISIG_ADDRESS) should be able to update stale threshold
        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSPythOracle.setStalePriceThreshold(staleThreshold);
        vm.assertEq(wOSPythOracle.stalePriceThreshold(), staleThreshold);

        // Test that price is valid before stale threshold
        (uint256 wOSPrice, bool isValid) = wOSPythOracle.getPrice(wOS);
        vm.assertEq(isValid, true);
        vm.assertGt(wOSPrice, 0);

        // Warp time to trigger stale price
        vm.warp(block.timestamp + staleThreshold + 1);

        // For a complete test, you would need to mock the Pyth response
        (wOSPrice, isValid) = wOSPythOracle.getPrice(wOS);
        vm.assertEq(isValid, false);
        vm.assertEq(wOSPrice, 0);
    }

    function test_transferOwnershipAPI3(address newOwner) public {
        vm.assume(newOwner != SAFE_MULTISIG_ADDRESS);
        vm.assume(newOwner != address(0));

        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSAPI3Oracle.transferOwnership(newOwner);

        // Check pending owner
        vm.assertEq(wOSAPI3Oracle.pendingOwner(), newOwner);

        // Pending owner should be able to accept
        vm.prank(newOwner);
        wOSAPI3Oracle.acceptOwnership();

        vm.assertEq(wOSAPI3Oracle.owner(), newOwner);
    }

    function test_transferOwnershipPyth(address newOwner) public {
        vm.assume(newOwner != SAFE_MULTISIG_ADDRESS);
        vm.assume(newOwner != address(0));

        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSPythOracle.transferOwnership(newOwner);

        // Check pending owner
        vm.assertEq(wOSPythOracle.pendingOwner(), newOwner);

        // Pending owner should be able to accept
        vm.prank(newOwner);
        wOSPythOracle.acceptOwnership();

        vm.assertEq(wOSPythOracle.owner(), newOwner);
    }

    function test_setAPI3ProxyAddress() public {
        address newProxyAddress = makeAddr("newProxyAddress");

        // Mock the API3 proxy to not revert on read
        vm.mockCall(
            newProxyAddress, abi.encodeWithSignature("read()"), abi.encode(int224(1e18), uint32(block.timestamp))
        );

        // Non-admin should not be able to update proxy address
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonAdmin));
        wOSAPI3Oracle.setOriginSonicAPI3ProxyAddress(newProxyAddress);

        // Admin should be able to update proxy address
        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSAPI3Oracle.setOriginSonicAPI3ProxyAddress(newProxyAddress);

        // Verify the proxy address was updated
        vm.assertEq(address(wOSAPI3Oracle.sApi3Proxy()), newProxyAddress);
    }

    function test_setPythPriceFeedId() public {
        bytes32 newPriceFeedId = bytes32(uint256(1));

        // Mock the Pyth price feed to not revert on getPriceUnsafe
        PythStructs.Price memory mockPrice = PythStructs.Price({
            price: int64(1e8),
            conf: uint64(0),
            expo: int32(-8),
            publishTime: uint64(block.timestamp)
        });

        vm.mockCall(
            address(0x2880aB155794e7179c9eE2e38200202908C17B43), // pyth address
            abi.encodeWithSignature("getPriceUnsafe(bytes32)", newPriceFeedId),
            abi.encode(mockPrice)
        );

        // Non-admin should not be able to update price feed id
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonAdmin));
        wOSPythOracle.setSonicPriceFeedId(newPriceFeedId);

        // Admin should be able to update price feed id
        vm.prank(SAFE_MULTISIG_ADDRESS);
        wOSPythOracle.setSonicPriceFeedId(newPriceFeedId);

        // Verify the price feed id was updated
        vm.assertEq(wOSPythOracle.sonicPriceFeedId(), newPriceFeedId);
    }

    function test_zeroStaleThresholdRevertsAPI3() public {
        vm.prank(SAFE_MULTISIG_ADDRESS);
        vm.expectRevert("API3Oracle: Stale price threshold must be greater than 0");
        wOSAPI3Oracle.setStalePriceThreshold(0);
    }

    function test_zeroStaleThresholdRevertsPyth() public {
        vm.prank(SAFE_MULTISIG_ADDRESS);
        vm.expectRevert("PythOracle: Stale price threshold must be greater than 0");
        wOSPythOracle.setStalePriceThreshold(0);
    }

    function test_zeroProxyAddressReverts() public {
        vm.prank(SAFE_MULTISIG_ADDRESS);
        vm.expectRevert("API3Oracle: API3 proxy address cannot be zero");
        wOSAPI3Oracle.setOriginSonicAPI3ProxyAddress(address(0));
    }

    function test_zeroPriceFeedIdReverts() public {
        vm.prank(SAFE_MULTISIG_ADDRESS);
        vm.expectRevert("PythOracle: Price feed id cannot be zero");
        wOSPythOracle.setSonicPriceFeedId(bytes32(0));
    }
}
