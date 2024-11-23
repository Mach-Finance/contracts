// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "../src/CErc20Delegator.sol";
import "../src/CErc20Delegate.sol";
import "../src/ComptrollerInterface.sol";
import "../src/InterestRateModel.sol";
import "../src/Comptroller.sol";
import "../src/JumpRateModelV2.sol";
import "./BaseTest.t.sol";

contract CTokenTest is BaseTest {
    function setUp() public {
        _deployBaselineContracts();
    }

    function test_sweepNative() public {
        vm.deal(address(cWbtcDelegator), 100 ether);
        vm.prank(admin);
        CErc20Delegate(address(cWbtcDelegator)).sweepNative();

        assertEq(address(cWbtcDelegator).balance, 0 ether);
        assertEq(address(admin).balance, 100 ether);
    }

    function test_supplyCap() public {
        deal(address(underlyingErc20Token), admin, 1000 ether);
        vm.prank(admin);

        CToken[] memory cTokens = new CToken[](1);
        cTokens[0] = CToken(address(cWbtcDelegator));
        uint256[] memory newSupplyCaps = new uint256[](1);
        newSupplyCaps[0] = 100 ether;
        comptroller._setMarketSupplyCaps(cTokens, newSupplyCaps);

        // Approve allowance
        vm.prank(admin);
        underlyingErc20Token.approve(address(cWbtcDelegator), type(uint256).max);

        vm.prank(admin);
        cWbtcDelegator.mint(99 ether);

        vm.expectRevert("market supply cap reached");
        vm.prank(admin);
        cWbtcDelegator.mint(1.5 ether);
    }
}
