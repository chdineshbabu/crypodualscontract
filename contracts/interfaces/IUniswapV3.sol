// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @notice Minimal subset of the Uniswap V3 SwapRouter02 used by TicketContract.
/// @dev Robinhood Chain mainnet SwapRouter02: 0xcaf681a66d020601342297493863e78c959e5cb2.
///      SwapRouter02 params intentionally have NO `deadline` field (unlike the original
///      v3-periphery SwapRouter); deadline is enforced by the caller (TicketContract
///      checks `block.timestamp <= deadline` before swapping).
interface IV3SwapRouter {
    struct ExactOutputParams {
        // V3 exact-output path, encoded in REVERSE order:
        // abi.encodePacked(tokenOut, fee, [midToken, fee, ...], tokenIn)
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little of the input token as possible for `amountOut` of the
    ///         output token. Pulls the required input from `msg.sender` (this contract)
    ///         via the swap callback, capped at `amountInMaximum`.
    /// @return amountIn The amount of the input token actually spent.
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);

    /// @notice Refunds any ETH held by the router to `msg.sender`. Paired with
    ///         `exactOutput` (via `multicall`) when paying with native ETH, to return
    ///         the unspent portion of the forwarded value.
    function refundETH() external payable;

    /// @notice Batches router calls in a single transaction (used to pair `exactOutput`
    ///         with `refundETH` for ETH-in swaps). Returns each call's raw return data.
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}

/// @notice Minimal Chainlink price-feed interface for the optional oracle sanity bound.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
