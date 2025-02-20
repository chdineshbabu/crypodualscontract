// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPrice {
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );
}

contract SwapQuoteQuery {
    IPrice public vault;
    address public WBERA =0x6969696969696969696969696969696969696969;
    address public constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    constructor(address _vaultAddress) {
        vault = IPrice(_vaultAddress);
    }

    function getPoolDetails(bytes32 poolId)
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        )
    {
        return vault.getPoolTokens(poolId);
    }

    function getPriceForToken(bytes32 poolId, address token)
        external
        view
        returns (uint256)
    {
        if (token == address(0)) {
            (IERC20[] memory tokens, uint256[] memory balances, ) = vault
                .getPoolTokens(poolId);
            int256 indexHoney = -1;
            int256 indexToken = -1;
            for (uint256 i = 0; i < tokens.length; i++) {
                if (address(tokens[i]) == HONEY) {
                    indexHoney = int256(i);
                }
                if (address(tokens[i]) == WBERA) {
                    indexToken = int256(i);
                }
            }
            require(indexHoney >= 0, "HONEY token not found in pool");
            require(indexToken >= 0, "Provided token not found in pool");
            uint256 balanceHoney = balances[uint256(indexHoney)];
            uint256 balanceToken = balances[uint256(indexToken)];
            require(balanceHoney > 0, "Insufficient balance for HONEY");
            require(balanceToken > 0, "Insufficient balance for token");
            return (balanceToken * 1e18) / balanceHoney;
        } else {
            (IERC20[] memory tokens, uint256[] memory balances, ) = vault
                .getPoolTokens(poolId);
            int256 indexHoney = -1;
            int256 indexToken = -1;
            for (uint256 i = 0; i < tokens.length; i++) {
                if (address(tokens[i]) == HONEY) {
                    indexHoney = int256(i);
                }
                if (address(tokens[i]) == token) {
                    indexToken = int256(i);
                }
            }
            require(indexHoney >= 0, "HONEY token not found in pool");
            require(indexToken >= 0, "Provided token not found in pool");
            uint256 balanceHoney = balances[uint256(indexHoney)];
            uint256 balanceToken = balances[uint256(indexToken)];
            require(balanceHoney > 0, "Insufficient balance for HONEY");
            require(balanceToken > 0, "Insufficient balance for token");
            return (balanceToken * 1e18) / balanceHoney;
        }
    }
}
