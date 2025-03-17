// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracleSource} from "../IOracleSource.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// wOS: https://sonicscan.org/token/0x9f0df7799f6fdad409300080cff680f5a23df4b1#readProxyContract
contract OriginSonicPythOracle is IOracleSource, Ownable2Step {
    uint256 public constant PRICE_SCALE = 36;
    uint256 public constant S_DECIMALS = 18;
    address public constant wOS = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    address public constant pyth = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    bytes32 public constant S_PRICE_FEED_ID = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    event SonicPriceFeedIdSet(bytes32 indexed priceFeedId);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);

    // @notice Stale price threshold in seconds
    uint256 public stalePriceThreshold;
    bytes32 public sonicPriceFeedId;

    constructor(address _owner, uint256 _stalePriceThreshold) Ownable(_owner) {
        _setSonicPriceFeedId(S_PRICE_FEED_ID);
        _setStalePriceThreshold(_stalePriceThreshold);
    }

    /**
     * @notice Get the price of wOS token from Pyth
     * @dev Returns (0, false) if token is not wOS or if price is invalid
     * @dev Price is calculated by getting the price of $S from Pyth and multiplying by the wOS/S exchange rate
     * @param token The address of the token to get the price for
     * @return price Price of wOS in USD as an unsigned integer scaled up by 10 ^ (36 - token decimals)
     * @return isValid Boolean indicating if the price is valid
     */
    function getPrice(address token) external view returns (uint256, bool) {
        if (token != wOS) return (0, false);

        // Feed Decimals for $S is +8
        (uint256 price, uint256 feedDecimals) = _getSonicLatestPrice();
        
        if (price == 0) {
            return (0, false);
        }
        
        uint256 tokenFeedDecimals = feedDecimals + S_DECIMALS;
        uint256 scaledPrice;

        if (tokenFeedDecimals <= PRICE_SCALE) {
            uint256 scale = 10 ** (PRICE_SCALE - tokenFeedDecimals);
            scaledPrice = price * scale;
        } else {
            uint256 scale = 10 ** (tokenFeedDecimals - PRICE_SCALE);
            scaledPrice = price / scale;
        }

        // Calculate price of wOS based on exchange rate
        uint256 wOSPrice = _calculatewOSPrice(scaledPrice);

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

    function _getSonicLatestPrice() internal view returns (uint256, uint256) {
        PythStructs.Price memory pythPrice = IPyth(pyth).getPriceUnsafe(sonicPriceFeedId);

        // Ensure price is non-negative and expo is non-positive
        // Otherwise, underflow will occur (fatal issue)
        if (pythPrice.price < 0 || pythPrice.expo > 0) return (0, 0);

        // Ensure price is not stale
        if (block.timestamp - stalePriceThreshold > pythPrice.publishTime) {
            return (0, 0);
        }

        uint256 price = uint256(uint64(pythPrice.price));
        uint256 expo = uint256(uint32(-pythPrice.expo));

        return (price, expo);
    }

    /// Admin functions to set Pyth price feed ID for Sonic token ////
    function setSonicPriceFeedId(bytes32 priceFeedId) external onlyOwner {
        _setSonicPriceFeedId(priceFeedId);
    }

    function _setSonicPriceFeedId(bytes32 priceFeedId) internal {
        require(priceFeedId != bytes32(0), "PythOracle: Price feed id cannot be zero");
        // Attempt to check if the Pyth price feed is valid, ignore return value, should revert if invalid
        IPyth(pyth).getPriceUnsafe(priceFeedId);
        sonicPriceFeedId = priceFeedId;
        emit SonicPriceFeedIdSet(priceFeedId);
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
        require(_stalePriceThreshold > 0, "PythOracle: Stale price threshold must be greater than 0");
        stalePriceThreshold = _stalePriceThreshold;
        emit StalePriceThresholdSet(_stalePriceThreshold);
    }
} 