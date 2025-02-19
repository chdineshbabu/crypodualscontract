// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IWBERA is IERC20 {
    function deposit() external payable;
}
interface IVault {
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

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
    address public immutable WETH;

    constructor(address _vaultAddress, address _WETH) {
        vault = IVault(_vaultAddress);
        WETH = _WETH;
    }

function swapTokens(
    bytes32 poolId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
) external payable {
    bool isETH = tokenIn == address(0);

    if (isETH) {
        require(msg.value == amountIn, "Incorrect ETH amount sent");
        IWBERA(WETH).deposit{value: msg.value}(); 
        IWBERA(WETH).approve(address(vault), amountIn);
    } else {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(vault), amountIn);
    }

    IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
        poolId: poolId,
        kind: IVault.SwapKind.GIVEN_IN,
        assetIn: IERC20(isETH ? WETH : tokenIn),
        assetOut: IERC20(tokenOut),
        amount: amountIn,
        userData: ""
    });

    IVault.FundManagement memory funds = IVault.FundManagement({
        sender: address(this),
        fromInternalBalance: false,
        recipient: payable(msg.sender),
        toInternalBalance: false
    });

    vault.swap(singleSwap,funds,minAmountOut,block.timestamp + 10 minutes);
}


    receive() external payable {}
}
