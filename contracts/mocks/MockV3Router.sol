// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IUniswapV3.sol";

/// @dev Test-only stand-in for Uniswap V3 SwapRouter02.
///      Returns a preset `fixedAmountIn` for any exact-output swap (decimals-agnostic)
///      and sends the exact base amount to the recipient. Must be pre-funded with the
///      output (base) token. Ignores the encoded path.
///      - ERC-20 mode (called directly, msg.value == 0): pulls `fixedAmountIn` of tokenIn.
///      - ETH mode (called via multicall with value): keeps `fixedAmountIn` ETH and
///        lets refundETH return the surplus, mirroring SwapRouter02 + refundETH.
contract MockV3Router is IV3SwapRouter {
    address public immutable tokenIn;   // expected input token (e.g. MEME) for ERC-20 mode
    address public immutable tokenOut;  // output token (base, e.g. USDG)
    uint256 public fixedAmountIn;       // input the mock charges per swap
    uint256 public collectedEth;        // ETH the mock has "spent" (kept) across ETH swaps

    constructor(address _tokenIn, address _tokenOut, uint256 _fixedAmountIn) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        fixedAmountIn = _fixedAmountIn;
    }

    function setFixedAmountIn(uint256 amountIn) external {
        fixedAmountIn = amountIn;
    }

    function exactOutput(ExactOutputParams calldata p) external payable override returns (uint256 amountIn) {
        amountIn = fixedAmountIn;
        require(amountIn <= p.amountInMaximum, "mock: exceeds amountInMaximum");
        if (msg.value == 0) {
            // ERC-20 mode: pull the input from the caller.
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        } else {
            // ETH mode: the forwarded ETH is already held by this contract; mark
            // `amountIn` as consumed so refundETH only returns the surplus.
            collectedEth += amountIn;
        }
        require(IERC20(tokenOut).transfer(p.recipient, p.amountOut), "mock: out transfer failed");
        return amountIn;
    }

    function refundETH() external payable override {
        uint256 refundable = address(this).balance - collectedEth;
        if (refundable > 0) {
            (bool ok, ) = payable(msg.sender).call{value: refundable}("");
            require(ok, "mock: refund failed");
        }
    }

    function multicall(bytes[] calldata data) external payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool ok, bytes memory res) = address(this).delegatecall(data[i]);
            require(ok, "mock: multicall subcall failed");
            results[i] = res;
        }
    }
}
