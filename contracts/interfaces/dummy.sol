// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IUniswapV2.sol";
import "hardhat/console.sol";

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
     * @param _quoteToken The token to get the price in
     * @param amount The amount of base tokens
     * @param path The swap path for the token (empty array for direct base token or ETH)
     * @return The price in the specified token
     */
    function getPrice(address _quoteToken, uint256 amount, address[] calldata path) public view
        returns (uint256)
    {
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");
        require(address(uniswapRouter) != address(0), "Router not set");
        
        if (_quoteToken == baseToken) {
            return amount;
        } else if (_quoteToken == address(0)) {
            // For ETH, use the provided path or default WETH -> baseToken
            address[] memory swapPath = path.length > 0 ? path : new address[](2);
            if (path.length == 0) {
                swapPath[0] = WETH;
                swapPath[1] = baseToken;
            }
            uint256[] memory amountsIn = IUniswapV2Router02(uniswapRouter)
                .getAmountsIn(amount, swapPath);
            require(amountsIn.length == swapPath.length && amountsIn[0] > 0, "Invalid ETH price");
            return amountsIn[0];
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_quoteToken];
            require(tokenInfo.tokenAddress != address(0), "Token not supported");
            
            // Use the provided path or default _quoteToken -> baseToken
            address[] memory swapPath = path.length > 0 ? path : new address[](2);
            if (path.length == 0) {
                swapPath[0] = _quoteToken;
                swapPath[1] = baseToken;
            }
            uint256[] memory amountsIn = IUniswapV2Router02(uniswapRouter)
                .getAmountsIn(amount, swapPath);
            require(amountsIn.length == swapPath.length && amountsIn[0] > 0, "Invalid token price");
            return amountsIn[0];
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
        address[] calldata path
    ) internal {
        require(address(uniswapRouter) != address(0), "Router not set");
        bool isETH = tokenIn == address(0);
        uint256 minAmountOut = calculateMinAmountOut(expectedAmountOut);

        // Use provided path or create default path
        address[] memory swapPath = path.length > 0 ? path : new address[](2);
        if (path.length == 0) {
            swapPath[0] = isETH ? WETH : tokenIn;
            swapPath[1] = tokenOut;
        }

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
     * @param path The swap path to use (empty array for direct base token payment)
     */
    function purchaseTicket(address _token, uint256 numOfTicket, address[] calldata path)
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
            uint256 ethNeeded = getPrice(address(0), totalAmount, path);
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
                path
            );
            IERC20(baseToken).transfer(teamAddress, teamAmount);
            // IERC20(baseToken).transfer(admin, ozFee);
            IERC20(baseToken).transfer(valutAddress, ticketAmount);
            uint256 remaining = IERC20(baseToken).balanceOf(address(this));
            IERC20(baseToken).transfer(admin, remaining);
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_token];
            require(tokenInfo.tokenAddress != address(0), "Token not supported");
            
            uint256 tokenAmount = getPrice(_token, totalAmount, path);
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
                path
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