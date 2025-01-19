// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracleSource} from "../IOracleSource.sol";
import {IstS} from "./IstS.sol";
import {IApi3ReaderProxy} from "@api3/contracts/interfaces/IApi3ReaderProxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// stS: https://sonicscan.org/address/0xe5da20f15420ad15de0fa650600afc998bbe3955
contract BeetsStakedSAPI3Oracle is IOracleSource, Ownable2Step {
    uint256 public constant PRICE_SCALE = 36;
    uint256 public constant API3_SCALE_FACTOR = 18;
    uint256 public constant S_DECIMALS = 18;
    address public constant stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;

    event StakedSAPI3ProxyAddressSet(address indexed api3ProxyAddress);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);

    // @notice Stale price threshold in seconds
    uint256 public stalePriceThreshold;
    IApi3ReaderProxy public sApi3Proxy;

    constructor(address _owner, address _sApi3Proxy) Ownable(_owner) {
        _setStakedSAPI3ProxyAddress(_sApi3Proxy);

        // Attempt to check if the API3 proxy address is valid, ignore return value, should revert if invalid
        sApi3Proxy.read();
        _setStalePriceThreshold(24 hours);
    }

    /**
     * @notice Get the price of stS token from API3 proxy
     * @dev Returns (0, false) if token is not stS or if price is invalid
     * @dev Price is calculated by getting the price of $S from API3 and multiplying by the stS/S exchange rate
     * @param token The address of the token to get the price for
     * @return price Price of stS in USD as an unsigned integer scaled up by 10 ^ (36 - token decimals)
     * @return isValid Boolean indicating if the price is valid
     */
    function getPrice(address token) external view returns (uint256 price, bool isValid) {
        if (token != stS) return (0, false);

        // Get price of $S first here
        uint256 price = _getSonicLatestPrice();

        // Calculate price of stS based on exchange rate
        uint256 stSPrice = _calculateStSPrice(price);

        if (stSPrice == 0) {
            return (0, false);
        }

        return (stSPrice, true);
    }

    /**
     * @notice Calculate price of stS based on exchange rate
     * @param sonicPrice Price of $S in USD
     * @return stSPrice Price of stS in USD
     */
    function _calculateStSPrice(uint256 sonicPrice) internal view returns (uint256 stSPrice) {
        uint256 rate = IstS(stS).getRate();
        uint8 stSDecimals = ERC20(stS).decimals();
        stSPrice = rate * sonicPrice / 10 ** (18 + stSDecimals - S_DECIMALS);
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
    function setStakedSAPI3ProxyAddress(address api3ProxyAddress) public onlyOwner {
        _setStakedSAPI3ProxyAddress(api3ProxyAddress);
    }

    function _setStakedSAPI3ProxyAddress(address api3ProxyAddress) internal {
        require(api3ProxyAddress != address(0), "API3Oracle: API3 proxy address cannot be zero");
        // Attempt to check if the API3 proxy address is valid, ignore return value, should revert if invalid
        IApi3ReaderProxy(api3ProxyAddress).read();
        sApi3Proxy = IApi3ReaderProxy(api3ProxyAddress);
        emit StakedSAPI3ProxyAddressSet(api3ProxyAddress);
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
