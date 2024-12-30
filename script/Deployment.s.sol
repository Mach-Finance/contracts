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

    address public constant API3_USDC_PROXY = 0x6427406aAED75920aEB0419E361ef5cd6Eff509f;
    address public constant API3_ETH_PROXY = 0xaA5fbCdBa698DFc2f5F2268bCB01012262D7692D;
    address public constant API3_WBTC_PROXY = 0xcc897BD298FDc90c298e7509818a4d9f4F8ca0D1;
    address public constant API3_SOLVBTC_PROXY = 0x867A57D7bf23D464c5CE9B31af097F2E7a75d078;
    address public constant API3_FTM_PROXY = 0x8927DA1377C78D25E78c335F48a6f8e42Cce0C09;

    address public constant USDC_ADDRESS = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant WETH_ADDRESS = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;

    // TODO: Update this to the actual WBTC address
    address public constant WBTC_ADDRESS = address(123);

    // TODO: Set this to the safe multisig address
    address public constant SAFE_MULTISIG_ADDRESS = address(456);

    // Look at Euler for best practice
    // https://github.com/euler-xyz/euler-price-oracle/blob/master/src/adapter/pyth/PythOracle.sol
    uint256 public constant PYTH_STALENESS_PERIOD = 1 hours;

    uint256 constant NO_ERROR = 0;
    uint8 constant CTOKEN_DECIMALS = 8;
    uint8 constant SONIC_DECIMALS = 18;

    // @notice - Admin address for the deployment (Hardware wallet)
    address public admin;

    function run() public {
        admin = vm.envAddress("ETH_KEYSTORE_ACCOUNT");
        vm.startBroadcast();

        // Deploy comptroller
        (Comptroller comptrollerImplementation, Unitroller unitroller) = deployComptroller();

        Comptroller comptroller = Comptroller(payable(address(unitroller)));

        // Deploy price oracle
        (PythOracle pythOracle, API3Oracle api3Oracle, PriceOracleAggregator priceOracleAggregator) =
            deployPriceOracle(admin, PYTH_ORACLE_ADDRESS, PYTH_STALENESS_PERIOD);

        // Set price oracle
        require(comptroller._setPriceOracle(priceOracleAggregator) == NO_ERROR, "Failed to set price oracle");

        JumpRateModelV2 sonicInterestRateModel;
        {
            // $S Interest rate model & parameters
            uint256 baseRatePerYearSonic = 0;
            uint256 multiplierPerYearSonic = 0.05e18;
            uint256 jumpMultiplierPerYearSonic = 6e18;
            uint256 kinkSonic = 0.6e18;

            sonicInterestRateModel = new JumpRateModelV2(
                baseRatePerYearSonic, multiplierPerYearSonic, jumpMultiplierPerYearSonic, kinkSonic, admin
            );
        }

        // Implementation contract for cErc20Delegator
        CErc20Delegate cErc20Delegate = new CErc20Delegate();

        {
            // Custom to $S
            uint256 reserveFactorMantissaSonic = 0.3e18;
            uint256 protocolSeizeShareMantissaSonic = 0.028e18;

            TokenDeploymentConfig memory sonicTokenDeploymentConfig = TokenDeploymentConfig(
                15 * 10 ** SONIC_DECIMALS, // 15 $S ~ $10
                reserveFactorMantissaSonic,
                protocolSeizeShareMantissaSonic,
                FTM_PRICE_FEED_ID,
                API3_FTM_PROXY,
                sonicInterestRateModel
            );

            // Deploy Sonic
            (CSonic sonic, Maximillion maximillion) =
                deployCSonic(sonicTokenDeploymentConfig, comptroller, pythOracle, api3Oracle, priceOracleAggregator);

            // Set supply caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(sonic));
                uint256[] memory supplyCaps = new uint256[](1);
                supplyCaps[0] = 12500 * 10 ** SONIC_DECIMALS;
                comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
            }

            // Set borrow caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(sonic));
                uint256[] memory borrowCaps = new uint256[](1);
                borrowCaps[0] = 8500 * 10 ** SONIC_DECIMALS;
                comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
            }
        }

        JumpRateModelV2 usdcInterestRateModel;

        {
            // $USDC Interest rate model & parameters
            uint256 baseRatePerYearUSDC = 0;
            uint256 multiplierPerYearUSDC = 0.052e18;
            uint256 jumpMultiplierPerYearUSDC = 9e18;
            uint256 kinkUSDC = 0.85e18;

            usdcInterestRateModel = new JumpRateModelV2(
                baseRatePerYearUSDC, multiplierPerYearUSDC, jumpMultiplierPerYearUSDC, kinkUSDC, admin
            );
        }

        // Custom to $USDC
        uint256 reserveFactorMantissaUSDC = 0.15e18;
        uint256 protocolSeizeShareMantissaUSDC = 0.028e18;
        uint8 usdcDecimals = 6;

        TokenDeploymentConfig memory sonicTokenDeploymentConfig = TokenDeploymentConfig(
            10 * 10 ** usdcDecimals, // $20 worth of USDC
            reserveFactorMantissaUSDC,
            protocolSeizeShareMantissaUSDC,
            USDC_PRICE_FEED_ID,
            API3_USDC_PROXY,
            usdcInterestRateModel
        );

        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig =
            UnderlyingTokenDeploymentConfig(USDC_ADDRESS, "MachFi USDC", "cUSDC", usdcDecimals);

        {
            // Deploy USDC
            CErc20Delegator newCtoken = deployNewCErc20Token(
                underlyingTokenDeploymentConfig,
                sonicTokenDeploymentConfig,
                address(cErc20Delegate),
                comptroller,
                pythOracle,
                api3Oracle,
                priceOracleAggregator,
                usdcInterestRateModel
            );

            // Set supply caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(newCtoken));
                uint256[] memory supplyCaps = new uint256[](1);
                supplyCaps[0] = 10000 * 10 ** usdcDecimals;
                comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
            }

            // Set borrow caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(newCtoken));
                uint256[] memory borrowCaps = new uint256[](1);
                borrowCaps[0] = 8500 * 10 ** usdcDecimals;
                comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
            }
        }

        // WETH
        JumpRateModelV2 wethInterestRateModel;

        {
            // $WETH Interest rate model & parameters
            uint256 baseRatePerYearWETH = 0;
            uint256 multiplierPerYearWETH = 0.035e18;
            uint256 jumpMultiplierPerYearWETH = 7e18;
            uint256 kinkWETH = 0.8e18;

            wethInterestRateModel = new JumpRateModelV2(
                baseRatePerYearWETH, multiplierPerYearWETH, jumpMultiplierPerYearWETH, kinkWETH, admin
            );
        }

        // Custom to $WETH
        uint256 reserveFactorMantissaWETH = 0.15e18;
        uint256 protocolSeizeShareMantissaWETH = 0.028e18;
        uint8 wethDecimals = 18;

        TokenDeploymentConfig memory wethTokenDeploymentConfig = TokenDeploymentConfig(
            3 * 10 ** (wethDecimals - 3), // $10 worth of WETH -> 0.003 WETH
            reserveFactorMantissaWETH,
            protocolSeizeShareMantissaWETH,
            ETH_PRICE_FEED_ID,
            API3_ETH_PROXY,
            wethInterestRateModel
        );

        underlyingTokenDeploymentConfig =
            UnderlyingTokenDeploymentConfig(WETH_ADDRESS, "MachFi WETH", "cWETH", wethDecimals);

        {
            // Deploy WETH
            CErc20Delegator newCtoken = deployNewCErc20Token(
                underlyingTokenDeploymentConfig,
                sonicTokenDeploymentConfig,
                address(cErc20Delegate),
                comptroller,
                pythOracle,
                api3Oracle,
                priceOracleAggregator,
                wethInterestRateModel
            );

            // Set supply caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(newCtoken));
                uint256[] memory supplyCaps = new uint256[](1);
                supplyCaps[0] = 3 * 10 ** wethDecimals;
                comptroller._setMarketSupplyCaps(cTokens, supplyCaps);
            }

            // Set borrow caps
            {
                CToken[] memory cTokens = new CToken[](1);
                cTokens[0] = CToken(address(newCtoken));
                uint256[] memory borrowCaps = new uint256[](1);
                borrowCaps[0] = 25 * 10 ** (wethDecimals - 1); // 2.5 WETH
                comptroller._setMarketBorrowCaps(cTokens, borrowCaps);
            }
        }

        vm.stopBroadcast();
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
        console.log("PythOracle deployed at", address(pythOracle));

        address[] memory underlyingTokens = new address[](0);
        address[] memory api3ProxyAddresses = new address[](0);

        API3Oracle api3Oracle = _deployAPI3Oracle(admin, underlyingTokens, api3ProxyAddresses);
        console.log("API3Oracle deployed at", address(api3Oracle));

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
            console.log("Setting price feed id for asset:", NATIVE_ASSET);
            pythOracle.setPriceFeedId(NATIVE_ASSET, tokenDeploymentConfig.pythPriceFeedId);
            console.log("Setting api3 proxy address for asset:", NATIVE_ASSET);
            console.log("api3ProxyAddress", tokenDeploymentConfig.api3ProxyAddress);
            console.log("owner", api3Oracle.owner());

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

            require(
                newCSonic._setProtocolSeizeShare(tokenDeploymentConfig.protocolSeizeShareMantissa) == NO_ERROR,
                "Failed to set protocol seize share"
            );
            require(
                newCSonic.protocolSeizeShareMantissa() == tokenDeploymentConfig.protocolSeizeShareMantissa,
                "Protocol seize share not set properly"
            );
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

            require(priceOracleAggregator.getUnderlyingPrice(CToken(address(newCSonic))) > 0, "Price not set");
        }

        Maximillion maximillion = new Maximillion(newCSonic);
        console.log("Maximillion deployed at", address(maximillion));

        return (newCSonic, maximillion);
    }

    function deployNewCErc20Token(
        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig,
        TokenDeploymentConfig memory tokenDeploymentConfig,
        address cErc20Delegate,
        // @notice - Should be previously deployed
        Comptroller comptroller,
        PythOracle pythOracle,
        API3Oracle api3Oracle,
        PriceOracleAggregator priceOracleAggregator,
        InterestRateModel interestRateModel
    ) public returns (CErc20Delegator newCtoken) {
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
            payable(admin),
            address(0),
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
}
