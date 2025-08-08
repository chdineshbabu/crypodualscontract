// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2.sol";

contract TicketContract is Ownable, ReentrancyGuard, Pausable {
    //========================Variables=========================
    IERC20 public token;
    IUniswapV2Router02 public uniswapRouter;
    address public immutable WETH;
    uint256 public ticketPrice;
    uint256 public teamPercentage;
    uint256 public ozFees;
    address public teamAddress;
    address public admin;
    uint256 public decimals;
    address public baseToken;
    uint256 public tokenBalances;
    address public valutAddress;
    uint256 public slippageTolerance = 50; // 0.5% 
    
    //=======================Structs============================
    // Keep extensibility for future metadata if needed
    struct TokenInfo { address tokenAddress; }
    
    struct UserInfo {
        uint256 ticketBalance; 
        uint256 lastDepositedTime; 
    }
    
    // ================ Mappings ================
    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => UserInfo) public userInfo;
    
    //=================Events=======================
    event FeesTransfered(uint256 teamAmount, address token);
    event TicketPurchased(
        address indexed user,
        uint256 numOfTicket,
        address token
    );
    event SetUserBalance(address indexed user, uint256 amount);
    event SetTokenAddress(address tokenAddr);
    event SetTicketprice(uint256 price);
    event SetTeamPercentage(uint256 teamPercent);
    event SetOZFees(uint256 ozFees);
    event SetTeamAddress(address teamAddr);
    event SetAdmin(address newAdmin);
    event SetRouterAddress(address _routerAddress);
    event SetVaultAddress(address _vaultAddress);
    event SetBaseTokens(address _newBaseTokenAddress);
    event SetSlippageTolerance(uint256 _slippageTolerance);

    constructor(
        address _baseToken,
        address _valutAddress,
        address _WETH,
        address _uniswapRouter
    ) Ownable() {
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        ozFees = (2500 * decimals) / 10000;
        //HardCoded values
        teamAddress = msg.sender;
        admin = msg.sender;
        baseToken = _baseToken;
        valutAddress = _valutAddress;
        WETH = _WETH;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /**
     * @notice Gets the price in the specified token for a given amount of base tokens
     * @param _quoteToken The token to get the price in (address(0) for ETH)
     * @param amount The amount of base tokens desired
     * @return The price in the specified token (amount of quote token needed)
     */
    function getPrice(address _quoteToken, uint256 amount) public view returns (uint256) {
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");
        require(address(uniswapRouter) != address(0), "Router not set");

        if (_quoteToken == baseToken) {
            return amount;
        }

        if (_quoteToken == address(0)) {
            // ETH pricing via WETH -> baseToken
            address[] memory pathEth = new address[](2);
            pathEth[0] = WETH;
            pathEth[1] = baseToken;
            uint256[] memory amountsInEth = IUniswapV2Router02(uniswapRouter).getAmountsIn(amount, pathEth);
            require(amountsInEth.length == pathEth.length && amountsInEth[0] > 0, "Invalid ETH price");
            return amountsInEth[0];
        }

        TokenInfo memory tokenInfo = supportedTokens[_quoteToken];
        require(tokenInfo.tokenAddress != address(0), "Token not supported");

        address[] memory computedPath = _determinePath(_quoteToken, baseToken);
        uint256[] memory amountsIn = IUniswapV2Router02(uniswapRouter).getAmountsIn(amount, computedPath);
        require(amountsIn.length == computedPath.length && amountsIn[0] > 0, "Invalid token price");
        return amountsIn[0];
    }

    /**
     * @dev Determines a reasonable swap path from tokenIn to tokenOut.
     * Tries direct path; if not available and neither side is WETH, tries via WETH.
     */
    function _determinePath(address tokenIn, address tokenOut) internal view returns (address[] memory) {
        address actualIn = tokenIn == address(0) ? WETH : tokenIn;

        // Try direct two-hop
        address[] memory directPath = new address[](2);
        directPath[0] = actualIn;
        directPath[1] = tokenOut;
        try IUniswapV2Router02(uniswapRouter).getAmountsOut(1, directPath) returns (uint256[] memory) {
            return directPath;
        } catch {}

        // Try via WETH only if it does not create a WETH self-hop
        if (actualIn != WETH && tokenOut != WETH) {
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = actualIn;
            viaWethPath[1] = WETH;
            viaWethPath[2] = tokenOut;
            try IUniswapV2Router02(uniswapRouter).getAmountsOut(1, viaWethPath) returns (uint256[] memory) {
                return viaWethPath;
            } catch {}
        }

        revert("No valid swap path found");
    }

    /**
     * @dev Gets the swap output for a token to base token using a specific path.
     * @param path The swap path from token to base token.
     * @param amount The amount of the input token to swap.
     * @return The amount of base tokens that would be received.
     */
    function getTokenToBasePriceWithPath(address[] calldata path, uint256 amount)
        external
        view
        returns (uint256)
    {
        require(path.length >= 2, "Invalid path length");
        require(path[path.length - 1] == baseToken, "Path must end with base token");
        require(amount > 0, "Amount must be greater than 0");

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the swap output for base token to a token using a specific path.
     * @param path The swap path from base token to token.
     * @param baseAmount The amount of the base token to swap.
     * @return The amount of the target token that would be received.
     */
    function getBaseToTokenPriceWithPath(address[] calldata path, uint256 baseAmount)
        external
        view
        returns (uint256)
    {
        require(path.length >= 2, "Invalid path length");
        require(path[0] == baseToken, "Path must start with base token");
        require(baseAmount > 0, "Amount must be greater than 0");

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, path) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the swap output for a token to base token.
     * Tries direct path first, then through WETH if direct path fails.
     * @param token The token address to get price for.
     * @param amount The amount of the token to swap.
     * @return The amount of base tokens that would be received.
     */
    function getTokenToBasePrice(address token, uint256 amount)
        external
        view
        returns (uint256)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(amount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = baseToken;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, directPath) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            // If direct path fails, try through WETH
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = token;
            viaWethPath[1] = WETH;
            viaWethPath[2] = baseToken;

            try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, viaWethPath) returns (uint256[] memory amounts) {
                return amounts[2];
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the swap output for base token to a token.
     * Tries direct path first, then through WETH if direct path fails.
     * @param token The token address to get price for.
     * @param baseAmount The amount of the base token to swap.
     * @return The amount of the target token that would be received.
     */
    function getBaseToTokenPrice(address token, uint256 baseAmount)
        external
        view
        returns (uint256)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(baseAmount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = baseToken;
        directPath[1] = token;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, directPath) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            // If direct path fails, try through WETH
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = baseToken;
            viaWethPath[1] = WETH;
            viaWethPath[2] = token;

            try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, viaWethPath) returns (uint256[] memory amounts) {
                return amounts[2];
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the amount of base token needed to get a specific amount of another token.
     * Tries direct path first, then through WETH if direct path fails.
     * @param token The token address to get price for.
     * @param tokenAmount The amount of the target token desired.
     * @return The amount of base token needed.
     */
    function getBaseAmountForToken(address token, uint256 tokenAmount)
        external
        view
        returns (uint256)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(tokenAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = token;

        try IUniswapV2Router02(uniswapRouter).getAmountsIn(tokenAmount, path) returns (uint256[] memory amounts) {
            return amounts[0];
        } catch {
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = baseToken;
            viaWethPath[1] = WETH;
            viaWethPath[2] = token;

            try IUniswapV2Router02(uniswapRouter).getAmountsIn(tokenAmount, viaWethPath) returns (uint256[] memory amounts) {
                return amounts[0];
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the price of base token in terms of WETH (native wrapped token).
     * @param baseAmount The amount of base token to get price for.
     * @return The amount of WETH that would be received.
     */
    function getBaseToWethPrice(uint256 baseAmount)
        external
        view
        returns (uint256)
    {
        require(baseAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = WETH;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of WETH in terms of base token.
     * @param wethAmount The amount of WETH to get price for.
     * @return The amount of base token that would be received.
     */
    function getWethToBasePrice(uint256 wethAmount)
        external
        view
        returns (uint256)
    {
        require(wethAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = baseToken;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(wethAmount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of base token in terms of any token using a direct path.
     * @param token The token address to get price for.
     * @param baseAmount The amount of base token to get price for.
     * @return The amount of the target token that would be received.
     */
    function getBasePriceInToken(address token, uint256 baseAmount)
        external
        view
        returns (uint256)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(baseAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = token;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the price of any token in terms of base token.
     * @param token The token address to get price for.
     * @param tokenAmount The amount of the token to get price for.
     * @return The amount of base token that would be received.
     */
    function getTokenPriceInBase(address token, uint256 tokenAmount)
        external
        view
        returns (uint256)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(tokenAmount > 0, "Amount must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = baseToken;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            revert("Failed to get swap price");
        }
    }

    /**
     * @dev Gets the best swap path for a token to base token.
     * Returns the path that gives the best output amount.
     * @param token The token address to get path for.
     * @param amount The amount of the token to swap.
     * @return path The best swap path.
     * @return outputAmount The expected output amount.
     */
    function getBestPathToBase(address token, uint256 amount)
        external
        view
        returns (address[] memory path, uint256 outputAmount)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(amount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = token;
        directPath[1] = baseToken;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, directPath) returns (uint256[] memory amounts) {
            return (directPath, amounts[1]);
        } catch {
            // If direct path fails, try through WETH
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = token;
            viaWethPath[1] = WETH;
            viaWethPath[2] = baseToken;

            try IUniswapV2Router02(uniswapRouter).getAmountsOut(amount, viaWethPath) returns (uint256[] memory amounts) {
                return (viaWethPath, amounts[2]);
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @dev Gets the best swap path for base token to a token.
     * Returns the path that gives the best output amount.
     * @param token The token address to get path for.
     * @param baseAmount The amount of base token to swap.
     * @return path The best swap path.
     * @return outputAmount The expected output amount.
     */
    function getBestPathFromBase(address token, uint256 baseAmount)
        external
        view
        returns (address[] memory path, uint256 outputAmount)
    {
        require(token != baseToken, "Cannot swap base to base");
        require(baseAmount > 0, "Amount must be greater than 0");

        // Try direct path first
        address[] memory directPath = new address[](2);
        directPath[0] = baseToken;
        directPath[1] = token;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, directPath) returns (uint256[] memory amounts) {
            return (directPath, amounts[1]);
        } catch {
            // If direct path fails, try through WETH
            address[] memory viaWethPath = new address[](3);
            viaWethPath[0] = baseToken;
            viaWethPath[1] = WETH;
            viaWethPath[2] = token;

            try IUniswapV2Router02(uniswapRouter).getAmountsOut(baseAmount, viaWethPath) returns (uint256[] memory amounts) {
                return (viaWethPath, amounts[2]);
            } catch {
                revert("No valid swap path found");
            }
        }
    }

    /**
     * @notice Calculates the minimum amount out after applying slippage tolerance
     * @param amount The expected amount
     * @return The minimum amount out after slippage
     */
    function calculateMinAmountOut(uint256 amount) public view returns (uint256) {
        return amount - (amount * slippageTolerance / 10000);
    }

    /**
     * @notice Adds a supported token to the contract
     * @param _token The token address to add
     */
    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(
            supportedTokens[_token].tokenAddress == address(0),
            "Token already exists"
        );
        supportedTokens[_token] = TokenInfo({tokenAddress: _token});
    }

    /**
     * @notice Removes a supported token from the contract
     * @param _token The token address to remove
     */
    function removeToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(
            supportedTokens[_token].tokenAddress != address(0),
            "Token does not exist"
        );

        delete supportedTokens[_token];
    }

    /**
     * @notice Internal function to swap tokens using UniswapV2 Router
     * @param tokenIn The input token address (address(0) for ETH)
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens (or ETH if tokenIn == address(0))
     * @param expectedAmountOut The expected amount of output tokens before slippage
     * @param recipient The address to receive the output tokens
     * @param path The swap path to use
     */
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 expectedAmountOut,
        address recipient,
        address[] memory path
    ) internal {
        require(address(uniswapRouter) != address(0), "Router not set");
        bool isETH = tokenIn == address(0);
        uint256 minAmountOut = calculateMinAmountOut(expectedAmountOut);

        // Auto-determine path when not provided
        address[] memory swapPath = path.length > 0 ? path : _determinePath(isETH ? WETH : tokenIn, tokenOut);

        if (isETH) {
            IUniswapV2Router02(uniswapRouter).swapExactETHForTokens{value: amountIn}(
                minAmountOut,
                swapPath,
                recipient,
                block.timestamp + 10 minutes
            );
        } else {
            IERC20(tokenIn).approve(address(uniswapRouter), amountIn);
            IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
                amountIn,
                minAmountOut,
                swapPath,
                recipient,
                block.timestamp + 10 minutes
            );
        }
    }

    /**
     * @notice Purchase tickets using various tokens
     * @param _token The token address to pay with (address(0) for ETH)
     * @param numOfTicket The number of tickets to purchase
     */
    function purchaseTicket(address _token, uint256 numOfTicket)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(numOfTicket > 0, "Invalid amount");
        uint256 ticketAmount = (numOfTicket * ticketPrice) / decimals; 
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals; 
        uint256 ozFee = (numOfTicket * ozFees) / decimals; 
        uint256 totalAmount = ticketAmount + teamAmount + ozFee; 

        if (_token == baseToken) {
            require(
                IERC20(_token).transferFrom(
                    msg.sender,
                    address(this),
                    totalAmount
                ),
                "Transfer failed"
            );
            IERC20(_token).transfer(teamAddress, teamAmount);
            IERC20(_token).transfer(admin, ozFee);
            IERC20(_token).transfer(valutAddress, ticketAmount);
        } else if (_token == address(0)) {
            uint256 ethNeeded = getPrice(address(0), totalAmount);
            require(ethNeeded > 0, "Invalid ETH amount");
            require(msg.value >= ethNeeded, "Insufficient ETH sent");
            if (msg.value > ethNeeded) {
                payable(msg.sender).transfer(msg.value - ethNeeded);
            }
            swapTokens(
                address(0),
                baseToken,
                ethNeeded,
                totalAmount, 
                address(this),
                new address[](0)
            );
            IERC20(baseToken).transfer(teamAddress, teamAmount);
            // IERC20(baseToken).transfer(admin, ozFee);
            IERC20(baseToken).transfer(valutAddress, ticketAmount);
            uint256 remaining = IERC20(baseToken).balanceOf(address(this));
            IERC20(baseToken).transfer(admin, remaining);
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_token];
            require(tokenInfo.tokenAddress != address(0), "Token not supported");
            
            uint256 tokenAmount = getPrice(_token, totalAmount);
            require(tokenAmount > 0, "Invalid token amount");
            
            require(
                IERC20(_token).transferFrom(msg.sender, address(this), tokenAmount),
                "Transfer failed"
            );
            
            swapTokens(
                _token,
                baseToken,
                tokenAmount,
                totalAmount,
                address(this),
                new address[](0)
            );
            
            IERC20(baseToken).transfer(teamAddress, teamAmount);
            // IERC20(baseToken).transfer(admin, ozFee);
            IERC20(baseToken).transfer(valutAddress, ticketAmount);
            uint256 remaining = IERC20(baseToken).balanceOf(address(this));
            IERC20(baseToken).transfer(admin, remaining);
        }

        userInfo[msg.sender].ticketBalance += numOfTicket;
        userInfo[msg.sender].lastDepositedTime = block.timestamp;
        emit TicketPurchased(msg.sender, numOfTicket, _token);
    }

    /**
     * @notice Sets the admin address
     * @param newAdmin The new admin address
     */
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    /**
     * @notice Sets the vault address (destination for ticket funds)
     * @param newVault The new vault address
     */
    function setVaultAddress(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid Vault address");
        valutAddress = newVault;
        emit SetVaultAddress(newVault);
    }

    /**
     * @notice Sets the UniswapV2 router address
     * @param _router The router address
     */
    function setRouterAddress(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        uniswapRouter = IUniswapV2Router02(_router);
        emit SetRouterAddress(_router);
    }

    /**
     * @notice Sets the slippage tolerance for swaps
     * @param _slippageTolerance New slippage tolerance in basis points (e.g. 50 = 0.5%, 100 = 1%)
     */
    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance > 0 && _slippageTolerance <= 1000, "Invalid slippage: must be between 0% and 10%");
        slippageTolerance = _slippageTolerance;
        emit SetSlippageTolerance(_slippageTolerance);
    }

    /**
     * @notice Sets the base token address
     * @param newBaseToken The new base token address
     */
    function setBaseToken(address newBaseToken) external onlyOwner {
        require(newBaseToken != address(0), "Invalid base token address");
        baseToken = newBaseToken;
        emit SetBaseTokens(newBaseToken);
    }

    /**
     * @notice Sets the OZ fees percentage
     * @param amount The new OZ fees percentage (in basis points, e.g. 2500 = 25%)
     */
    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid OZ fees");
        ozFees = (amount * decimals) / 10000;
        emit SetOZFees(amount);
    }

    /**
     * @notice Sets the team percentage
     * @param amount The new team percentage (in basis points, e.g. 1000 = 10%)
     */
    function setTeamPercentage(uint256 amount) external onlyOwner {
        require(amount <= 2000, "Max 20%");
        teamPercentage = (ticketPrice * amount) / 10000;
        emit SetTeamPercentage(amount);
    }

    /**
     * @notice Sets the team address
     * @param newTeamAddress The new team address
     */
    function setTeamAddress(address newTeamAddress) external onlyOwner {
        require(newTeamAddress != address(0), "Invalid team address");
        teamAddress = newTeamAddress;
        emit SetTeamAddress(newTeamAddress);
    }

    // Removed setSwapQuoteQuery: pricing now uses UniswapV2 router

    /**
     * @notice Sets the ticket price
     * @param price The new ticket price
     */
    function setTicketPrice(uint256 price) external onlyOwner {
        require(price > 0, "Invalid ticket price");
        ticketPrice = price * decimals;
        // Update team percentage based on new ticket price
        teamPercentage = (ticketPrice * 1000) / 10000; // 10% by default
        emit SetTicketprice(price);
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {}
}