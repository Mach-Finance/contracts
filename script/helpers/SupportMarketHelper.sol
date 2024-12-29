// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Comptroller} from "../../src/Comptroller.sol";
import {Unitroller} from "../../src/Unitroller.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CErc20} from "../../src/CErc20.sol";
import {CToken} from "../../src/CToken.sol";
import {CSonic} from "../../src/CSonic.sol";

/**
 * @author MachFi
 * @notice Helper contract to support a market, ensures security against sandwich attacks
 * @dev Prevents inflation / donation attacks on Compound v2 forks that happen when supporting a market
 */
contract SupportMarketHelper is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 constant NO_ERROR = 0;

    Comptroller immutable comptroller;
    Unitroller immutable unitroller;

    constructor(address payable _comptroller, address _owner) Ownable(_owner) {
        comptroller = Comptroller(_comptroller);
        unitroller = Unitroller(_comptroller);
    }

    // Prevents inflation / donation attacks on Compound v2 forks that happen when supporting a cSonic market
    // 1. Support market
    // 2. Ensure CF=0
    // 3. Mint cTokens, burn them to make sure total supply doesn't go to zero
    function supportCSonicMarket(CSonic _cSonic) external payable onlyOwner nonReentrant {
        // Check if pending admin is this contract
        require(unitroller.pendingAdmin() == address(this), "Only pending admin can support a market");

        // Accept admin role
        require(unitroller._acceptAdmin() == NO_ERROR, "Failed to accept admin role");

        // Check if market is already listed
        (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(_cSonic));
        require(!isListed, "Market already listed");
        require(msg.value > 0, "Underlying burn amount must be greater than 0");
        require(address(_cSonic) != address(0), "CSonic address cannot be 0");

        string memory symbol = _cSonic.symbol();
        require(keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("cSonic")), "Symbol must be cSonic");
        /// END OF PRE-CHECKS ///

        // Support market
        require(comptroller._supportMarket(CToken(address(_cSonic))) == NO_ERROR, "Failed to support market");

        // Check totalSupply is zero (first mint)
        require(_cSonic.totalSupply() == 0, "Total supply must be 0");

        // Mint cSonic
        _cSonic.mint{value: msg.value}();

        // Check totalSupply == _cSonic.balanceOf(address(this))
        require(
            _cSonic.totalSupply() == _cSonic.balanceOf(address(this)),
            "Total supply must be equal to balance of this contract"
        );

        // Burn minted cSonic
        require(_cSonic.transfer(address(0), _cSonic.balanceOf(address(this))), "Failed to burn cTokens");
        require(
            _cSonic.balanceOf(address(0)) == _cSonic.totalSupply(),
            "Total supply must be equal to balance of address(0)"
        );
        //// POST CHECKS ////

        // Make Unitroller admin the owner
        require(unitroller._setPendingAdmin(owner()) == NO_ERROR, "Failed to set pending admin");

        // Check if market is listed and CF is 0
        (isListed, collateralFactorMantissa) = comptroller.markets(address(_cSonic));

        // "owner" needs to accept admin role after this transaction
        require(unitroller.pendingAdmin() == owner(), "invalid pending admin");
        require(collateralFactorMantissa == 0, "CF must be 0");
        require(isListed, "Market must be listed");
    }

    // Prevents inflation / donation attacks on Compound v2 forks that happen when supporting a market
    // 1. Support market
    // 2. Ensure CF=0
    // 3. Mint cTokens, burn them to make sure total supply doesn't go to zero
    function supportCErc20Market(CErc20 _cToken, uint256 _underlyingBurnAmount) external onlyOwner nonReentrant {
        // Check if pending admin is this contract
        require(unitroller.pendingAdmin() == address(this), "Only pending admin can support a market");

        // Accept admin role
        require(unitroller._acceptAdmin() == NO_ERROR, "Failed to accept admin role");

        // Check if market is already listed
        (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(_cToken));
        require(!isListed, "Market already listed");
        require(_underlyingBurnAmount > 0, "Underlying burn amount must be greater than 0");
        require(address(_cToken) != address(0), "CToken address cannot be 0");

        address underlying = _cToken.underlying();
        require(underlying != address(0), "Underlying token address cannot be 0");

        /// Support Market operations ///
        // Assumes allowance has been set by msg.sender, else fails
        IERC20 underlyingToken = IERC20(underlying);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _underlyingBurnAmount);

        // Support market
        require(comptroller._supportMarket(CToken(address(_cToken))) == NO_ERROR, "Failed to support market");

        // ERC20 Approve cToken, to mint cTokens
        underlyingToken.approve(address(_cToken), _underlyingBurnAmount);

        // Check totalSupply is zero (first mint)
        require(_cToken.totalSupply() == 0, "Total supply must be 0");

        // Mint cTokens
        require(_cToken.mint(_underlyingBurnAmount) == NO_ERROR, "Failed to mint cTokens");

        // Check totalSupply == _cToken.balanceOf(address(this))
        require(
            _cToken.totalSupply() == _cToken.balanceOf(address(this)),
            "Total supply must be equal to balance of this contract"
        );

        // Burn cTokens
        require(_cToken.transfer(address(0), _cToken.balanceOf(address(this))), "Failed to burn cTokens");
        require(
            _cToken.balanceOf(address(0)) == _cToken.totalSupply(),
            "Total supply must be equal to balance of address(0)"
        );
        /// END Support Market operations ///

        //// POST CHECKS ////

        // Make Unitroller admin the owner
        require(unitroller._setPendingAdmin(owner()) == NO_ERROR, "Failed to set pending admin");

        // Check if market is listed and CF is 0
        (isListed, collateralFactorMantissa) = comptroller.markets(address(_cToken));

        // "owner" needs to accept admin role after this transaction
        require(unitroller.pendingAdmin() == owner(), "invalid pending admin");
        require(collateralFactorMantissa == 0, "CF must be 0");
        require(isListed, "Market must be listed");
    }

    // Escape hatch function to revoke unitroller admin role to owner
    function _setPendingAdminToOwner() external onlyOwner {
        require(unitroller.admin() == address(this), "Contract must be admin");
        unitroller._setPendingAdmin(owner());
        require(unitroller.pendingAdmin() == owner(), "Pending admin must be owner");
    }

    // Escape hatch function to sweep underlying tokens
    function sweepUnderlying(IERC20 _underlyingToken) external onlyOwner {
        _underlyingToken.safeTransfer(owner(), _underlyingToken.balanceOf(address(this)));
    }
}
