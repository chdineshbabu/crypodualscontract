// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SwapQuoteQuery
 * @dev Fetches token pool details and calculates token swap prices.
 */
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
    address public WBERA = 0x6969696969696969696969696969696969696969;
    address public constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    /**
     * @dev Constructor initializes the vault address.
     */
    constructor() {
        // vault = IPrice(_vaultAddress);
        vault = IPrice(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
    }

    /**
     * @dev Fetches pool details including tokens, balances, and last update block.
     * @param poolId The ID of the liquidity pool.
     * @return tokens The list of tokens in the pool.
     * @return balances The respective balances of the tokens in the pool.
     * @return lastChangeBlock The last block in which the pool was updated.
     */
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

    /**
     * @dev Calculates the equivalent price for a given token in the pool.
     * @param poolId The ID of the liquidity pool.
     * @param token The token address for which the price is required.
     * @param amount The amount of the token to be swapped.
     * @return The equivalent amount of HONEY token.
     */
    function getPriceForToken(bytes32 poolId, address token, uint256 amount)
        external
        view
        returns (uint256)
    {
        (IERC20[] memory tokens, uint256[] memory balances, ) = vault.getPoolTokens(poolId);
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
        
        uint256 balanceForHoney = (balanceToken * 1e18) / balanceHoney;
        return (amount * balanceForHoney) / 1e18;
    }
}
