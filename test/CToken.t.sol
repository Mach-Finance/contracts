// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "../src/CErc20Delegator.sol";
import "../src/CErc20Delegate.sol";
import "../src/ComptrollerInterface.sol";
import "../src/InterestRateModel.sol";
import "../src/Comptroller.sol";
import "../src/JumpRateModelV2.sol";
import "../src/Oracles/SimplePriceOracle.sol";
import "./BaseTest.t.sol";

contract CTokenTest is BaseTest {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    SimplePriceOracle public priceOracle;

    function setUp() public {
        _deployBaselineContracts();

        vm.startPrank(admin);
        priceOracle = new SimplePriceOracle();

        uint256 btcPrice = 100_000 * 10 ** (36 - wbtc.decimals());
        priceOracle.setUnderlyingPrice(CToken(address(cWbtcDelegator)), btcPrice);

        uint256 sonicPrice = 1 * 10 ** (36 - 18);
        priceOracle.setUnderlyingPrice(CToken(address(cSonic)), sonicPrice);

        comptroller._setPriceOracle(priceOracle);

        comptroller._setCollateralFactor(CToken(address(cWbtcDelegator)), 0.75e18);
        comptroller._setCollateralFactor(CToken(address(cSonic)), 0.5e18);
        vm.stopPrank();
    }

    function test_sweepNative() public {
        vm.deal(address(cWbtcDelegator), 100 ether);
        vm.prank(admin);
        CErc20Delegate(address(cWbtcDelegator)).sweepNative();

        assertEq(address(cWbtcDelegator).balance, 0 ether);
        assertEq(address(admin).balance, 100 ether);
    }

    function test_supplyCap() public {
        deal(address(wbtc), admin, 1000 ether);
        vm.prank(admin);

        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(address(cWbtcDelegator));
        uint256[] memory supplyCaps = new uint256[](1);
        supplyCaps[0] = 100 ether;
        comptroller._setMarketSupplyCaps(cTokens, supplyCaps);

        // Approve allowance
        vm.prank(admin);
        wbtc.approve(address(cWbtcDelegator), type(uint256).max);

        vm.prank(admin);
        cWbtcDelegator.mint(99 ether);

        vm.expectRevert("market supply cap reached");
        vm.prank(admin);
        cWbtcDelegator.mint(1.5 ether);

        // Update supply cap
        uint256[] memory newSupplyCaps = new uint256[](1);
        newSupplyCaps[0] = 150 ether;

        vm.prank(admin);
        comptroller._setMarketSupplyCaps(cTokens, newSupplyCaps);

        vm.prank(admin);
        cWbtcDelegator.mint(1.5 ether);
    }

    function test_interestRateAccrual() public {
        // Setup initial balances (enough to cover minting)
        uint256 wBTCInitialBalance = 100 * (10 ** wbtc.decimals());
        deal(address(wbtc), alice, wBTCInitialBalance);
        deal(address(wbtc), bob, wBTCInitialBalance);
        deal(address(wbtc), charlie, wBTCInitialBalance);

        uint256 sonicInitialBalance = 1e18 ether;
        deal(alice, sonicInitialBalance);
        deal(bob, sonicInitialBalance);
        deal(charlie, sonicInitialBalance);

        uint256 wBTCMintAmount = 10 * (10 ** wbtc.decimals());

        address[] memory marketsToEnter = new address[](2);
        marketsToEnter[0] = address(cWbtcDelegator);
        marketsToEnter[1] = address(cSonic);

        // Supply wBTC
        vm.startPrank(alice);
        wbtc.approve(address(cWbtcDelegator), type(uint256).max);
        cWbtcDelegator.mint(wBTCMintAmount);
        vm.stopPrank();

        // Supply wBTC as collateral
        vm.startPrank(bob);
        wbtc.approve(address(cWbtcDelegator), type(uint256).max);
        cWbtcDelegator.mint(wBTCMintAmount);
        comptroller.enterMarkets(marketsToEnter);
        vm.stopPrank();

        // Supply Sonic as collateral
        vm.startPrank(charlie);
        cSonic.mint{value: 1e6 ether}();
        comptroller.enterMarkets(marketsToEnter);
        vm.stopPrank();

        // Borrow SONIC against wBTC
        vm.prank(bob);
        cSonic.borrow(1e4 ether);

        // Borrow wBTC against Sonic
        vm.prank(charlie);
        cWbtcDelegator.borrow(1 * 1e8);

        // Record initial state
        uint256 initialBTCBorrows = cWbtcDelegator.totalBorrows();
        uint256 initialBTCBorrowIndex = cWbtcDelegator.borrowIndex();

        // Simulate interest accrual daily for one year
        for (uint256 i = 0; i < 365; i++) {
            // Advance 1 day
            vm.warp(block.timestamp + 1 days);

            // Accrue interest
            cWbtcDelegator.accrueInterest();
            cSonic.accrueInterest();
        }

        // Get final state
        uint256 finalBTCBorrows = cWbtcDelegator.totalBorrows();
        uint256 finalBTCBorrowIndex = cWbtcDelegator.borrowIndex();

        // Ensure final borrow index is greater than initial borrow index
        assertGt(finalBTCBorrowIndex, initialBTCBorrowIndex, "BTC borrow index should increase");

        // Calculated via Python notebook
        uint256 expectedBTCBorrowAmount = 101265191;
        uint256 expectedBTCBorrowIndex = 1012044310264898940;

        // 0.38% delta is enough to pass, compared to Python notebook calculations
        assertApproxEqRel(finalBTCBorrows, expectedBTCBorrowAmount, 0.0038e18);
        assertApproxEqRel(finalBTCBorrowIndex, expectedBTCBorrowIndex, 0.0038e18);
    }
}
