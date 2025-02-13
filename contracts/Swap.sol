// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


// Valut contract address: 0x4Be03f781C497A489E3cB0287833452cA9B9E80B
// Balancer Quary contract address: 0x3C612e132624f4Bd500eE1495F54565F0bcc9b59
interface IAsset {
    // Empty interface used for asset addresses
}
interface IQuary {
    function querySwap(IBalancerVault.SingleSwap memory singleSwap, IBalancerVault.FundManagement memory funds)
    external
    returns (uint256);
}

interface IBalancerVault {
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
    
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);
}

contract BalancerV3Swapper {
    IBalancerVault public immutable vault;
    IQuary public immutable quary;
    uint256 public constant MAX_DEADLINE = 2 days;    
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDeadline();
    error SwapFailed();
    
    event SwapExecuted(
        address indexed sender,
        address indexed assetIn,
        address indexed assetOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address vaultAddress, address queryAddress) {
        if (vaultAddress == address(0)) revert InvalidAddress();
        vault = IBalancerVault(vaultAddress);
        quary = IQuary(queryAddress);
    }
    function swap(
        bytes32 poolId,
        address assetIn,
        address assetOut,
        uint256 amount,
        address payable recipient,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (assetIn == address(0) || assetOut == address(0) || recipient == address(0)) 
            revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (deadline == 0) {
            deadline = block.timestamp + 10 minutes; 
        } else if (deadline > block.timestamp + MAX_DEADLINE) {
            revert InvalidDeadline();
        }
        if (deadline <= block.timestamp) revert InvalidDeadline();

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: poolId,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: msg.sender,
            fromInternalBalance: false,
            recipient: recipient,
            toInternalBalance: false
        });

        amountOut = vault.swap(singleSwap, funds, limit, deadline);
        if (amountOut < limit) revert SwapFailed();
        
        emit SwapExecuted(msg.sender, assetIn, assetOut, amount, amountOut);
        return amountOut;
    }
    function querySwap(
        bytes32 poolId,
        address assetIn,
        address assetOut,
        uint256 amount
    ) external returns (uint256) {
        if (assetIn == address(0) || assetOut == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: poolId,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: msg.sender,
            fromInternalBalance: false,
            recipient: payable(msg.sender),
            toInternalBalance: false
        });
        return quary.querySwap(singleSwap, funds);
    }
}