// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FaucetERC20 is ERC20 {
    uint8 public tokenDecimals;

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        tokenDecimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}
