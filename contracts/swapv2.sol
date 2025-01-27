// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
}

interface IAsset {}

contract Swap {
    IVault public immutable vault;

    address  VAULT_ADDRESS = 0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33;
    address  HONEY = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
    address  WBERA = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8;
    bytes32  WETH_USDC_POOL_ID = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    constructor() {
        vault = IVault(VAULT_ADDRESS);
        IERC20(HONEY).approve(VAULT_ADDRESS, type(uint256).max);
    }

    function executeSwap(
        uint256 amountIn, 
        uint256 minAmountOut
    ) external payable {
        require(
            IERC20(HONEY).balanceOf(msg.sender) >= amountIn, 
            "Insufficient WETH balance"
        );

        IERC20(HONEY).transferFrom(msg.sender, address(this), amountIn);

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: WETH_USDC_POOL_ID,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(HONEY),
            assetOut: IAsset(WBERA),
            amount: amountIn,
            userData: ""
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(msg.sender),
            toInternalBalance: false
        });

        uint256 amountOut = vault.swap{gas: gasleft()}(
            singleSwap, 
            funds, 
            minAmountOut, 
            block.timestamp + 300
        );

        require(amountOut >= minAmountOut, "Insufficient output amount");
    }
}