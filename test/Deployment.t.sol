// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CErc20Delegate} from "../src/CErc20Delegate.sol";
import {CErc20} from "../src/CErc20.sol";
import {CSonic} from "../src/CSonic.sol";
import {CToken} from "../src/CToken.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {PythOracle} from "../src/Oracles/Pyth/PythOracle.sol";
import {API3Oracle} from "../src/Oracles/API3/API3Oracle.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {IOracleSource} from "../src/Oracles/IOracleSource.sol";
import {console} from "forge-std/console.sol";
import {TokenDeploymentConfig, UnderlyingTokenDeploymentConfig} from "../script/Deployment.s.sol";
import {BeetsStakedSAPI3Oracle} from "../src/Oracles/Beets/BeetsStakedSAPI3Oracle.sol";
import {BeetsStakedSPythOracle} from "../src/Oracles/Beets/BeetsStakedSPythOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {JumpRateModelV2} from "../src/JumpRateModelV2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    bytes32 constant USDC_PRICE_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    // API3 addresses
    address constant API3_USDC_PROXY = 0x6427406aAED75920aEB0419E361ef5cd6Eff509f;
    address constant FTM_API3_PROXY_ADDRESS = 0x41Efded5ec14C2783a42dA9e8c7970aC313d5576;
    address constant S_API3_PROXY_ADDRESS = 0x726D2E87d73567ecA1b75C063Bd09c1493655918;
    address constant NEW_S_API3_PROXY_ADDRESS = 0x2551A2a96988829D2a55c3b02b88E138023D1cE8;
    address constant SCUSD_ADDRESS = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;

    // Underlying tokens
    address constant ST_S_ADDRESS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    // Deployed tokens
    CSonic public constant cSonic = CSonic(payable(0x9F5d9f2FDDA7494aA58c90165cF8E6B070Fe92e6));
    CErc20 public constant cUsdc = CErc20(0xC84F54B2dB8752f80DEE5b5A48b64a2774d2B445);
    CErc20 public constant cWeth = CErc20(0x15eF11b942Cc14e582797A61e95D47218808800D);
    CErc20 public constant cStS = CErc20(0xbAA06b4D6f45ac93B6c53962Ea861e6e3052DC74);
    CErc20 public constant cscUsd = CErc20(0xe5A79Db6623BCA3C65337dd6695Ae6b1f53Bec45);

    CErc20Delegator cUsdcDelegator = CErc20Delegator(payable(address(cUsdc)));
    CErc20Delegator cWethDelegator = CErc20Delegator(payable(address(cWeth)));

    string SONIC_MAINNET_RPC_URL = vm.envString("SONIC_MAINNET_RPC_URL");

    uint256 constant NO_ERROR = 0;
    uint8 constant CTOKEN_DECIMALS = 8;
    uint8 constant SONIC_DECIMALS = 18;
    uint8 constant ST_S_DECIMALS = 18;
    uint8 constant SCUSD_DECIMALS = 6;

    // Follow Compound v2's initial exchange rate mantissa
    uint256 initialExchangeRateMantissa = 10 ** (SONIC_DECIMALS + 18 - CTOKEN_DECIMALS) / 50;

    uint256 sonicMainnetFork;

    function setUp() public {
        sonicMainnetFork = vm.createSelectFork(SONIC_MAINNET_RPC_URL);
    }

    // These steps are to be used for simulation, before broadcasting them to the chain
    function test_transferAdmin(address newAdmin) public {
        vm.assume(newAdmin != address(0));

        vm.prank(SAFE_MULTISIG_ADDRESS);
        unitroller._setPendingAdmin(payable(newAdmin));
        vm.prank(newAdmin);
        unitroller._acceptAdmin();

        // Check admin is set
        assertEq(unitroller.admin(), newAdmin);

        // Old admin address should fail
        vm.startPrank(admin);
        require(comptroller._setCollateralFactor(cSonic, 0.7e18) == 1, "Old admin should fail");
        vm.stopPrank();
    }

    function test_updateCSonicOracle() public {
        vm.skip(true);

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
        vm.skip(true);

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

        // Mint some $S
        uint256 err = cSonic.mintAsCollateral{value: 1 ether}();
        require(err == 0, "Failed to mint $S");

        // Check if $S is used as collateral
        require(comptroller.checkMembership(SAFE_MULTISIG_ADDRESS, address(cSonic)), "Sonic is not used as collateral");
        require(cSonic.balanceOf(SAFE_MULTISIG_ADDRESS) > 0, "Sonic balance is 0");

        vm.stopPrank();
    }

    function test_deployScUsd() public {
        vm.startPrank(admin);

        uint256 baseRatePerYearScUsd = 0;
        uint256 multiplierPerYearScUsd = 0.06e18;
        uint256 jumpMultiplierPerYearScUsd = 12e18;
        uint256 kinkScUsd = 0.8e18;

        JumpRateModelV2 scUsdInterestRateModel = new JumpRateModelV2(
            baseRatePerYearScUsd, multiplierPerYearScUsd, jumpMultiplierPerYearScUsd, kinkScUsd, SAFE_MULTISIG_ADDRESS
        );

        uint256 reserveFactorMantissaScUsd = 0.2e18;
        uint256 protocolSeizeShareMantissaScUsd = 0.028e18;
        uint8 scUsdDecimals = 6;

        TokenDeploymentConfig memory cScUsdTokenDeploymentConfig = TokenDeploymentConfig(
            20 * 10 ** scUsdDecimals, // 20 $USDC
            reserveFactorMantissaScUsd,
            protocolSeizeShareMantissaScUsd,
            USDC_PRICE_FEED_ID,
            API3_USDC_PROXY,
            scUsdInterestRateModel
        );

        UnderlyingTokenDeploymentConfig memory underlyingScUsdTokenDeploymentConfig =
            UnderlyingTokenDeploymentConfig(SCUSD_ADDRESS, "Mach scUSD", "cscUsd", scUsdDecimals);

        CErc20Delegator cscUsd =
            deployOnlyCErc20Token(underlyingScUsdTokenDeploymentConfig, cScUsdTokenDeploymentConfig);

        vm.stopPrank();

        // Switch to SAFE_MULTISIG_ADDRESS to support market & update oracles
        vm.startPrank(SAFE_MULTISIG_ADDRESS);

        // Update Pyth Oracle to support $scUSD
        pythOracle.setPriceFeedId(SCUSD_ADDRESS, USDC_PRICE_FEED_ID);

        // Update API3 Oracle to support $scUSD
        api3Oracle.setApi3ProxyAddress(SCUSD_ADDRESS, API3_USDC_PROXY);

        // Update price oracle aggregator
        IOracleSource[] memory scUsdOracles = new IOracleSource[](2);
        scUsdOracles[0] = api3Oracle;
        scUsdOracles[1] = pythOracle;

        priceOracleAggregator.updateTokenOracles(SCUSD_ADDRESS, scUsdOracles);

        // Set reserve factor & protocol seize share
        cscUsd._setReserveFactor(reserveFactorMantissaScUsd);
        cscUsd._setProtocolSeizeShare(protocolSeizeShareMantissaScUsd);

        require(cscUsd.reserveFactorMantissa() == reserveFactorMantissaScUsd, "Reserve factor not set properly");
        require(
            cscUsd.protocolSeizeShareMantissa() == protocolSeizeShareMantissaScUsd,
            "Protocol seize share not set properly"
        );

        ERC20 scUsd = ERC20(SCUSD_ADDRESS);

        {
            scUsd.approve(address(cscUsd), cScUsdTokenDeploymentConfig.underlyingAmountToBurn);
            require(comptroller._supportMarket(CToken(address(cscUsd))) == NO_ERROR, "Failed to support market");
            require(
                cscUsd.mint(cScUsdTokenDeploymentConfig.underlyingAmountToBurn) == NO_ERROR, "Failed to mint cTokens"
            );

            require(
                cscUsd.balanceOf(SAFE_MULTISIG_ADDRESS)
                    == (cScUsdTokenDeploymentConfig.underlyingAmountToBurn * 1e18) / initialExchangeRateMantissa,
                "Amount to burn not equal to expected initial exchange rate mantissa"
            );
            require(
                cscUsd.totalSupply() == cscUsd.balanceOf(SAFE_MULTISIG_ADDRESS),
                "Total supply should be equal to balance of admin"
            );

            // Burn entire initial total balance of minted cTokens
            require(cscUsd.transfer(address(0), cscUsd.balanceOf(SAFE_MULTISIG_ADDRESS)), "Failed to burn cTokens");
        }

        // Check state of market afterwards all operations
        {
            require(
                cscUsd.balanceOf(address(0)) == cscUsd.totalSupply(), "All cTokens minted on initially should be burned"
            );
            (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(cscUsd));
            require(isListed, "Market should be listed");
            require(collateralFactorMantissa == 0, "Collateral factor should be 0");

            uint256 price = priceOracleAggregator.getUnderlyingPrice(CToken(address(cscUsd)));
            console.log("Price of cscUsd", price);
            require(price > 0, "Price not set");
        }

        vm.stopPrank();
    }

    function test_deployStS() public {
        vm.startPrank(admin);

        uint256 baseRatePerYearStS = 0.02e18;
        uint256 multiplierPerYearStS = 0.07e18;
        uint256 jumpMultiplierPerYearStS = 3e18;
        uint256 kinkStS = 0.5e18;

        JumpRateModelV2 stSInterestRateModel = new JumpRateModelV2(
            baseRatePerYearStS, multiplierPerYearStS, jumpMultiplierPerYearStS, kinkStS, SAFE_MULTISIG_ADDRESS
        );

        uint256 reserveFactorMantissaStS = 0.15e18;
        uint256 protocolSeizeShareMantissaStS = 0.028e18;
        uint8 stSDecimals = 18;

        TokenDeploymentConfig memory cStSTokenDeploymentConfig = TokenDeploymentConfig(
            25 * 10 ** stSDecimals, // 25 $S
            reserveFactorMantissaStS,
            protocolSeizeShareMantissaStS,
            S_PRICE_FEED_ID,
            NEW_S_API3_PROXY_ADDRESS,
            stSInterestRateModel
        );

        UnderlyingTokenDeploymentConfig memory underlyingStSTokenDeploymentConfig =
            UnderlyingTokenDeploymentConfig(ST_S_ADDRESS, "Mach stS", "cstS", stSDecimals);

        CErc20Delegator cstS = deployOnlyCErc20Token(underlyingStSTokenDeploymentConfig, cStSTokenDeploymentConfig);

        vm.stopPrank();

        // Switch to SAFE_MULTISIG_ADDRESS to support market & update oracles
        vm.startPrank(SAFE_MULTISIG_ADDRESS);

        // Deploy API3 oracle for $stS
        BeetsStakedSAPI3Oracle stSAPI3Oracle =
            new BeetsStakedSAPI3Oracle(SAFE_MULTISIG_ADDRESS, NEW_S_API3_PROXY_ADDRESS);

        // Deploy Pyth oracle for $stS
        BeetsStakedSPythOracle stSPythOracle = new BeetsStakedSPythOracle(SAFE_MULTISIG_ADDRESS, 24 hours);

        // Update price oracle aggregator
        IOracleSource[] memory stSOracles = new IOracleSource[](2);
        stSOracles[0] = stSAPI3Oracle;
        stSOracles[1] = stSPythOracle;
        priceOracleAggregator.updateTokenOracles(ST_S_ADDRESS, stSOracles);

        // Set reserve factor & protocol seize share
        cstS._setReserveFactor(reserveFactorMantissaStS);
        cstS._setProtocolSeizeShare(protocolSeizeShareMantissaStS);

        require(cstS.reserveFactorMantissa() == reserveFactorMantissaStS, "Reserve factor not set properly");
        require(
            cstS.protocolSeizeShareMantissa() == protocolSeizeShareMantissaStS, "Protocol seize share not set properly"
        );

        ERC20 stS = ERC20(ST_S_ADDRESS);

        {
            stS.approve(address(cstS), cStSTokenDeploymentConfig.underlyingAmountToBurn);
            require(comptroller._supportMarket(CToken(address(cstS))) == NO_ERROR, "Failed to support market");
            require(cstS.mint(cStSTokenDeploymentConfig.underlyingAmountToBurn) == NO_ERROR, "Failed to mint cTokens");

            require(
                cstS.balanceOf(SAFE_MULTISIG_ADDRESS)
                    == (cStSTokenDeploymentConfig.underlyingAmountToBurn * 1e18) / initialExchangeRateMantissa,
                "Amount to burn not equal to expected initial exchange rate mantissa"
            );
            require(
                cstS.totalSupply() == cstS.balanceOf(SAFE_MULTISIG_ADDRESS),
                "Total supply should be equal to balance of admin"
            );

            // Burn entire initial total balance of minted cTokens
            require(cstS.transfer(address(0), cstS.balanceOf(SAFE_MULTISIG_ADDRESS)), "Failed to burn cTokens");
        }

        // Check state of market afterwards all operations
        {
            require(
                cstS.balanceOf(address(0)) == cstS.totalSupply(), "All cTokens minted on initially should be burned"
            );
            (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(cstS));
            require(isListed, "Market should be listed");
            require(collateralFactorMantissa == 0, "Collateral factor should be 0");
            require(priceOracleAggregator.getUnderlyingPrice(CToken(address(cstS))) > 0, "Price not set");
        }

        vm.stopPrank();
    }

    function deployOnlyCErc20Token(
        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig,
        TokenDeploymentConfig memory tokenDeploymentConfig
    ) public returns (CErc20Delegator newCtoken) {
        // Implementation contract for cErc20Delegator
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        console.log("CErc20Delegate deployed at", address(cErc20Delegate));

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

        return newCtoken;
    }

    function deployNewCErc20Token(
        UnderlyingTokenDeploymentConfig memory underlyingTokenDeploymentConfig,
        TokenDeploymentConfig memory tokenDeploymentConfig,
        InterestRateModel interestRateModel
    ) public returns (CErc20Delegator newCtoken) {
        // Implementation contract for cErc20Delegator
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        console.log("CErc20Delegate deployed at", address(cErc20Delegate));

        ERC20 underlyingErc20Token = ERC20(underlyingTokenDeploymentConfig.underlyingToken);

        // 1. Check enough balance for underlying token
        {
            require(
                underlyingErc20Token.balanceOf(SAFE_MULTISIG_ADDRESS) >= tokenDeploymentConfig.underlyingAmountToBurn,
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

    function test_updateCollateralFactor() public {
        vm.startPrank(SAFE_MULTISIG_ADDRESS);

        // Check collateral factor of $S
        (bool isSonicListed, uint256 sonicCollateralFactorMantissa) = comptroller.markets(address(cSonic));
        require(isSonicListed, "Market should be listed");
        require(sonicCollateralFactorMantissa == 0.7e18, "Collateral factor should be 0.7e18");

        console.log("Sonic collateral factor", sonicCollateralFactorMantissa);

        // Update collateral factor of $stS
        comptroller._setCollateralFactor(cStS, 0.6e18);
        (bool isStSListed, uint256 stSCollateralFactorMantissa) = comptroller.markets(address(cStS));
        require(isStSListed, "Market should be listed");
        require(stSCollateralFactorMantissa == 0.6e18, "Collateral factor should be 0.6e18");
        vm.stopPrank();
    }

    function test_setMarketSupplyAndBorrowCaps() public {
        vm.startPrank(SAFE_MULTISIG_ADDRESS);
        // Update market supply cap
        {
            CToken[] memory cTokens = new CToken[](1);
            cTokens[0] = CToken(address(cStS));

            uint256[] memory supplyCaps = new uint256[](1);
            supplyCaps[0] = 500000000000000000000000;
            comptroller._setMarketSupplyCaps(cTokens, supplyCaps);

            console.log("Supply cap set for cStS", comptroller.supplyCaps(address(cStS)));
            require(
                comptroller.supplyCaps(address(cStS)) == 500000 * 10 ** ST_S_DECIMALS, "Supply cap not set properly"
            );
        }

        // Update market borrow cap
        {
            CToken[] memory cTokens = new CToken[](2);
            cTokens[0] = CToken(address(cStS));
            cTokens[1] = CToken(address(cSonic));

            uint256[] memory borrowCaps = new uint256[](2);
            borrowCaps[0] = 250000000000000000000000;
            borrowCaps[1] = 750000000000000000000000;

            comptroller._setMarketBorrowCaps(cTokens, borrowCaps);

            console.log("Borrow cap set for cStS", comptroller.borrowCaps(address(cStS)));
            console.log("Borrow cap set for cSonic", comptroller.borrowCaps(address(cSonic)));
            require(
                comptroller.borrowCaps(address(cStS)) == 250000 * 10 ** ST_S_DECIMALS, "Borrow cap not set properly"
            );

            require(
                comptroller.borrowCaps(address(cSonic)) == 750000 * 10 ** SONIC_DECIMALS, "Borrow cap not set properly"
            );
        }

        vm.stopPrank();
    }
}
