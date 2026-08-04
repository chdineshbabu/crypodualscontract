// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IUniswapV3.sol";

/// @dev Test-only Chainlink aggregator. Configurable price, decimals, freshness and
///      round-completeness so the oracle bound (deviation + staleness) can be exercised.
contract MockAggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 answer_, uint256 updatedAt_) {
        _decimals = decimals_;
        _answer = answer_;
        _updatedAt = updatedAt_;
        _roundId = 1;
        _answeredInRound = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    /// @notice Force an incomplete round (answeredInRound < roundId).
    function setIncompleteRound() external {
        _roundId = 2;
        _answeredInRound = 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}
