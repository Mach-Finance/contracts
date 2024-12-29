// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {BaseTest} from "./BaseTest.t.sol";
import {SupportMarketHelper} from "../script/helpers/SupportMarketHelper.sol";
import {Unitroller} from "../src/Unitroller.sol";
import {Comptroller} from "../src/Comptroller.sol";
import {CErc20} from "../src/CErc20.sol";
import {SimplePriceOracle} from "./mocks/SimplePriceOracle.sol";
import {CErc20Delegator} from "../src/CErc20Delegator.sol";
import {CToken} from "../src/CToken.sol";
import {CSonic} from "../src/CSonic.sol";

contract SupportMarketHelperTest is BaseTest {
    Unitroller public unitroller;
    Comptroller public comptrollerProxy;

    SupportMarketHelper public smHelper;

    function setUp() public {
        _deployBaselineContracts();

        vm.startPrank(admin);
        unitroller = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        comptrollerProxy = Comptroller(payable(address(unitroller)));

        // Redeploy cTokens with new unitroller address
        redeployCTokens();

        vm.assertEq(address(comptrollerProxy), address(unitroller));
        vm.assertNotEq(address(comptroller), address(unitroller));

        smHelper = new SupportMarketHelper(payable(address(comptrollerProxy)), admin);

        // Hardcode price oracle to ensure minting works
        SimplePriceOracle simplePriceOracle = new SimplePriceOracle();
        comptrollerProxy._setPriceOracle(simplePriceOracle);
        simplePriceOracle.setUnderlyingPrice(CToken(address(cWethDelegator)), 3500 * 10 ** (36 - weth.decimals()));
        simplePriceOracle.setUnderlyingPrice(CToken(address(cUsdcDelegator)), 1 * 10 ** (36 - usdc.decimals()));
        simplePriceOracle.setUnderlyingPrice(CToken(address(cWbtcDelegator)), 1 * 10 ** (36 - wbtc.decimals()));
        vm.stopPrank();
    }

    function redeployCTokens() internal {
        uint256 initialExchangeRateMantissaForWeth = 10 ** (18 + weth.decimals() - cTokenDecimals) / 50;
        uint256 initialExchangeRateMantissaForWbtc = 10 ** (18 + wbtc.decimals() - cTokenDecimals) / 50;
        uint256 initialExchangeRateMantissaForUsdc = 10 ** (18 + usdc.decimals() - cTokenDecimals) / 50;

        // Redeploy tokens
        cWethDelegator = new CErc20Delegator(
            address(weth), // underlying
            comptrollerProxy, // comptroller
            interestRateModel, // interestRateModel
            initialExchangeRateMantissaForWeth, // initialExchangeRateMantissa
            "Compound Wrapped Ethereum", // name
            "cWETH", // symbol
            cTokenDecimals, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );

        cWbtcDelegator = new CErc20Delegator(
            address(wbtc), // underlying
            comptrollerProxy, // comptroller
            interestRateModel, // interestRateModel
            initialExchangeRateMantissaForWbtc, // initialExchangeRateMantissa
            "Compound Wrapped Bitcoin", // name
            "cWBTC", // symbol
            cTokenDecimals, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );

        cUsdcDelegator = new CErc20Delegator(
            address(usdc), // underlying
            comptrollerProxy, // comptroller
            interestRateModel, // interestRateModel
            initialExchangeRateMantissaForUsdc, // initialExchangeRateMantissa
            "Compound USDC", // name
            "cUSDC", // symbol
            cTokenDecimals, // decimals
            payable(admin), // admin
            address(cErc20Delegate), // implementation
            "" // becomeImplementationData
        );
    }

    function test_supportMarketSonic() public {
        // 0. Mint SONIC to admin
        uint256 amountToMint = 1e3 * 10 ** nativeTokenDecimals;
        vm.deal(address(admin), amountToMint);

        vm.startPrank(admin);

        // 1. Set pending admin to `smHelper`
        unitroller._setPendingAdmin(address(smHelper));
        assertEq(unitroller.pendingAdmin(), address(smHelper), "Pending admin should be smHelper");

        // 2. Call supportCErc20Market for cSonic
        smHelper.supportCSonicMarket{value: amountToMint}(cSonic);

        // Check totalSupply == cSonic.balanceOf(address(0))
        assertGt(cSonic.totalSupply(), 0, "Total supply must be > 0 for cSonic");
        assertEq(
            cSonic.totalSupply(),
            cSonic.balanceOf(address(0)),
            "Total supply must equal the balance of address(0) for cSonic"
        );

        // After the function, pendingAdmin should be reset back to `admin`
        assertEq(unitroller.pendingAdmin(), admin, "Pending admin should revert to original admin");

        // 3. Accept admin role
        unitroller._acceptAdmin();
        assertEq(unitroller.admin(), admin, "Unitroller admin should be set to `admin`");

        // 4. The cSonic market should be listed
        (bool isListed, uint256 cf) = comptrollerProxy.markets(address(cSonic));
        assertTrue(isListed, "cSonic Market not listed");
        assertEq(cf, 0, "Collateral factor should be zero for cSonic");

        vm.stopPrank();
    }

    /// @dev Basic success scenario (from your snippet)
    function test_supportMarketWeth() public {
        // 0. Mint WETH to admin
        uint256 amountToBurn = 1e3 * 10 ** weth.decimals();
        vm.startPrank(admin);
        weth.mint(address(admin), amountToBurn);

        // 1. Set pending admin to `smHelper`
        unitroller._setPendingAdmin(address(smHelper));
        assertEq(unitroller.pendingAdmin(), address(smHelper));

        // 2. Provide allowance to smHelper
        weth.approve(address(smHelper), amountToBurn);

        // 3. Call supportCErc20Market
        smHelper.supportCErc20Market(CErc20(address(cWethDelegator)), amountToBurn);

        // Check totalSupply == _cToken.balanceOf(address(this))
        assertGt(cWethDelegator.totalSupply(), 0, "Total supply must be greater than 0");
        assertEq(
            cWethDelegator.totalSupply(),
            cWethDelegator.balanceOf(address(0)),
            "Total supply must be equal to balance of address(0)"
        );

        // After the function, pendingAdmin should be reset back to `admin`
        assertEq(unitroller.pendingAdmin(), admin);

        // Accept admin role
        unitroller._acceptAdmin();
        assertEq(unitroller.admin(), admin);

        // The cToken market should be listed
        (bool isListed, uint256 cf) = comptrollerProxy.markets(address(cWethDelegator));
        assertTrue(isListed, "Market not listed");
        assertEq(cf, 0, "Collateral factor should be zero");

        vm.stopPrank();
    }

    /// @dev Test supporting USDC market
    function test_supportMarketUsdc() public {
        vm.startPrank(admin);
        uint256 amountToBurn = 500e6; // e.g. 500 USDC

        // Mint USDC to admin
        usdc.mint(admin, amountToBurn);

        // 1. Set pending admin to `smHelper`
        unitroller._setPendingAdmin(address(smHelper));
        assertEq(unitroller.pendingAdmin(), address(smHelper));

        // 2. Provide allowance to smHelper
        usdc.approve(address(smHelper), amountToBurn);

        // 3. Call supportCErc20Market
        smHelper.supportCErc20Market(CErc20(address(cUsdcDelegator)), amountToBurn);

        // Check totalSupply == _cToken.balanceOf(address(this))
        assertGt(cUsdcDelegator.totalSupply(), 0, "Total supply must be greater than 0");
        assertEq(
            cUsdcDelegator.totalSupply(),
            cUsdcDelegator.balanceOf(address(0)),
            "Total supply must be equal to balance of address(0)"
        );

        // pendingAdmin -> admin
        assertEq(unitroller.pendingAdmin(), admin);
        unitroller._acceptAdmin();
        assertEq(unitroller.admin(), admin);

        // The cToken market should be listed
        (bool isListed, uint256 cf) = comptrollerProxy.markets(address(cUsdcDelegator));
        assertTrue(isListed, "USDC market not listed");
        assertEq(cf, 0, "Collateral factor should be zero");

        vm.stopPrank();
    }

    /// @dev Revert if not called by owner
    function test_revert_NotOwnerCallsSupportMarket() public {
        uint256 amountToBurn = 1e3 * 10 ** weth.decimals();
        // Setup enough WETH in some non-owner account
        address attacker = address(0xbad);
        weth.mint(attacker, amountToBurn);
        vm.deal(attacker, amountToBurn);

        // attacker tries to call supportCErc20Market
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        smHelper.supportCErc20Market(CErc20(address(cWethDelegator)), amountToBurn);

        // attacker tries to call supportCSonicMarket
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        smHelper.supportCSonicMarket{value: amountToBurn}(cSonic);
    }

    /// @dev Revert if pending admin is not the smHelper
    function test_revert_InvalidPendingAdmin() public {
        vm.startPrank(admin);

        // We never set pending admin to the smHelper
        // So this should revert
        uint256 amountToBurn = 1000e18;
        weth.mint(admin, amountToBurn);
        vm.deal(admin, amountToBurn);

        weth.approve(address(smHelper), amountToBurn);

        vm.expectRevert("Only pending admin can support a market");
        smHelper.supportCErc20Market(CErc20(address(cWethDelegator)), amountToBurn);

        vm.expectRevert("Only pending admin can support a market");
        smHelper.supportCSonicMarket{value: amountToBurn}(cSonic);

        vm.stopPrank();
    }

    /// @dev Revert if _underlyingBurnAmount == 0
    function test_revert_ZeroBurnAmount() public {
        vm.startPrank(admin);

        unitroller._setPendingAdmin(address(smHelper));
        // Approve 0
        weth.approve(address(smHelper), 0);

        vm.expectRevert("Underlying burn amount must be greater than 0");
        smHelper.supportCErc20Market(CErc20(address(cWethDelegator)), 0);

        vm.expectRevert("Underlying burn amount must be greater than 0");
        smHelper.supportCSonicMarket{value: 0}(cSonic);

        vm.stopPrank();
    }

    /// @dev Revert if cToken address == 0
    function test_revert_ZeroCToken() public {
        vm.startPrank(admin);

        uint256 amountToBurn = 1000;
        vm.deal(admin, amountToBurn);

        unitroller._setPendingAdmin(address(smHelper));
        vm.expectRevert("CToken address cannot be 0");
        smHelper.supportCErc20Market(CErc20(address(0)), 1000);

        vm.expectRevert("CSonic address cannot be 0");
        smHelper.supportCSonicMarket{value: 1000}(CSonic(payable(address(0))));

        vm.stopPrank();
    }

    /// @dev Test the escape hatch _setPendingAdminToOwner
    function test_setPendingAdminToOwner_Success() public {
        // 1. Make smHelper the admin
        vm.prank(admin);
        unitroller._setPendingAdmin(address(smHelper));

        // Simulate smHelper calling _acceptAdmin
        vm.prank(address(smHelper));
        unitroller._acceptAdmin();
        // Now smHelper is actually admin of the unitroller

        // 2. Call _setPendingAdminToOwner
        vm.startPrank(admin);
        smHelper._setPendingAdminToOwner();

        // Now pending admin should be admin
        assertEq(unitroller.pendingAdmin(), admin);

        // 3. Call _acceptAdmin
        unitroller._acceptAdmin();
        assertEq(unitroller.admin(), admin);

        vm.stopPrank();
    }

    /// @dev Revert if smHelper isn't actually the admin
    function test_setPendingAdminToOwner_RevertNotAdmin() public {
        // If we never made the smHelper the admin, it can't setPendingAdminToOwner
        vm.startPrank(admin);
        vm.expectRevert("Contract must be admin");
        smHelper._setPendingAdminToOwner();
        vm.stopPrank();
    }

    /// @dev Test sweepUnderlying when there is a nonzero balance
    function test_sweepUnderlying_Success() public {
        // Mint WETH to the smHelper contract
        uint256 sweepAmount = 100e18;
        vm.startPrank(admin);
        weth.mint(address(smHelper), sweepAmount);
        vm.stopPrank();

        // Check that the smHelper has the tokens
        assertEq(weth.balanceOf(address(smHelper)), sweepAmount);

        // Now call sweep from owner
        vm.startPrank(admin);
        smHelper.sweepUnderlying(weth);

        // Verify the tokens are swept to admin
        assertEq(weth.balanceOf(admin), sweepAmount, "Owner should have swept tokens");
        assertEq(weth.balanceOf(address(smHelper)), 0, "Helper should have no tokens left");
        vm.stopPrank();
    }

    /// @dev Revert if not called by owner
    function test_sweepUnderlying_RevertNotOwner() public {
        uint256 sweepAmount = 100e18;
        vm.startPrank(admin);
        weth.mint(address(smHelper), sweepAmount);
        vm.stopPrank();

        // Attempt to sweep from a random user
        address attacker = address(0xbad);
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        smHelper.sweepUnderlying(weth);
        vm.stopPrank();
    }
}
