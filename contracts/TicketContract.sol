// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SwapQuoteQuery.sol";
import "hardhat/console.sol";

interface IWBERA is IERC20 {
    function deposit() external payable;
}
interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
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
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }
}

contract TicketContract is Ownable, ReentrancyGuard, Pausable {
    //========================Variables=========================
    IERC20 public token;
    SwapQuoteQuery public swapQuoteQuery;
    IVault public vault;
    address public immutable WETH;
    bytes32 public immutable BeraPoolId;
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
    struct TokenInfo {
        address tokenAddress; 
        bytes32 poolIdWithHoney;
    }
    
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
        // address _teamAddress,
        // address _admin,
        address _baseToken,
        address _valutAddress,
        address _swapQuoteQuery,
        address _WETH,
        bytes32 _BeraPoolId,
        address _vault
    ) Ownable() {
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        ozFees = (2500 * decimals) / 10000;
        //HardCoded values
        teamAddress = msg.sender;
        admin = msg.sender;
        // baseToken = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
        // valutAddress = 0x42F945224afEA1019ADF1d7Be020450f4Df529C7;
        // swapQuoteQuery = SwapQuoteQuery(
        //     0x409dD95463CBdc9F19FEea04da6fbA82fD15370e  
        // );
        // vault = IVault(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
        // WETH = 0x6969696969696969696969696969696969696969;
        // BeraPoolId = 0x2c4a603a2aa5596287a06886862dc29d56dbc354000200000000000000000002;

        baseToken = _baseToken;
        valutAddress = _valutAddress;
        swapQuoteQuery = SwapQuoteQuery(_swapQuoteQuery  );
        vault = IVault(_vault);
        WETH = _WETH;
        BeraPoolId = _BeraPoolId;
    }

    /**
     * @notice Gets the price in the specified token for a given amount of base tokens
     * @param _quoteToken The token to get the price in
     * @param amount The amount of base tokens
     * @return The price in the specified token
     */
    function getPrice(address _quoteToken, uint256 amount) public view
        returns (uint256)
    {
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");
        
        if (_quoteToken == baseToken) {
            return amount;
        } else if (_quoteToken == address(0)) {
            bytes32 poolId = BeraPoolId;
            uint256 ethPrice = swapQuoteQuery.getPriceForToken(
                poolId,
                WETH, 
                amount
            );
            require(ethPrice > 0, "Invalid ETH price");
            return ethPrice;
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_quoteToken];
            require(
                tokenInfo.tokenAddress != address(0),
                "Token not supported"
            );
            bytes32 poolId = tokenInfo.poolIdWithHoney;
            uint256 tokenPrice = swapQuoteQuery.getPriceForToken(
                poolId,
                _quoteToken,
                amount
            );
            require(tokenPrice > 0, "Invalid token price");
            return tokenPrice;
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
     * @param poolIdWithHoney The pool ID for swapping the token
     */
    function addToken(address _token, bytes32 poolIdWithHoney)
        external
        onlyOwner
    {
        require(_token != address(0), "Invalid token address");
        require(
            supportedTokens[_token].tokenAddress == address(0),
            "Token already exists"
        );
        supportedTokens[_token] = TokenInfo(_token, poolIdWithHoney);
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
     * @notice Internal function to swap tokens using Balancer vault
     * @param poolId The pool ID to use for swapping
     * @param tokenIn The input token address (address(0) for ETH)
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens
     * @param expectedAmountOut The expected amount of output tokens before slippage
     * @param recipient The address to receive the output tokens
     */
    function swapTokens(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 expectedAmountOut,
        address recipient
    ) internal {
        bool isETH = tokenIn == address(0);
        address actualTokenIn = isETH ? WETH : tokenIn;
        uint256 minAmountOut = calculateMinAmountOut(expectedAmountOut);
         if (isETH) {
            IWBERA(WETH).deposit{value: amountIn}();
            IERC20(WETH).approve(address(vault), amountIn);
        } else {
            IERC20(tokenIn).approve(address(vault), amountIn);
        }
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(actualTokenIn),
            assetOut: IAsset(tokenOut),
            amount: amountIn,
            userData: ""
        });
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(recipient),
            toInternalBalance: false
        });

        vault.swap(
            singleSwap,
            funds,
            minAmountOut, 
            block.timestamp + 10 minutes
        );
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
                BeraPoolId,
                address(0),
                baseToken,
                ethNeeded,
                totalAmount, 
                address(this)
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
                tokenInfo.poolIdWithHoney,
                _token,
                baseToken,
                tokenAmount,
                totalAmount,
                address(this)
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
     * @notice Sets the vault address
     * @param newVault The new vault address
     */
    function setVaultAddress(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid Vault address");
        valutAddress = newVault;
        emit SetVaultAddress(newVault);
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

    /**
     * @notice Sets the swap quote query contract address
     * @param _swapQuoteQuery The new swap quote query contract address
     */
    function setSwapQuoteQuery(address _swapQuoteQuery) external onlyOwner {
        require(_swapQuoteQuery != address(0), "Invalid swap quote query address");
        swapQuoteQuery = SwapQuoteQuery(_swapQuoteQuery);
    }

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