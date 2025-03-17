// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracleSource} from "../IOracleSource.sol";
import {IApi3ReaderProxy} from "@api3/contracts/interfaces/IApi3ReaderProxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// wOS: https://sonicscan.org/token/0x9f0df7799f6fdad409300080cff680f5a23df4b1#readProxyContract
contract OriginSonicAPI3Oracle is IOracleSource, Ownable2Step {
    uint256 public constant PRICE_SCALE = 36;
    uint256 public constant API3_SCALE_FACTOR = 18;
    uint256 public constant S_DECIMALS = 18;
    address public constant wOS = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;

    event OriginSonicAPI3ProxyAddressSet(address indexed api3ProxyAddress);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);

    // @notice Stale price threshold in seconds
    uint256 public stalePriceThreshold;
    IApi3ReaderProxy public sApi3Proxy;

    constructor(address _owner, address _sApi3Proxy) Ownable(_owner) {
        _setOriginSonicAPI3ProxyAddress(_sApi3Proxy);

        // Attempt to check if the API3 proxy address is valid, ignore return value, should revert if invalid
        sApi3Proxy.read();
        _setStalePriceThreshold(24 hours);
    }

    /**
     * @notice Get the price of wOS token from API3 proxy
     * @dev Returns (0, false) if token is not wOS or if price is invalid
     * @dev Price is calculated by getting the price of $S from API3 and multiplying by the wOS/S exchange rate
     * @param token The address of the token to get the price for
     * @return price Price of wOS in USD as an unsigned integer scaled up by 10 ^ (36 - token decimals)
     * @return isValid Boolean indicating if the price is valid
     */
    function getPrice(address token) external view returns (uint256 price, bool isValid) {
        if (token != wOS) return (0, false);

        // Get price of $S first here
        uint256 price = _getSonicLatestPrice();

        // Calculate price of wOS based on exchange rate
        uint256 wOSPrice = _calculatewOSPrice(price);

        if (wOSPrice == 0) {
            return (0, false);
        }

        return (wOSPrice, true);
    }

    /**
     * @notice Calculate price of wOS based on exchange rate
     * @param sonicPrice Price of $S in USD
     * @return wOSPrice Price of wOS in USD
     */
    function _calculatewOSPrice(uint256 sonicPrice) internal view returns (uint256 wOSPrice) {
        uint8 wOSDecimals = ERC20(wOS).decimals();
        uint256 rate = IERC4626(wOS).previewRedeem(10 ** wOSDecimals);
        wOSPrice = rate * sonicPrice / 10 ** (18 + wOSDecimals - S_DECIMALS);
    }

    function _getSonicLatestPrice() internal view returns (uint256) {
        // API3 returns prices with scaled up by 1e18 base
        // https://docs.api3.org/dapps/integration/contract-integration.html#using-value
        (int224 price, uint32 timestamp) = sApi3Proxy.read();

        // Ensure price is positive, negative & zero prices are not valid
        if (price <= 0) {
            return 0;
        }

        // ---timestamp---block.timestamp---timestamp + stalePriceThreshold--- [ OK ]
        // ---timestamp---timestamp + stalePriceThreshold---block.timestamp--- [ NOT OK ]
        // Price staleness check, API3 provides 24 hour heartbeat (stalePriceThreshold = 24 hours)
        if (block.timestamp - stalePriceThreshold > timestamp) {
            return 0;
        }

        return uint256(int256(price));
    }

    /// Admin functions to set API3 oracle proxy address for a token ////
    function setOriginSonicAPI3ProxyAddress(address api3ProxyAddress) public onlyOwner {
        _setOriginSonicAPI3ProxyAddress(api3ProxyAddress);
    }

    function _setOriginSonicAPI3ProxyAddress(address api3ProxyAddress) internal {
        require(api3ProxyAddress != address(0), "API3Oracle: API3 proxy address cannot be zero");
        // Attempt to check if the API3 proxy address is valid, ignore return value, should revert if invalid
        IApi3ReaderProxy(api3ProxyAddress).read();
        sApi3Proxy = IApi3ReaderProxy(api3ProxyAddress);
        emit OriginSonicAPI3ProxyAddressSet(api3ProxyAddress);
    }

    /**
     * @notice Set stale price threshold, only callable by owner
     * @param _stalePriceThreshold The new stale price threshold in seconds
     */
    function setStalePriceThreshold(uint256 _stalePriceThreshold) external onlyOwner {
        _setStalePriceThreshold(_stalePriceThreshold);
    }

    /**
     * @notice Internal function to set stale price threshold
     * @param _stalePriceThreshold The new stale price threshold in seconds
     */
    function _setStalePriceThreshold(uint256 _stalePriceThreshold) internal {
        require(_stalePriceThreshold > 0, "API3Oracle: Stale price threshold must be greater than 0");
        stalePriceThreshold = _stalePriceThreshold;
        emit StalePriceThresholdSet(_stalePriceThreshold);
    }
}
