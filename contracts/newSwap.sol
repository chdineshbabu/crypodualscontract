// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    function swap(
        IVault.SingleSwap calldata singleSwap,
        IVault.FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256);

    struct SingleSwap {
        bytes32 poolId;
        IVault.SwapKind kind;
        IERC20 assetIn;
        IERC20 assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    enum SwapKind { GIVEN_IN, GIVEN_OUT }
}

contract TokenSwapper {
    IVault public vault;

    constructor(address _vaultAddress) {
        vault = IVault(_vaultAddress);
    }

    function swapTokens(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(vault), amountIn);

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IERC20(tokenIn),
            assetOut: IERC20(tokenOut),
            amount: amountIn,
            userData: ""
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(recipient),
            toInternalBalance: false
        });

        vault.swap(singleSwap, funds, minAmountOut, block.timestamp + 10 minutes);
    }
}
