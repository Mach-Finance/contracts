// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracleSource} from "../IOracleSource.sol";
import {IstS} from "./IstS.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BeetsStakedSPythOracle is IOracleSource, Ownable2Step {
    uint256 public constant PRICE_SCALE = 36;
    uint256 public constant S_DECIMALS = 18;

    address public constant stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address public constant pyth = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    bytes32 public constant S_PRICE_FEED_ID = 0xf490b178d0c85683b7a0f2388b40af2e6f7c90cbe0f96b31f315f08d0e5a2d6d;

    event StakedSPriceFeedIdSet(bytes32 indexed priceFeedId);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);

    // @notice Stale price threshold in seconds
    uint256 public stalePriceThreshold;

    constructor(address _owner, uint256 _stalePriceThreshold) Ownable(_owner) {
        _setPriceFeedId(S_PRICE_FEED_ID);
        _setStalePriceThreshold(_stalePriceThreshold);
    }

    function _setPriceFeedId(bytes32 priceFeedId) internal {
        require(priceFeedId != bytes32(0), "PythOracle: Price feed id cannot be zero");
        // Attempt to check if the Pyth price feed is valid, ignore return value, should revert if invalid
        IPyth(pyth).getPriceUnsafe(priceFeedId);
        emit StakedSPriceFeedIdSet(priceFeedId);
    }

    function getPrice(address token) external view returns (uint256, bool) {
        if (token != stS) return (0, false);

        // Feed Decimals for $S is +8
        (uint256 price, uint256 feedDecimals) = _getSonicLatestPrice();
        uint256 tokenFeedDecimals = feedDecimals + S_DECIMALS;
        uint256 scaledPrice;

        if (tokenFeedDecimals <= PRICE_SCALE) {
            uint256 scale = 10 ** (PRICE_SCALE - tokenFeedDecimals);
            scaledPrice = price * scale;
        } else {
            uint256 scale = 10 ** (tokenFeedDecimals - PRICE_SCALE);
            scaledPrice = price / scale;
        }

        // Calculate price of stS based on exchange rate
        uint256 stSPrice = _calculateStSPrice(scaledPrice);

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

    function _getSonicLatestPrice() internal view returns (uint256, uint256) {
        PythStructs.Price memory pythPrice = IPyth(pyth).getPriceUnsafe(S_PRICE_FEED_ID);

        // Ensure price is non-negative and expo is non-positive
        // Otherwise, underflow will occur (fatal issue)
        if (pythPrice.price < 0 || pythPrice.expo > 0) return (0, 0);

        // Ensure price is not stale (https://github.com/pyth-network/pyth-sdk-solidity/blob/c24b3e0173a5715c875ae035c20e063cb900f481/AbstractPyth.sol#L54)
        if (block.timestamp - stalePriceThreshold > pythPrice.publishTime) {
            return (0, 0);
        }

        uint256 price = uint256(uint64(pythPrice.price));
        uint256 expo = uint256(uint32(-pythPrice.expo));

        return (price, expo);
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
