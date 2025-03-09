// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CErc20Delegate} from "../src/CErc20Delegate.sol";
import {CErc20} from "../src/CErc20.sol";
import {CSonic} from "../src/CSonic.sol";
import {CToken} from "../src/CToken.sol";
import {ComptrollerInterface} from "../src/ComptrollerInterface.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {JumpRateModelV2} from "../src/JumpRateModelV2.sol";
import {IOracleSource} from "../src/Oracles/IOracleSource.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PythOracle} from "../src/Oracles/Pyth/PythOracle.sol";
import {API3Oracle} from "../src/Oracles/API3/API3Oracle.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {Maximillion} from "../src/Maximillion.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {ComptrollerV1Storage} from "../src/ComptrollerStorage.sol";

import {console} from "forge-std/console.sol";

import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {BeetsStakedSAPI3Oracle} from "../src/Oracles/Beets/BeetsStakedSAPI3Oracle.sol";
import {BeetsStakedSPythOracle} from "../src/Oracles/Beets/BeetsStakedSPythOracle.sol";

struct TokenDeploymentConfig {
    uint256 underlyingAmountToBurn;
    uint256 reserveFactorMantissa;
    uint256 protocolSeizeShareMantissa;
    bytes32 pythPriceFeedId;
    address api3ProxyAddress;
    InterestRateModel interestRateModel;
}

struct UnderlyingTokenDeploymentConfig {
    address underlyingToken;
    // cToken name
    string name;
    // cToken symbol
    string symbol;
    // underlying token decimals
    uint8 tokenDecimals;
}

contract DeploymentScript is Script {
    address public constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant PYTH_ORACLE_ADDRESS = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    bytes32 constant FTM_PRICE_FEED_ID = 0x5c6c0d2386e3352356c3ab84434fafb5ea067ac2678a38a338c4a69ddc4bdb0c;
    bytes32 constant WBTC_PRICE_FEED_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    bytes32 constant USDC_PRICE_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant SOLV_PRICE_FEED_ID = 0xf253cf87dc7d5ed5aa14cba5a6e79aee8bcfaef885a0e1b807035a0bbecc36fa;
    bytes32 constant ETH_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant SCETH_PRICE_FEED_ID = 0x8bb5e69ed1ab19642a0e7e851b1ed7b3579d0548bc8ddd1077b0d9476bb1dabc;
    bytes32 constant S_PRICE_FEED_ID = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    address public constant API3_USDC_PROXY = 0x6427406aAED75920aEB0419E361ef5cd6Eff509f;
    address public constant API3_ETH_PROXY = 0xaA5fbCdBa698DFc2f5F2268bCB01012262D7692D;
    address public constant API3_WBTC_PROXY = 0xcc897BD298FDc90c298e7509818a4d9f4F8ca0D1;
    address public constant API3_SOLVBTC_PROXY = 0x867A57D7bf23D464c5CE9B31af097F2E7a75d078;
    address public constant API3_FTM_PROXY = 0x41Efded5ec14C2783a42dA9e8c7970aC313d5576;
    address public constant API3_S_PROXY = 0x2551A2a96988829D2a55c3b02b88E138023D1cE8;

    address public constant USDC_ADDRESS = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant WETH_ADDRESS = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address public constant ST_S_ADDRESS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address public constant SOLV_BTC_ADDRESS = 0x541FD749419CA806a8bc7da8ac23D346f2dF8B77;
    address public constant SCUSD_ADDRESS = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address public constant SCBTC_ADDRESS = 0xBb30e76d9Bb2CC9631F7fC5Eb8e87B5Aff32bFbd;
    address public constant SCETH_ADDRESS = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;
    // TODO: Update this to the actual WBTC address
    address public constant WBTC_ADDRESS = address(123);

    address public constant SAFE_MULTISIG_ADDRESS = 0x43410B419191AB7Df9d2e943995699f80898A058;

    // Look at Euler for best practice
    // https://github.com/euler-xyz/euler-price-oracle/blob/master/src/adapter/pyth/PythOracle.sol
    uint256 public constant PYTH_STALENESS_PERIOD = 1 hours;

    uint256 constant NO_ERROR = 0;

    // Decimal places
    uint8 constant CTOKEN_DECIMALS = 8;
    uint8 constant SONIC_DECIMALS = 18;
    uint8 constant USDC_DECIMALS = 6;
    uint8 constant WETH_DECIMALS = 18;
    uint8 constant SOLV_BTC_DECIMALS = 18;
    uint8 constant SCUSD_DECIMALS = 6;
    uint8 constant SCBTC_DECIMALS = 8;
    uint8 constant SCETH_DECIMALS = 18;

    Comptroller comptrollerImplementation = Comptroller(0x147A9deA1DA08cFBb3D496A4e34C0D8C3b73Eaf8);
    Unitroller unitroller = Unitroller(payable(0x646F91AbD5Ab94B76d1F9C5D9490A2f6DDf25730));
    Comptroller comptroller = Comptroller(payable(address(unitroller)));

    PythOracle pythOracle = PythOracle(0x69625Ca76EA8d3C6Ea9dB5Df7c49250ed14Bf03f);
    API3Oracle api3Oracle = API3Oracle(0xD458d8CA6e52E4D8E6938B6720bf7d9E1A42d175);
    PriceOracleAggregator priceOracleAggregator = PriceOracleAggregator(0x139Bf94a9cA4a3DB61a7Ce2022F7AECa12cEAa9d);

    // @notice - Deployer address
    address public constant admin = 0x9A74A959Ab5F706c1DFf414F580560287FcB7576;

    // Deployed tokens
    CSonic public constant cSonic = CSonic(payable(0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6));
    CErc20 public constant cUsdc = CErc20(0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445);
    CErc20 public constant cWeth = CErc20(0x15eF11b942Cc14e582797A61e95D47218808800D);
    CErc20 public constant cStS = CErc20(0xbAA06b4D6f45ac93B6c53962Ea861e6e3052DC74);
    CErc20 public constant cscUsd = CErc20(0xe5A79Db6623BCA3C65337dd6695Ae6b1f53Bec45);
    CErc20 public constant cScEth = CErc20(0x08A1821Fbb570359d458fa1e6740a1e677Aa45B8);

    function run() public {
        vm.startBroadcast();

        // // Deploy comptroller
        // (Comptroller comptrollerImplementation, Unitroller unitroller) = deployComptroller();

        // Comptroller comptroller = Comptroller(payable(address(unitroller)));

        // // Deploy price oracle
        // (PythOracle pythOracle, API3Oracle api3Oracle, PriceOracleAggregator priceOracleAggregator) =
        //     deployPriceOracle(admin, PYTH_ORACLE_ADDRESS, PYTH_STALENESS_PERIOD);

        // // Set price oracle
        // require(comptroller._setPriceOracle(priceOracleAggregator) == NO_ERROR, "Failed to set price oracle");

        // JumpRateModelV2 sonicInterestRateModel;
        // {
        //     // $S Interest rate model & parameters
        //     uint256 baseRatePerYearSonic = 0;
        //     uint256 multiplierPerYearSonic = 0.05e18;
        //     uint256 jumpMultiplierPerYearSonic = 6e18;
        //     uint256 kinkSonic = 0.6e18;

        //     sonicInterestRateModel = new JumpRateModelV2(
        //         baseRatePerYearSonic, multiplierPerYearSonic, jumpMultiplierPerYearSonic, kinkSonic, admin
        //     );
        // }

        // {
        //     // Custom to $S
        //     uint256 reserveFactorMantissaSonic = 0.3e18;
        //     uint256 protocolSeizeShareMantissaSonic = 0.028e18;

        //     TokenDeploymentConfig memory sonicTokenDeploymentConfig = TokenDeploymentConfig(
        //         15 * 10 ** SONIC_DECIMALS, // 15 $S ~ $10
        //         reserveFactorMantissaSonic,
        //         protocolSeizeShareMantissaSonic,
        //         FTM_PRICE_FEED_ID,
        //         API3_FTM_PROXY,
        //         sonicInterestRateModel
        //     );

        //     // Deploy Sonic
        //     (CSonic sonic, Maximillion maximillion) =
        //         deployCSonic(sonicTokenDeploymentConfig, comptroller, pythOracle, api3Oracle, priceOracleAggregator);

        //     // Set supply caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(sonic));
        //         uint256[] memory supplyCaps = new uint256[](1);
        //         supplyCaps[0] = 12500 * 10 ** SONIC_DECIMALS;
        //         comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
        //         console.log("supplyCaps", comptroller.supplyCaps(address(sonic)));
        //     }

        //     // Set borrow caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(sonic));
        //         uint256[] memory borrowCaps = new uint256[](1);
        //         borrowCaps[0] = 8500 * 10 ** SONIC_DECIMALS;
        //         comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
        //         console.log("borrowCaps", comptroller.borrowCaps(address(sonic)));
        //     }
        // }

        // JumpRateModelV2 usdcInterestRateModel;

        // {
        //     // $USDC Interest rate model & parameters
        //     uint256 baseRatePerYearUSDC = 0;
        //     uint256 multiplierPerYearUSDC = 0.052e18;
        //     uint256 jumpMultiplierPerYearUSDC = 9e18;
        //     uint256 kinkUSDC = 0.85e18;

        //     usdcInterestRateModel = new JumpRateModelV2(
        //         baseRatePerYearUSDC, multiplierPerYearUSDC, jumpMultiplierPerYearUSDC, kinkUSDC, admin
        //     );
        // }

        // // Custom to $USDC
        // uint256 reserveFactorMantissaUSDC = 0.15e18;
        // uint256 protocolSeizeShareMantissaUSDC = 0.028e18;
        // uint8 usdcDecimals = 6;

        // TokenDeploymentConfig memory cUsdcTokenDeploymentConfig = TokenDeploymentConfig(
        //     10 * 10 ** usdcDecimals, // $20 worth of USDC
        //     reserveFactorMantissaUSDC,
        //     protocolSeizeShareMantissaUSDC,
        //     USDC_PRICE_FEED_ID,
        //     API3_USDC_PROXY,
        //     usdcInterestRateModel
        // );

        // UnderlyingTokenDeploymentConfig memory underlyingUsdcTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(USDC_ADDRESS, "Mach USDC", "cUSDC", usdcDecimals);

        // {

        //     // Deploy USDC
        //     CErc20Delegator newCtoken = deployNewCErc20Token(
        //         underlyingTokenDeploymentConfig,
        //         sonicTokenDeploymentConfig,
        //         usdcInterestRateModel
        //     );

        //     // Set supply caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(newCtoken));
        //         uint256[] memory supplyCaps = new uint256[](1);
        //         supplyCaps[0] = 10000 * 10 ** usdcDecimals;
        //         comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
        //     }

        //     // Set borrow caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(newCtoken));
        //         uint256[] memory borrowCaps = new uint256[](1);
        //         borrowCaps[0] = 8500 * 10 ** usdcDecimals;
        //         comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
        //     }
        // }

        // // WETH
        // JumpRateModelV2 wethInterestRateModel;

        // {
        //     // $WETH Interest rate model & parameters
        //     uint256 baseRatePerYearWETH = 0;
        //     uint256 multiplierPerYearWETH = 0.035e18;
        //     uint256 jumpMultiplierPerYearWETH = 7e18;
        //     uint256 kinkWETH = 0.8e18;

        //     wethInterestRateModel = new JumpRateModelV2(
        //         baseRatePerYearWETH, multiplierPerYearWETH, jumpMultiplierPerYearWETH, kinkWETH, admin
        //     );
        // }

        // // Custom to $WETH
        // uint256 reserveFactorMantissaWETH = 0.15e18;
        // uint256 protocolSeizeShareMantissaWETH = 0.028e18;
        // uint8 wethDecimals = 18;

        // TokenDeploymentConfig memory cWethTokenDeploymentConfig = TokenDeploymentConfig(
        //     3 * 10 ** (wethDecimals - 3), // $10 worth of WETH -> 0.003 WETH
        //     reserveFactorMantissaWETH,
        //     protocolSeizeShareMantissaWETH,
        //     ETH_PRICE_FEED_ID,
        //     API3_ETH_PROXY,
        //     wethInterestRateModel
        // );

        // UnderlyingTokenDeploymentConfig memory underlyingWethTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(WETH_ADDRESS, "Mach WETH", "cWETH", wethDecimals);

        // {
        //     // Deploy WETH
        //     CErc20Delegator newCtoken = deployNewCErc20Token(
        //         underlyingWethTokenDeploymentConfig, cWethTokenDeploymentConfig, wethInterestRateModel
        //     );

        //     // Set supply caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(newCtoken));
        //         uint256[] memory supplyCaps = new uint256[](1);
        //         supplyCaps[0] = 3 * 10 ** wethDecimals;
        //         comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
        //     }

        //     // Set borrow caps
        //     {
        //         CToken[] memory cTokens = new CToken[](1);
        //         cTokens[0] = CToken(address(newCtoken));
        //         uint256[] memory borrowCaps = new uint256[](1);
        //         borrowCaps[0] = 25 * 10 ** (wethDecimals - 1); // 2.5 WETH
        //         comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
        //     }
        // }

        // // stS
        // uint256 baseRatePerYearStS = 0.02e18;
        // uint256 multiplierPerYearStS = 0.07e18;
        // uint256 jumpMultiplierPerYearStS = 3e18;
        // uint256 kinkStS = 0.5e18;

        // JumpRateModelV2 stSInterestRateModel = new JumpRateModelV2(
        //     baseRatePerYearStS, multiplierPerYearStS, jumpMultiplierPerYearStS, kinkStS, SAFE_MULTISIG_ADDRESS
        // );

        // uint256 reserveFactorMantissaStS = 0.15e18;
        // uint256 protocolSeizeShareMantissaStS = 0.028e18;
        // uint8 stSDecimals = 18;

        // TokenDeploymentConfig memory cStSTokenDeploymentConfig = TokenDeploymentConfig(
        //     25 * 10 ** stSDecimals, // 25 $S
        //     reserveFactorMantissaStS,
        //     protocolSeizeShareMantissaStS,
        //     S_PRICE_FEED_ID,
        //     API3_S_PROXY,
        //     stSInterestRateModel
        // );

        // UnderlyingTokenDeploymentConfig memory underlyingStSTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(ST_S_ADDRESS, "Mach stS", "cstS", stSDecimals);

        // // Deploy stS
        // CErc20Delegator cstS = deployOnlyCErc20Token(underlyingStSTokenDeploymentConfig, cStSTokenDeploymentConfig);
        // console.log("cstS deployed at", address(cstS));

        //  // Deploy API3 oracle for $stS
        // BeetsStakedSAPI3Oracle stSAPI3Oracle =
        //     new BeetsStakedSAPI3Oracle(SAFE_MULTISIG_ADDRESS, API3_S_PROXY);
        // console.log("stSAPI3Oracle deployed at", address(stSAPI3Oracle));

        // (uint256 stSPrice, bool isValid) = stSAPI3Oracle.getPrice(ST_S_ADDRESS);
        // require(stSPrice > 0, "stSAPI3Oracle price not set");
        // require(isValid, "stSAPI3Oracle price is not valid");
        // console.log("stSAPI3Oracle price", stSPrice);

        // // Deploy Pyth oracle for $stS
        // BeetsStakedSPythOracle stSPythOracle = new BeetsStakedSPythOracle(SAFE_MULTISIG_ADDRESS, 24 hours);
        // console.log("stSPythOracle deployed at", address(stSPythOracle));

        // (stSPrice, isValid) = stSPythOracle.getPrice(ST_S_ADDRESS);
        // require(stSPrice > 0, "stSPythOracle price not set");
        // require(isValid, "stSPythOracle price is not valid");
        // console.log("stSPythOracle price", stSPrice);

        // // SolvBTC
        // uint256 baseRatePerYearSolvBtc = 0;
        // uint256 multiplierPerYearSolvBtc = 0.065e18;
        // uint256 jumpMultiplierPerYearSolvBtc = 6e18;
        // uint256 kinkSolvBtc = 0.7e18;

        // JumpRateModelV2 solvBtcInterestRateModel = new JumpRateModelV2(
        //     baseRatePerYearSolvBtc, multiplierPerYearSolvBtc, jumpMultiplierPerYearSolvBtc, kinkSolvBtc, SAFE_MULTISIG_ADDRESS
        // );

        // console.log("solvBtcInterestRateModel deployed at", address(solvBtcInterestRateModel));

        // uint256 reserveFactorMantissaSolvBtc = 0.15e18;
        // uint256 protocolSeizeShareMantissaSolvBtc = 0.028e18;

        // UnderlyingTokenDeploymentConfig memory underlyingSolvBtcTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(SOLV_BTC_ADDRESS, "Mach solvBTC", "cSolvBtc", SOLV_BTC_DECIMALS);

        // TokenDeploymentConfig memory cSolvBtcTokenDeploymentConfig = TokenDeploymentConfig(
        //     2 * 1e14, // (20 / 100k) * 1e18
        //     reserveFactorMantissaSolvBtc,
        //     protocolSeizeShareMantissaSolvBtc,
        //     SOLV_PRICE_FEED_ID,
        //     API3_SOLVBTC_PROXY,
        //     solvBtcInterestRateModel
        // );

        // CErc20Delegator cSolvBtc = deployOnlyCErc20Token(underlyingSolvBtcTokenDeploymentConfig, cSolvBtcTokenDeploymentConfig);
        // console.log("cSolvBtc deployed at", address(cSolvBtc));

        // // scUSD
        // uint256 baseRatePerYearScUsd = 0;
        // uint256 multiplierPerYearScUsd = 0.06e18;
        // uint256 jumpMultiplierPerYearScUsd = 12e18;
        // uint256 kinkScUsd = 0.8e18;

        // JumpRateModelV2 scUsdInterestRateModel = new JumpRateModelV2(
        //     baseRatePerYearScUsd, multiplierPerYearScUsd, jumpMultiplierPerYearScUsd, kinkScUsd, SAFE_MULTISIG_ADDRESS
        // );

        // uint256 reserveFactorMantissaScUsd = 0.2e18;
        // uint256 protocolSeizeShareMantissaScUsd = 0.028e18;

        // UnderlyingTokenDeploymentConfig memory underlyingScUsdTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(SCUSD_ADDRESS, "Mach scUSD", "cscUSD", SCUSD_DECIMALS);

        // TokenDeploymentConfig memory cScUsdTokenDeploymentConfig = TokenDeploymentConfig(
        //     20 * 10 ** SCUSD_DECIMALS, // 20 $scUSD
        //     reserveFactorMantissaScUsd,
        //     protocolSeizeShareMantissaScUsd,
        //     USDC_PRICE_FEED_ID,
        //     API3_USDC_PROXY,
        //     scUsdInterestRateModel
        // );

        // CErc20Delegator cScUsd = deployOnlyCErc20Token(underlyingScUsdTokenDeploymentConfig, cScUsdTokenDeploymentConfig);
        // console.log("cScUsd deployed at", address(cScUsd));

        // // Check initial exchange rate
        // console.log("initial exchange rate", cScUsd.exchangeRateStored());
        // console.log("totalSupply", cScUsd.totalSupply());

        // // Check admin of CErc20Delegator
        // console.log("admin of CErc20Delegator", cScUsd.admin());
        // console.log("SAFE_MULTISIG_ADDRESS", SAFE_MULTISIG_ADDRESS);

        // require(cScUsd.admin() == SAFE_MULTISIG_ADDRESS, "Admin of CErc20Delegator should be SAFE_MULTISIG_ADDRESS");

        // // scBTC
        // uint256 baseRatePerYearScBtc = 0;
        // uint256 multiplierPerYearScBtc = 0.07e18;
        // uint256 jumpMultiplierPerYearScBtc = 2e18;
        // uint256 kinkScBtc = 0.6e18;

        // JumpRateModelV2 scBtcInterestRateModel = new JumpRateModelV2(
        //     baseRatePerYearScBtc, multiplierPerYearScBtc, jumpMultiplierPerYearScBtc, kinkScBtc, SAFE_MULTISIG_ADDRESS
        // );

        // uint256 reserveFactorMantissaScBtc = 0.15e18;
        // uint256 protocolSeizeShareMantissaScBtc = 0.028e18;

        // UnderlyingTokenDeploymentConfig memory underlyingScBtcTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(SCBTC_ADDRESS, "Mach scBTC", "cscBTC", SCBTC_DECIMALS);

        // TokenDeploymentConfig memory cScBtcTokenDeploymentConfig = TokenDeploymentConfig(
        //     0.0002 * 10 ** 8, // ~$20 worth of scBTC
        //     reserveFactorMantissaScBtc,
        //     protocolSeizeShareMantissaScBtc,
        //     WBTC_PRICE_FEED_ID,
        //     API3_WBTC_PROXY,
        //     scBtcInterestRateModel
        // );

        // CErc20Delegator cScBtc = deployOnlyCErc20Token(underlyingScBtcTokenDeploymentConfig, cScBtcTokenDeploymentConfig);
        // console.log("cScBtc deployed at", address(cScBtc));

        // // Check initial exchange rate
        // console.log("initial exchange rate", cScBtc.exchangeRateStored());
        // console.log("totalSupply", cScBtc.totalSupply());

        // // 1 cToken = 0.02 underlying token at start
        // require(cScBtc.exchangeRateStored() == 0.02e18, "Initial exchange rate should be 0.02e18");

        // // Check admin of CErc20Delegator
        // console.log("admin of CErc20Delegator", cScBtc.admin());
        // console.log("SAFE_MULTISIG_ADDRESS", SAFE_MULTISIG_ADDRESS);

        // require(cScBtc.admin() == SAFE_MULTISIG_ADDRESS, "Admin of CErc20Delegator should be SAFE_MULTISIG_ADDRESS");

        // scETH
        // uint256 baseRatePerYearScEth = 0;
        // uint256 multiplierPerYearScEth = 0.061e18;
        // uint256 jumpMultiplierPerYearScEth = 3.5e18;
        // uint256 kinkScEth = 0.35e18;

        // JumpRateModelV2 scEthInterestRateModel = new JumpRateModelV2(
        //     baseRatePerYearScEth, multiplierPerYearScEth, jumpMultiplierPerYearScEth, kinkScEth, SAFE_MULTISIG_ADDRESS
        // );

        // uint256 reserveFactorMantissaScEth = 0.15e18;
        // uint256 protocolSeizeShareMantissaScEth = 0.028e18;

        // UnderlyingTokenDeploymentConfig memory underlyingScEthTokenDeploymentConfig =
        //     UnderlyingTokenDeploymentConfig(SCETH_ADDRESS, "Mach scETH", "cscETH", SCETH_DECIMALS);

        // TokenDeploymentConfig memory cScEthTokenDeploymentConfig = TokenDeploymentConfig(
        //     0.01e18, // ~$20 worth of scETH
        //     reserveFactorMantissaScEth,
        //     protocolSeizeShareMantissaScEth,
        //     SCETH_PRICE_FEED_ID,
        //     API3_ETH_PROXY,
        //     scEthInterestRateModel
        // );

        // CErc20Delegator cScEth = deployOnlyCErc20Token(underlyingScEthTokenDeploymentConfig, cScEthTokenDeploymentConfig);
        // console.log("cScEth deployed at", address(cScEth));

        // // Check initial exchange rate
        // console.log("initial exchange rate", cScEth.exchangeRateStored());

        // // Check admin of CErc20Delegator
        // console.log("admin of CErc20Delegator", cScEth.admin());
        // require(cScEth.admin() == SAFE_MULTISIG_ADDRESS, "Admin of CErc20Delegator should be SAFE_MULTISIG_ADDRESS");

        vm.stopBroadcast();
    }

    function updateSupplyCaps(CToken[] memory cTokens, uint256[] memory supplyCaps) public {
        comptroller._setMarketSupplyCaps(cTokens, supplyCaps);

        for (uint256 i = 0; i < cTokens.length; i++) {
            console.log("cTokens[i]", address(cTokens[i]));
            console.log("supplyCaps[i]", supplyCaps[i]);
            require(comptroller.supplyCaps(address(cTokens[i])) == supplyCaps[i], "Supply cap not set properly");
        }
    }

    function updateBorrowCaps(CToken[] memory cTokens, uint256[] memory borrowCaps) public {
        comptroller._setMarketBorrowCaps(cTokens, borrowCaps);

        for (uint256 i = 0; i < cTokens.length; i++) {
            console.log("cTokens[i]", address(cTokens[i]));
            console.log("borrowCaps[i]", borrowCaps[i]);
            require(comptroller.borrowCaps(address(cTokens[i])) == borrowCaps[i], "Borrow cap not set properly");
        }
    }

    function deployComptroller() public returns (Comptroller comptrollerImplementation, Unitroller unitroller) {
        Comptroller comptrollerImplementation = new Comptroller();
        console.log("Comptroller deployed at", address(comptrollerImplementation));

        Unitroller unitroller = new Unitroller();
        console.log("Unitroller deployed at", address(unitroller));

        // Set pending comptroller implementation
        unitroller._setPendingImplementation(address(comptrollerImplementation));

        // Become comptroller
        comptrollerImplementation._become(unitroller);
        Comptroller comptroller = Comptroller(payable(address(unitroller)));

        // Set liquidation incentive mantissa (follows Compound v2)
        comptroller._setLiquidationIncentive(1.08e18);

        // Follow Compound v2's close factor
        comptroller._setCloseFactor(0.5e18);

        // Set borrow cap, pause cap, supply cap guardian
        comptroller._setBorrowCapGuardian(admin);
        comptroller._setPauseGuardian(admin);
        comptroller._setSupplyCapGuardian(admin);

        return (comptrollerImplementation, unitroller);
    }

    /**
     * @notice - Deploy price oracle
     * Deploys price oracle aggregator, that depends on Pyth and API3 oracle
     */
    function deployPriceOracle(address admin, address pythOracleAddress, uint256 stalenessPeriod)
        public
        returns (PythOracle pythOracle, API3Oracle api3Oracle, PriceOracleAggregator priceOracleAggregator)
    {
        PythOracle pythOracle = _deployPythOracle(admin, PYTH_ORACLE_ADDRESS, PYTH_STALENESS_PERIOD);

        address[] memory underlyingTokens = new address[](0);
        address[] memory api3ProxyAddresses = new address[](0);

        API3Oracle api3Oracle = _deployAPI3Oracle(admin, underlyingTokens, api3ProxyAddresses);

        address priceOracleAggregatorProxyAddress = Upgrades.deployUUPSProxy(
            "PriceOracleAggregator.sol", abi.encodeCall(PriceOracleAggregator.initialize, (admin))
        );
        PriceOracleAggregator priceOracleAggregator = PriceOracleAggregator(payable(priceOracleAggregatorProxyAddress));
        console.log("PriceOracleAggregator deployed at", address(priceOracleAggregator));

        return (pythOracle, api3Oracle, priceOracleAggregator);
    }

    function deployCSonic(
        TokenDeploymentConfig memory tokenDeploymentConfig,
        // @notice - Should be previously deployed
        Comptroller comptroller,
        PythOracle pythOracle,
        API3Oracle api3Oracle,
        PriceOracleAggregator priceOracleAggregator
    ) public returns (CSonic sonic, Maximillion maximillion) {
        // Follow Compound v2's initial exchange rate mantissa
        uint256 initialExchangeRateMantissa = 10 ** (SONIC_DECIMALS + 18 - CTOKEN_DECIMALS) / 50;

        // 1. Check enough balance for Sonic
        {
            require(
                address(admin).balance >= tokenDeploymentConfig.underlyingAmountToBurn, "Not enough balance for Sonic"
            );
        }

        // 2. Deploy CSonic
        CSonic newCSonic = new CSonic(
            ComptrollerInterface(address(comptroller)),
            tokenDeploymentConfig.interestRateModel,
            initialExchangeRateMantissa,
            "Mach Sonic",
            "cSonic",
            CTOKEN_DECIMALS,
            payable(admin)
        );
        console.log("CSonic deployed at", address(newCSonic));

        // 3. Update price oracle aggregator
        {
            IOracleSource[] memory oracles = new IOracleSource[](2);
            oracles[0] = api3Oracle;
            oracles[1] = pythOracle;
            priceOracleAggregator.updateTokenOracles(NATIVE_ASSET, oracles);
        }

        // 4. Set price feed id and api3 proxy address
        {
            console.log("Setting Pyth priceFeedId for asset:", NATIVE_ASSET);
            console.log("Corresponding priceFeedId");
            console.logBytes32(tokenDeploymentConfig.pythPriceFeedId);
            pythOracle.setPriceFeedId(NATIVE_ASSET, tokenDeploymentConfig.pythPriceFeedId);

            console.log("Setting api3 proxy address for asset:", NATIVE_ASSET);
            console.log("api3ProxyAddress", tokenDeploymentConfig.api3ProxyAddress);
            api3Oracle.setApi3ProxyAddress(NATIVE_ASSET, tokenDeploymentConfig.api3ProxyAddress);
        }

        // 5. Set reserve factor + protocol seize share
        {
            require(
                newCSonic._setReserveFactor(tokenDeploymentConfig.reserveFactorMantissa) == NO_ERROR,
                "Failed to set reserve factor"
            );
            require(
                newCSonic.reserveFactorMantissa() == tokenDeploymentConfig.reserveFactorMantissa,
                "Reserve factor not set properly"
            );
            console.log("reserveFactorMantissa", newCSonic.reserveFactorMantissa());

            require(
                newCSonic._setProtocolSeizeShare(tokenDeploymentConfig.protocolSeizeShareMantissa) == NO_ERROR,
                "Failed to set protocol seize share"
            );
            require(
                newCSonic.protocolSeizeShareMantissa() == tokenDeploymentConfig.protocolSeizeShareMantissa,
                "Protocol seize share not set properly"
            );
            console.log("protocolSeizeShareMantissa", newCSonic.protocolSeizeShareMantissa());
        }

        // 6. Support market safely
        {
            require(comptroller._supportMarket(CToken(address(newCSonic))) == NO_ERROR, "Failed to support market");
            newCSonic.mint{value: tokenDeploymentConfig.underlyingAmountToBurn}();
            require(
                newCSonic.balanceOf(admin)
                    == (tokenDeploymentConfig.underlyingAmountToBurn * 1e18) / initialExchangeRateMantissa,
                "Amount to burn not equal to expected initial exchange rate mantissa"
            );

            // Burn entire initial total balance of minted cTokens
            require(newCSonic.transfer(address(0), newCSonic.balanceOf(admin)), "Failed to burn cTokens");
            console.log("totalSupply", newCSonic.totalSupply());
            console.log("burnt cSonic", newCSonic.balanceOf(address(0)));
        }

        // Check state of market afterwards all operations
        {
            require(
                newCSonic.balanceOf(address(0)) == newCSonic.totalSupply(),
                "All cSonic minted on initially should be burned"
            );
            (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(newCSonic));
            require(isListed, "Market should be listed");
            require(collateralFactorMantissa == 0, "Collateral factor should be 0");

            uint256 sonicPrice = priceOracleAggregator.getUnderlyingPrice(CToken(address(newCSonic)));
            require(sonicPrice > 0, "Price not set");
            console.log("price", sonicPrice);
        }

        Maximillion maximillion = new Maximillion(newCSonic);
        console.log("Maximillion deployed at", address(maximillion));

        return (newCSonic, maximillion);
    }

    function deployNewCErc20Token(
        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig,
        TokenDeploymentConfig memory tokenDeploymentConfig,
        InterestRateModel interestRateModel
    ) public returns (CErc20Delegator newCtoken) {
        // Implementation contract for cErc20Delegator
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        console.log("CErc20Delegate deployed at", address(cErc20Delegate));

        // Follow Compound v2's initial exchange rate mantissa
        uint256 initialExchangeRateMantissa =
            10 ** (underlyingTokenDeploymentConfig.tokenDecimals + 18 - CTOKEN_DECIMALS) / 50;

        ERC20 underlyingErc20Token = ERC20(underlyingTokenDeploymentConfig.underlyingToken);

        // 1. Check enough balance for underlying token
        {
            require(
                underlyingErc20Token.balanceOf(admin) >= tokenDeploymentConfig.underlyingAmountToBurn,
                "Not enough balance for underlying token"
            );
        }

        // 2. Deploy CErc20Delegator
        CErc20Delegator newCtoken = new CErc20Delegator(
            underlyingTokenDeploymentConfig.underlyingToken,
            comptroller,
            tokenDeploymentConfig.interestRateModel,
            initialExchangeRateMantissa,
            underlyingTokenDeploymentConfig.name,
            underlyingTokenDeploymentConfig.symbol,
            CTOKEN_DECIMALS,
            payable(SAFE_MULTISIG_ADDRESS),
            address(cErc20Delegate),
            ""
        );
        console.log("CErc20Delegator deployed at", address(newCtoken));

        require(newCtoken.exchangeRateStored() == initialExchangeRateMantissa, "Initial exchange rate should be set");

        // 3. Deploy PriceOracleAggregator
        {
            console.log("Setting price feed id for asset:", underlyingTokenDeploymentConfig.underlyingToken);
            pythOracle.setPriceFeedId(
                underlyingTokenDeploymentConfig.underlyingToken, tokenDeploymentConfig.pythPriceFeedId
            );
            console.log("Setting api3 proxy address for asset:", underlyingTokenDeploymentConfig.underlyingToken);
            api3Oracle.setApi3ProxyAddress(
                underlyingTokenDeploymentConfig.underlyingToken, tokenDeploymentConfig.api3ProxyAddress
            );
        }

        // 4. Update price oracle aggregator
        {
            IOracleSource[] memory oracles = new IOracleSource[](2);
            oracles[0] = api3Oracle;
            oracles[1] = pythOracle;
            priceOracleAggregator.updateTokenOracles(underlyingTokenDeploymentConfig.underlyingToken, oracles);
        }

        // 5. Set reserve factor & protocol seize share
        {
            require(
                newCtoken._setReserveFactor(tokenDeploymentConfig.reserveFactorMantissa) == NO_ERROR,
                "Failed to set reserve factor"
            );
            require(
                newCtoken.reserveFactorMantissa() == tokenDeploymentConfig.reserveFactorMantissa,
                "Reserve factor not set properly"
            );

            require(
                newCtoken._setProtocolSeizeShare(tokenDeploymentConfig.protocolSeizeShareMantissa) == NO_ERROR,
                "Failed to set protocol seize share"
            );
            require(
                newCtoken.protocolSeizeShareMantissa() == tokenDeploymentConfig.protocolSeizeShareMantissa,
                "Protocol seize share not set properly"
            );
        }

        // 6. Support market safely
        // CAREFUL of "exchange rate" manipulation attacks on Compound v2 forks
        // @dev - Before setting collateral factors -> https://x.com/hexagate_/status/1650177766187323394
        // - Support market (ensuring CF = 0, by default)
        // - Mint some cTokens
        // - Burn them to make sure total supply doesn't go to zero
        // - Then set collateral factors once market grows in size
        {
            underlyingErc20Token.approve(address(newCtoken), tokenDeploymentConfig.underlyingAmountToBurn);
            require(comptroller._supportMarket(CToken(address(newCtoken))) == NO_ERROR, "Failed to support market");
            require(newCtoken.mint(tokenDeploymentConfig.underlyingAmountToBurn) == NO_ERROR, "Failed to mint cTokens");

            require(
                newCtoken.balanceOf(admin)
                    == (tokenDeploymentConfig.underlyingAmountToBurn * 1e18) / initialExchangeRateMantissa,
                "Amount to burn not equal to expected initial exchange rate mantissa"
            );
            require(
                newCtoken.totalSupply() == newCtoken.balanceOf(admin),
                "Total supply should be equal to balance of admin"
            );

            // Burn entire initial total balance of minted cTokens
            require(newCtoken.transfer(address(0), newCtoken.balanceOf(admin)), "Failed to burn cTokens");
        }

        // Check state of market afterwards all operations
        {
            require(
                newCtoken.balanceOf(address(0)) == newCtoken.totalSupply(),
                "All cTokens minted on initially should be burned"
            );
            (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(newCtoken));
            require(isListed, "Market should be listed");
            require(collateralFactorMantissa == 0, "Collateral factor should be 0");
            require(priceOracleAggregator.getUnderlyingPrice(CToken(address(newCtoken))) > 0, "Price not set");
        }

        return newCtoken;
    }

    function deployOnlyCErc20Token(
        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig,
        TokenDeploymentConfig memory tokenDeploymentConfig
    ) public returns (CErc20Delegator newCtoken) {
        // Implementation contract for cErc20Delegator
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        console.log("CErc20Delegate deployed at", address(cErc20Delegate));

        // Follow Compound v2's initial exchange rate mantissa
        uint256 initialExchangeRateMantissa =
            10 ** (underlyingTokenDeploymentConfig.tokenDecimals + 18 - CTOKEN_DECIMALS) / 50;

        ERC20 underlyingErc20Token = ERC20(underlyingTokenDeploymentConfig.underlyingToken);

        // 1. Deploy CErc20Delegator
        CErc20Delegator newCtoken = new CErc20Delegator(
            underlyingTokenDeploymentConfig.underlyingToken,
            comptroller,
            tokenDeploymentConfig.interestRateModel,
            initialExchangeRateMantissa,
            underlyingTokenDeploymentConfig.name,
            underlyingTokenDeploymentConfig.symbol,
            CTOKEN_DECIMALS,
            payable(SAFE_MULTISIG_ADDRESS),
            address(cErc20Delegate),
            ""
        );
        console.log("CErc20Delegator deployed at", address(newCtoken));

        require(newCtoken.exchangeRateStored() == initialExchangeRateMantissa, "Initial exchange rate should be set");
        require(newCtoken.totalSupply() == 0, "Total supply should be 0");
        require(newCtoken.comptroller() == comptroller, "Comptroller should be set");
        require(
            newCtoken.interestRateModel() == tokenDeploymentConfig.interestRateModel,
            "Interest rate model should be set"
        );
        require(newCtoken.exchangeRateStored() == initialExchangeRateMantissa, "Initial exchange rate should be set");
        require(newCtoken.decimals() == CTOKEN_DECIMALS, "Decimals should be set");

        // Print out token info
        CErc20 newCErc20 = CErc20(address(newCtoken));
        console.log("Token name:", newCErc20.name());
        console.log("Token symbol:", newCErc20.symbol());
        console.log("Token decimals:", newCErc20.decimals());
        console.log("Underlying token:", newCErc20.underlying());

        return newCtoken;
    }

    function _deployPythOracle(address admin, address pythOracleAddress, uint256 stalenessPeriod)
        internal
        returns (PythOracle pythOracle)
    {
        address[] memory underlyingTokens = new address[](0);
        bytes32[] memory priceFeedIds = new bytes32[](0);

        pythOracle = new PythOracle(admin, pythOracleAddress, underlyingTokens, priceFeedIds, stalenessPeriod);
        console.log("PythOracle deployed at", address(pythOracle));
    }

    function _deployAPI3Oracle(address admin, address[] memory underlyingTokens, address[] memory api3ProxyAddresses)
        internal
        returns (API3Oracle api3Oracle)
    {
        address[] memory underlyingTokens = new address[](0);
        address[] memory api3ProxyAddresses = new address[](0);

        api3Oracle = new API3Oracle(admin, underlyingTokens, api3ProxyAddresses);
        console.log("API3Oracle deployed at", address(api3Oracle));
    }

    function _deployJumpRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        address admin
    ) internal returns (JumpRateModelV2 jumpRateModel) {
        jumpRateModel = new JumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink, admin);

        return jumpRateModel;
    }
}
