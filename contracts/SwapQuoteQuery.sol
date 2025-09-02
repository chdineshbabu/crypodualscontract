// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IUniswapV2.sol";

/**
 * @title SwapQuoteQuery
 * @dev Fetches token swap prices using UniswapV2 router with HONEY as the base token.
 */

contract SwapQuoteQuery is Initializable, OwnableUpgradeable {
    IUniswapV2Router02 public router;
    address public WBERA;
    address public HONEY;
    address public factory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Constructor initializes the router, factory, and token addresses.
     */
    function initialize(
        address _honey, 
        address _bera, 
        address _routerAddress
    ) public initializer {
        __Ownable_init();
        
        router = IUniswapV2Router02(_routerAddress);
        factory = router.factory();
        WBERA = _bera;
        HONEY = _honey;
    }

    /**
     * @dev Gets the swap price for a token to HONEY using a specific path.
     * @param path The swap path from token to HONEY.
     * @param amount The amount of the input token to swap.
     * @return The amount of HONEY tokens that would be received.
     */
    function getTokenToHoneyPriceWithPath(address[] calldata path, uint256 amount)
        external
        view
        returns (uint256)
    {
        require(path.length >= 2, "Invalid path length");
        require(path[path.length - 1] == HONEY, "Path must end with HONEY");
        require(amount > 0, "Amount must be greater than 0");

        try router.getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1]; // Return the HONEY amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the swap price for HONEY to a token using a specific path.
     * @param path The swap path from HONEY to token.
     * @param honeyAmount The amount of HONEY to swap.
     * @return The amount of the target token that would be received.
     */
    function getHoneyToTokenPriceWithPath(address[] calldata path, uint256 honeyAmount)
        external
        view
        returns (uint256)
    {
        require(path.length >= 2, "Invalid path length");
        require(path[0] == HONEY, "Path must start with HONEY");
        require(honeyAmount > 0, "Amount must be greater than 0");

        try router.getAmountsOut(honeyAmount, path) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1]; // Return the target token amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the swap price for a token to HONEY using UniswapV2 router.
     * Tries direct path first, then through BERA if direct path fails.
     * @param token The token address to get price for.
     * @param amount The amount of the token to swap.
     * @return The amount of HONEY tokens that would be received.
     */
    function getTokenToHoneyPrice(address token, uint256 amount)
        external
        view
        returns (uint256)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(amount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = HONEY;

        try router.getAmountsOut(amount, directPath) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the HONEY amount
        } catch {
            // If direct path fails, try through BERA
            address[] memory beraPath = new address[](3);
            beraPath[0] = token;
            beraPath[1] = WBERA;
            beraPath[2] = HONEY;

            try router.getAmountsOut(amount, beraPath) returns (uint256[] memory amounts) {
                return amounts[2]; // Return the HONEY amount
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the swap price for HONEY to a token using UniswapV2 router.
     * Tries direct path first, then through BERA if direct path fails.
     * @param token The token address to get price for.
     * @param honeyAmount The amount of HONEY to swap.
     * @return The amount of the target token that would be received.
     */
    function getHoneyToTokenPrice(address token, uint256 honeyAmount)
        external
        view
        returns (uint256)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(honeyAmount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = HONEY;
        directPath[1] = token;

        try router.getAmountsOut(honeyAmount, directPath) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the target token amount
        } catch {
            // If direct path fails, try through BERA
            address[] memory beraPath = new address[](3);
            beraPath[0] = HONEY;
            beraPath[1] = WBERA;
            beraPath[2] = token;

            try router.getAmountsOut(honeyAmount, beraPath) returns (uint256[] memory amounts) {
                return amounts[2]; // Return the target token amount
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the amount of HONEY needed to get a specific amount of another token.
     * @param token The token address to get price for.
     * @param tokenAmount The amount of the target token desired.
     * @return The amount of HONEY needed.
     */
    function getHoneyAmountForToken(address token, uint256 tokenAmount)
        external
        view
        returns (uint256)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(tokenAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = HONEY;
        path[1] = token;

        try router.getAmountsIn(tokenAmount, path) returns (uint256[] memory amounts) {
            return amounts[0]; // Return the HONEY amount needed
        } catch {
            // If direct path fails, try through BERA
            address[] memory beraPath = new address[](3);
            beraPath[0] = HONEY;
            beraPath[1] = WBERA;
            beraPath[2] = token;

            try router.getAmountsIn(tokenAmount, beraPath) returns (uint256[] memory amounts) {
                return amounts[0]; // Return the HONEY amount needed
            } catch {
                revert("No valid swap path found");
            }
        }
    }

   
    /**
     * @dev Gets the price of HONEY in terms of BERA (native token).
     * @param honeyAmount The amount of HONEY to get price for.
     * @return The amount of BERA that would be received.
     */
    function getHoneyToBeraPrice(uint256 honeyAmount)
        external
        view
        returns (uint256)
    {
        require(honeyAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = HONEY;
        path[1] = WBERA;

        try router.getAmountsOut(honeyAmount, path) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the BERA amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of BERA in terms of HONEY.
     * @param beraAmount The amount of BERA to get price for.
     * @return The amount of HONEY that would be received.
     */
    function getBeraToHoneyPrice(uint256 beraAmount)
        external
        view
        returns (uint256)
    {
        require(beraAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = WBERA;
        path[1] = HONEY;

        try router.getAmountsOut(beraAmount, path) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the HONEY amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of HONEY in terms of any token using a direct path.
     * @param token The token address to get price for.
     * @param honeyAmount The amount of HONEY to get price for.
     * @return The amount of the target token that would be received.
     */
    function getHoneyPriceInToken(address token, uint256 honeyAmount)
        external
        view
        returns (uint256)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(honeyAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = HONEY;
        path[1] = token;

        try router.getAmountsOut(honeyAmount, path) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the target token amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of any token in terms of HONEY.
     * @param token The token address to get price for.
     * @param tokenAmount The amount of the token to get price for.
     * @return The amount of HONEY that would be received.
     */
    function getTokenPriceInHoney(address token, uint256 tokenAmount)
        external
        view
        returns (uint256)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(tokenAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = HONEY;

        try router.getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            return amounts[1]; // Return the HONEY amount
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the best swap path for a token to HONEY.
     * Returns the path that gives the best output amount.
     * @param token The token address to get path for.
     * @param amount The amount of the token to swap.
     * @return path The best swap path.
     * @return outputAmount The expected output amount.
     */
    function getBestPathToHoney(address token, uint256 amount)
        external
        view
        returns (address[] memory path, uint256 outputAmount)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(amount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = HONEY;

        try router.getAmountsOut(amount, directPath) returns (uint256[] memory amounts) {
            return (directPath, amounts[1]);
        } catch {
            // If direct path fails, try through BERA
            address[] memory beraPath = new address[](3);
            beraPath[0] = token;
            beraPath[1] = WBERA;
            beraPath[2] = HONEY;

            try router.getAmountsOut(amount, beraPath) returns (uint256[] memory amounts) {
                return (beraPath, amounts[2]);
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the best swap path for HONEY to a token.
     * Returns the path that gives the best output amount.
     * @param token The token address to get path for.
     * @param honeyAmount The amount of HONEY to swap.
     * @return path The best swap path.
     * @return outputAmount The expected output amount.
     */
    function getBestPathFromHoney(address token, uint256 honeyAmount)
        external
        view
        returns (address[] memory path, uint256 outputAmount)
    {
        require(token != HONEY, "Cannot swap HONEY to HONEY");
        require(honeyAmount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = HONEY;
        directPath[1] = token;

        try router.getAmountsOut(honeyAmount, directPath) returns (uint256[] memory amounts) {
            return (directPath, amounts[1]);
        } catch {
            // If direct path fails, try through BERA
            address[] memory beraPath = new address[](3);
            beraPath[0] = HONEY;
            beraPath[1] = WBERA;
            beraPath[2] = token;

            try router.getAmountsOut(honeyAmount, beraPath) returns (uint256[] memory amounts) {
                return (beraPath, amounts[2]);
            } catch {
                revert("No valid swap path found");
            }
        }
    }
}
