// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {CToken} from "../../CToken.sol";
import {CErc20} from "../../CErc20.sol";
import {PriceOracle} from "../../PriceOracle.sol";
import {IOracleSource} from "../IOracleSource.sol";

contract PythOracle is IOracleSource, Ownable2Step {
    uint256 public constant PRICE_SCALE = 36;
    uint256 public constant NATIVE_DECIMALS = 18;
    address public constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event UnderlyingTokenPriceFeedSet(address indexed token, bytes32 priceFeedId);
    event StalePriceThresholdSet(uint256 indexed stalePriceThreshold);

    IPyth public immutable pyth;

    // @notice Stale price threshold in seconds
    uint256 public stalePriceThreshold;
    // @notice Mapping between underlying token and Pyth price feed id
    mapping(address => bytes32) public priceFeedIds;

    constructor(
        address _owner,
        address _pyth,
        address[] memory _underlyingTokens,
        bytes32[] memory _priceFeedIds,
        uint256 _stalePriceThreshold
    ) Ownable(_owner) {
        require(
            _underlyingTokens.length == _priceFeedIds.length, "PythOracle: Lengths of tokens and price feed must match"
        );

        pyth = IPyth(_pyth);

        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            _setPriceFeedId(_underlyingTokens[i], _priceFeedIds[i]);
        }

        _setStalePriceThreshold(_stalePriceThreshold);
    }

    function _setPriceFeedId(address underlyingToken, bytes32 priceFeedId) internal {
        require(priceFeedId != bytes32(0), "PythOracle: Price feed id cannot be zero");
        // Attempt to check if the Pyth price feed is valid, ignore return value, should revert if invalid
        pyth.getPriceUnsafe(priceFeedId);

        priceFeedIds[underlyingToken] = priceFeedId;
        emit UnderlyingTokenPriceFeedSet(underlyingToken, priceFeedId);
    }

    function setPriceFeedId(address underlyingToken, bytes32 priceFeedId) public onlyOwner {
        _setPriceFeedId(underlyingToken, priceFeedId);
    }

    function bulkSetPriceFeedIds(address[] memory _underlyingTokens, bytes32[] memory _priceFeedIds)
        external
        onlyOwner
    {
        require(
            _underlyingTokens.length == _priceFeedIds.length, "PythOracle: Lengths of tokens and price feed must match"
        );

        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            _setPriceFeedId(_underlyingTokens[i], _priceFeedIds[i]);
        }
    }

    /**
     * @notice Get the price of a token from Pyth oracle
     * @param token The address of the token to get the price for
     * @return The price of the token in USD as an unsigned integer scaled up by 10 ^ (36 - token decimals)
     * @return A boolean indicating if the price is valid
     */
    function getPrice(address token) external view returns (uint256, bool) {
        (uint256 price, uint256 feedDecimals) = _getLatestPrice(token);
        uint256 decimals = _getDecimals(token);

        uint256 scaledPrice;

        // Number of decimals determine multiplication / division for scaling
        if (feedDecimals + decimals <= PRICE_SCALE) {
            uint256 scale = 10 ** (PRICE_SCALE - feedDecimals - decimals);
            scaledPrice = price * scale;
        } else {
            uint256 scale = 10 ** (feedDecimals + decimals - PRICE_SCALE);
            scaledPrice = price / scale;
        }

        if (scaledPrice == 0) {
            return (0, false);
        }

        return (scaledPrice, true);
    }

    function _getLatestPrice(address token) internal view returns (uint256, uint256) {
        // Return 0 if price feed id is not set, reverts are handled by caller
        if (priceFeedIds[token] == bytes32(0)) return (0, 0);

        bytes32 priceFeedId = priceFeedIds[token];
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);

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

    function _getDecimals(address token) internal view returns (uint256) {
        if (token == NATIVE_ASSET) {
            return NATIVE_DECIMALS;
        } else {
            return ERC20(token).decimals();
        }
    }

    /**
     * @notice Set stale price threshold, only callable by owner
     * @param _stalePriceThreshold The new stale price threshold in seconds
     */
    function setStalePriceThreshold(uint256 _stalePriceThreshold) external onlyOwner {
        _setStalePriceThreshold(_stalePriceThreshold);
    }

    function _setStalePriceThreshold(uint256 _stalePriceThreshold) internal {
        require(_stalePriceThreshold > 0, "PythOracle: Stale price threshold must be greater than 0");
        stalePriceThreshold = _stalePriceThreshold;
        emit StalePriceThresholdSet(_stalePriceThreshold);
    }
}
