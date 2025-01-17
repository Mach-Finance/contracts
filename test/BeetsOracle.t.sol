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
import {BeetsStakedSAPI3Oracle} from "../src/Oracles/Beets/BeetsStakedSAPI3Oracle.sol";
import {BeetsStakedSPythOracle} from "../src/Oracles/Beets/BeetsStakedSPythOracle.sol";
import {IstS} from "../src/Oracles/Beets/IstS.sol";

contract BeetsStakedSAPI3OracleTest is Test {
    address public constant SAFE_MULTISIG_ADDRESS = 0x43410B419191AB7Df9d2e943995699f80898A058;

    Comptroller comptrollerImplementation = Comptroller(0x147A9deA1DA08cFBb3D496A4e34C0D8C3b73Eaf8);
    Unitroller unitroller = Unitroller(payable(0x646F91AbD5Ab94B76d1F9C5D9490A2f6DDf25730));
    Comptroller comptroller = Comptroller(payable(address(unitroller)));

    PythOracle pythOracle = PythOracle(0x69625Ca76EA8d3C6Ea9dB5Df7c49250ed14Bf03f);
    API3Oracle api3Oracle = API3Oracle(0xD458d8CA6e52E4D8E6938B6720bf7d9E1A42d175);
    PriceOracleAggregator priceOracleAggregator = PriceOracleAggregator(0x139Bf94a9cA4a3DB61a7Ce2022F7AECa12cEAa9d);

    // @notice - Deployer address
    address public constant admin = 0x9A74A959Ab5F706c1DFf414F580560287FcB7576;
    address public constant sApi3Proxy = 0x2551A2a96988829D2a55c3b02b88E138023D1cE8;
    bytes32 public constant sPriceFeedId = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    // Deployed tokens
    CSonic public constant cSonic = CSonic(payable(0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6));
    CErc20 public constant cUsdc = CErc20(0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445);
    CErc20 public constant cWeth = CErc20(0x15eF11b942Cc14e582797A61e95D47218808800D);

    CErc20Delegator cUsdcDelegator = CErc20Delegator(payable(address(cUsdc)));
    CErc20Delegator cWethDelegator = CErc20Delegator(payable(address(cWeth)));

    string SONIC_MAINNET_RPC_URL = vm.envString("SONIC_MAINNET_RPC_URL");
    uint256 SONIC_BLOCK_NUMBER = 4290090;
    uint256 sonicMainnetFork;

    // Beets stS oracle
    BeetsStakedSAPI3Oracle stSAPI3Oracle;
    BeetsStakedSPythOracle stSPythOracle;
    address public constant stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    function setUp() public {
        sonicMainnetFork = vm.createSelectFork(SONIC_MAINNET_RPC_URL, SONIC_BLOCK_NUMBER);
        stSAPI3Oracle = new BeetsStakedSAPI3Oracle(SAFE_MULTISIG_ADDRESS, sApi3Proxy);
        stSPythOracle = new BeetsStakedSPythOracle(SAFE_MULTISIG_ADDRESS, 1 hours);
    }

    function test_stSPriceAPI3() public {
        uint256 sPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        (uint256 stSPrice, bool isValid) = stSAPI3Oracle.getPrice(address(stS));
        vm.assertEq(isValid, true);

        uint256 expectedStSPrice = IstS(stS).getRate() * sPrice / 1e18;

        // Exchange rate 1 $stS > 1 $S
        vm.assertGt(stSPrice, sPrice);
        vm.assertApproxEqAbs(stSPrice, expectedStSPrice, 1e16);
    }

    function test_stSPricePyth() public {
        uint256 sPrice = priceOracleAggregator.getUnderlyingPrice(cSonic);
        (uint256 stSPrice, bool isValid) = stSAPI3Oracle.getPrice(address(stS));
        vm.assertEq(isValid, true);

        uint256 expectedStSPrice = IstS(stS).getRate() * sPrice / 1e18;
        vm.assertApproxEqAbs(stSPrice, expectedStSPrice, 1e16);

        // Exchange rate 1 $stS > 1 $S
        vm.assertGt(stSPrice, sPrice);
    }
}
