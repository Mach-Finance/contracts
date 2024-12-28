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
import {BandOracle} from "../src/Oracles/Band/BandOracle.sol";
import {API3Oracle} from "../src/Oracles/API3/API3Oracle.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {PriceOracleAggregator} from "../src/Oracles/PriceOracleAggregator.sol";
import {Maximillion} from "../src/Maximillion.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {ComptrollerV1Storage} from "../src/ComptrollerStorage.sol";
import {FaucetERC20} from "./helpers/FaucetERC20.sol";

import "forge-std/console.sol";

contract TestnetDeploymentScript is Script {
    bytes32 constant FTM_PRICE_FEED_ID = 0x5c6c0d2386e3352356c3ab84434fafb5ea067ac2678a38a338c4a69ddc4bdb0c;
    bytes32 constant WBTC_PRICE_FEED_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
    bytes32 constant USDC_PRICE_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant SOLV_PRICE_FEED_ID = 0xf253cf87dc7d5ed5aa14cba5a6e79aee8bcfaef885a0e1b807035a0bbecc36fa;
    bytes32 constant ETH_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDT_PRICE_FEED_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;

    address public constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant BLAZE_TESTNET_PYTH_ORACLE_ADDRESS = 0x96124d1F6E44FfDf1fb5D6d74BB2DE1B7Fbe7376;

    address constant SONIC_BLAZE_TESTNET_API3_FTM_PROXY = 0x8927DA1377C78D25E78c335F48a6f8e42Cce0C09;
    address constant SONIC_BLAZE_TESTNET_API3_WBTC_PROXY = 0x041a131Fa91Ad61dD85262A42c04975986580d50;
    address constant SONIC_BLAZE_TESTNET_API3_USDC_PROXY = 0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f;
    address constant SONIC_BLAZE_TESTNET_API3_SOLV_PROXY = 0xadf6e9419E483Cc214dfC9EF1887f3aa7e85cA09;
    address constant SONIC_BLAZE_TESTNET_API3_ETH_PROXY = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address constant SONIC_BLAZE_TESTNET_API3_USDT_PROXY = 0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76;

    // Look at Euler for best practice
    // https://github.com/euler-xyz/euler-price-oracle/blob/master/src/adapter/pyth/PythOracle.sol
    uint256 public constant PYTH_STALENESS_PERIOD = 1 hours;
    uint256 constant NO_ERROR = 0;
    uint8 constant CTOKEN_DECIMALS = 8;
    uint8 constant SONIC_DECIMALS = 18;

    CSonic public cSonic = CSonic(payable(0xa3FC66E3098d6D7BEfB6e3EC4356B20e3DFD8890));

    FaucetERC20 public usdc = FaucetERC20(0x1FF8b7dB7FA8437413BB35Eaa01273100Ce674AA);
    CErc20Delegator public cUsdc = CErc20Delegator(payable(0xA979D386C68093A7ebb859375d41245D2df8dc1f));

    FaucetERC20 public wbtc = FaucetERC20(0xe4aA8fA3Dcd77d72b92Ed8E2439307159bEcE982);
    CErc20Delegator public cWbtc = CErc20Delegator(payable(0x032c61121472C9F486ec6DCe5aB14Ba9dF753aB6));

    FaucetERC20 public eth = FaucetERC20(0xeAa4b815Ac96bdAf16e3E21fDE41E5eca14E1c7f);
    CErc20Delegator public cEth = CErc20Delegator(payable(0x5832d12d08d68f2616F1F8BbDb9701256Dfdb00A));

    FaucetERC20 public solv = FaucetERC20(0xC232E169b791a29053bF994a29Fad1790BB04BcB);
    CErc20Delegator public cSolv = CErc20Delegator(payable(0xDE56CD3380e72D6FBf97c9B5dF7567E41F11d2AB));

    CErc20Delegate public cDelegate = CErc20Delegate(0xF029218283442b75474c4DCf902b1cCb2c044fAa);

    Comptroller public comptrollerImplementation = Comptroller(0xC70a960C2B26cD79b2b8f01eDe2f4a67930a983b);
    Comptroller public comptroller = Comptroller(0x377401C85077589EeDCeEb443368Cb140928f61A);
    Unitroller public unitroller = Unitroller(payable(0x377401C85077589EeDCeEb443368Cb140928f61A));

    PythOracle public pythOracle = PythOracle(0xA36a07BBb8a45ADdcC005A99CaDAA9d195FD94Cd);
    API3Oracle public api3Oracle = API3Oracle(0x7DD27dBA120A4269CfB81Ab250abEa958980Cee6);
    PriceOracleAggregator public priceOracleAggregator =
        PriceOracleAggregator(0x4518765214645dD7bAe27139d9DFDbc6E7ac99F6);

    // @notice - Admin address for the deployment
    address public admin;

    function run() public {
        uint256 privateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        admin = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        deployNewCErc20Token("MachFi USDT", "cUSDT", 6, USDT_PRICE_FEED_ID, SONIC_BLAZE_TESTNET_API3_USDT_PROXY);
        deployCSonic(FTM_PRICE_FEED_ID, SONIC_BLAZE_TESTNET_API3_FTM_PROXY);

        vm.stopBroadcast();
    }

    function deployNewCErc20Token(
        string memory name,
        string memory symbol,
        uint8 tokenDecimals,
        bytes32 pythPriceFeedId,
        address api3ProxyAddress
    ) public {
        // TODO: To be adjusted based on the initial exchange rate mantissa
        uint256 amountToBurn = 1 * 10 ** tokenDecimals;
        uint256 reserveFactorMantissa = 0.1e18;

        // Follow Compound v2's initial exchange rate mantissa
        uint256 initialExchangeRateMantissa = 10 ** (tokenDecimals + 18 - CTOKEN_DECIMALS) / 50;

        // 1. Deploy MockERC20 & mint to admin
        FaucetERC20 newErc20 = new FaucetERC20(name, symbol, tokenDecimals);
        console.log("name: ", name);
        console.log("symbol: ", symbol);
        newErc20.mint(admin, amountToBurn);

        InterestRateModel newInterestRateModel;

        {
            // TODO: To be adjusted based on token, on mainnet Sonic
            uint256 baseRatePerYear = 0;
            uint256 multiplierPerYear = 0.25e18;
            uint256 jumpMultiplierPerYear = 5e18;
            uint256 kink_ = 0.8e18;

            newInterestRateModel =
                new JumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, admin);
            console.log("InterestRateModel deployed at", address(newInterestRateModel));
        }

        // 2. Deploy CErc20Delegator
        CErc20Delegator newCtoken = new CErc20Delegator(
            address(newErc20),
            comptroller,
            newInterestRateModel,
            initialExchangeRateMantissa,
            name,
            symbol,
            CTOKEN_DECIMALS,
            payable(admin),
            address(cDelegate),
            ""
        );
        console.log("CErc20Delegator deployed at", address(newCtoken));
        require(newCtoken.exchangeRateStored() == initialExchangeRateMantissa, "Initial exchange rate should be set");

        // 3. Deploy PriceOracleAggregator
        {
            console.log("Setting price feed id for", address(newErc20));
            pythOracle.setPriceFeedId(address(newErc20), pythPriceFeedId);
            console.log("Setting api3 proxy address for", address(newErc20));
            api3Oracle.setApi3ProxyAddress(address(newErc20), api3ProxyAddress);
        }

        // 4. Update price oracle aggregator
        {
            IOracleSource[] memory oracles = new IOracleSource[](2);
            oracles[0] = api3Oracle;
            oracles[1] = pythOracle;
            priceOracleAggregator.updateTokenOracles(address(newErc20), oracles);
        }

        // 5. Set reserve factor (to be adjusted based on token)
        {
            require(newCtoken._setReserveFactor(reserveFactorMantissa) == NO_ERROR, "Failed to set reserve factor");
            require(newCtoken.reserveFactorMantissa() == reserveFactorMantissa, "Reserve factor not set properly");
        }

        // 6. Support market safely
        // CAREFUL of "exchange rate" manipulation attacks on Compound v2 forks
        // @dev - Before setting collateral factors -> https://x.com/hexagate_/status/1650177766187323394
        // - Support market (ensuring CF = 0, by default)
        // - Mint some cTokens
        // - Burn them to make sure total supply doesn't go to zero
        // - Then set collateral factors once market grows in size
        {
            newErc20.approve(address(newCtoken), amountToBurn);
            require(comptroller._supportMarket(CToken(address(newCtoken))) == NO_ERROR, "Failed to support market");
            require(newCtoken.mint(amountToBurn) == NO_ERROR, "Failed to mint cTokens");

            require(
                newCtoken.balanceOf(admin) == (amountToBurn * 1e18) / initialExchangeRateMantissa,
                "Amount to burn not equal to expected initial exchange rate mantissa"
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
        }
    }

    function deployCSonic(bytes32 pythPriceFeedId, address api3ProxyAddress) public {
        // TODO: To be adjusted based on the initial exchange rate mantissa
        uint256 amountToBurn = 1 * 10 ** SONIC_DECIMALS;
        uint256 reserveFactorMantissa = 0.1e18;

        // Follow Compound v2's initial exchange rate mantissa
        uint256 initialExchangeRateMantissa = 10 ** (SONIC_DECIMALS + 18 - CTOKEN_DECIMALS) / 50;

        // 1. Set & Deploy interest rate models
        InterestRateModel newInterestRateModel;

        {
            // TODO: Adjust on mainnet Sonic
            uint256 baseRatePerYear = 0;
            uint256 multiplierPerYear = 0.25e18;
            uint256 jumpMultiplierPerYear = 5e18;
            uint256 kink_ = 0.8e18;

            newInterestRateModel =
                new JumpRateModelV2(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, admin);
            console.log("InterestRateModel deployed at", address(newInterestRateModel));
        }

        // 2. Deploy CSonic
        CSonic newCSonic = new CSonic(
            ComptrollerInterface(address(comptroller)),
            newInterestRateModel,
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
            console.log("Setting price feed id for", NATIVE_ASSET);
            pythOracle.setPriceFeedId(NATIVE_ASSET, pythPriceFeedId);
            console.log("Setting api3 proxy address for", NATIVE_ASSET);
            api3Oracle.setApi3ProxyAddress(NATIVE_ASSET, api3ProxyAddress);
        }

        // 5. Set reserve factor
        {
            require(newCSonic._setReserveFactor(reserveFactorMantissa) == NO_ERROR, "Failed to set reserve factor");
            require(newCSonic.reserveFactorMantissa() == reserveFactorMantissa, "Reserve factor not set properly");
        }

        // 6. Support market safely
        {
            require(comptroller._supportMarket(CToken(address(newCSonic))) == NO_ERROR, "Failed to support market");
            newCSonic.mint{value: amountToBurn}();
            require(
                newCSonic.balanceOf(admin) == (amountToBurn * 1e18) / initialExchangeRateMantissa,
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
        }
    }

    function deployComptroller() public {
        comptrollerImplementation = new Comptroller();
        console.log("Comptroller deployed at", address(comptrollerImplementation));

        unitroller = new Unitroller();
        console.log("Unitroller deployed at", address(unitroller));

        // Set pending comptroller implementation
        unitroller._setPendingImplementation(address(comptrollerImplementation));

        // Become comptroller
        comptrollerImplementation._become(unitroller);
        comptroller = Comptroller(payable(address(unitroller)));
    }

    function deployPriceOracles() public returns (PriceOracleAggregator) {
        _deployPythOracle();
        _deployAPI3Oracle();

        address priceOracleAggregatorProxyAddress = Upgrades.deployUUPSProxy(
            "PriceOracleAggregator.sol", abi.encodeCall(PriceOracleAggregator.initialize, (admin))
        );
        priceOracleAggregator = PriceOracleAggregator(payable(priceOracleAggregatorProxyAddress));

        IOracleSource[] memory oracles = new IOracleSource[](2);
        oracles[0] = api3Oracle;
        oracles[1] = pythOracle;

        console.log("PriceOracleAggregator deployed at", address(priceOracleAggregator));

        return priceOracleAggregator;
    }

    function _deployPythOracle() internal {
        address[] memory underlyingTokens = new address[](0);
        bytes32[] memory priceFeedIds = new bytes32[](0);

        pythOracle = new PythOracle(
            admin, BLAZE_TESTNET_PYTH_ORACLE_ADDRESS, underlyingTokens, priceFeedIds, PYTH_STALENESS_PERIOD
        );
        console.log("PythOracle deployed at", address(pythOracle));
    }

    function _deployAPI3Oracle() internal {
        address[] memory underlyingTokens = new address[](0);
        address[] memory api3ProxyAddresses = new address[](0);

        api3Oracle = new API3Oracle(admin, underlyingTokens, api3ProxyAddresses);
        console.log("API3Oracle deployed at", address(api3Oracle));
    }

    // @notice -  Only call this when market has significant liquidity to prevent donation attack
    function setCollateralFactors(address[] memory cTokens, uint256[] memory collateralFactors) public {
        for (uint256 i = 0; i < cTokens.length; i++) {
            comptroller._setCollateralFactor(CToken(cTokens[i]), collateralFactors[i]);
        }
    }
}
