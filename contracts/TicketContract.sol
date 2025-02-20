// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SwapQuoteQuery.sol";

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

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }
}

contract TicketContract is Ownable, ReentrancyGuard, Pausable {
    //========================Varibales=========================
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
    //=======================Structs============================
    struct TokenInfo {
        address tokenAddress; // Suppoted token in the contract
        bytes32 poolIdWithHoney; // The pool ID for token to Swap
    }
    struct UserInfo {
        uint256 ticketBalance; // The tickets that Each user has.
        uint256 lastDepositedTime; // Last deposited Timestamp.
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
    event setVaultAddresss(address _vaultAddress);
    event setBaseTokens(address _newBaseTokenAddress);

    constructor()
        // address _swapQuoteQuery,
        // address _baseToken,
        // address _vaultAddress,
        // address _WBERA,
        // bytes32 _BERAPOOLID
        Ownable(msg.sender)
    {
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        ozFees = (5000 * decimals) / 10000;
        teamAddress = msg.sender;
        admin = msg.sender;
        baseToken = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
        valutAddress = 0x4Be03f781C497A489E3cB0287833452cA9B9E80B;
        swapQuoteQuery = SwapQuoteQuery(
            0x3ffa381a42EF5287af98221aC726e8c77C1ecAA1
        );
        vault = IVault(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
        WETH = 0x6969696969696969696969696969696969696969;
        BeraPoolId = 0x2c4a603a2aa5596287a06886862dc29d56dbc354000200000000000000000002;
        // baseToken = _baseToken;
        // valutAddress = _vaultAddress;
        // swapQuoteQuery = SwapQuoteQuery(_swapQuoteQuery);
        // vault = IVault(_vaultAddress);
        // WETH = _WBERA;
        // BeraPoolId = _BERAPOOLID;
    }

    function getPrice(address _quoteToken)
        public
        view
        returns (uint256 pricePerToken)
    {
        // require(_quoteToken != address(0), "Invalid token address");
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");
        if (_quoteToken == baseToken) {
            return ticketPrice;
        } else if (_quoteToken == address(0)) {
            bytes32 poolId = BeraPoolId;
            uint256 tempTokenPrice = swapQuoteQuery.getPriceForToken(
                poolId,
                _quoteToken
            );
            require(tempTokenPrice > 0, "Invalid token price");
            uint256 amountOfTokenPerTicket = (ticketPrice * tempTokenPrice) /
                decimals;
            return amountOfTokenPerTicket;
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_quoteToken];
            require(
                tokenInfo.tokenAddress != address(0),
                "Token not supported"
            );
            bytes32 poolId = tokenInfo.poolIdWithHoney;
            uint256 tempTokenPrice = swapQuoteQuery.getPriceForToken(
                poolId,
                _quoteToken
            );
            require(tempTokenPrice > 0, "Invalid token price");
            uint256 amountOfTokenPerTicket = (ticketPrice * tempTokenPrice) /
                decimals;
            return amountOfTokenPerTicket;
        }
    }

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

    function removeToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(
            supportedTokens[_token].tokenAddress != address(0),
            "Token does not exist"
        );

        delete supportedTokens[_token];
    }

    function swapTokens(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal {
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
            kind: IVault.SwapKind.GIVEN_IN, // Corrected SwapKind
            assetIn: IERC20(isETH ? WETH : tokenIn),
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

        vault.swap(
            singleSwap,
            funds,
            minAmountOut,
            block.timestamp + 10 minutes
        );
    }

    function purchaseTicket(address _token, uint256 numOfTicket)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(numOfTicket > 0, "Invalid amount");

        uint256 ticketAmount = numOfTicket * ticketPrice; 
        uint256 teamAmount = (ticketAmount * teamPercentage) / 10000; // 10% of ticketAmount
        uint256 ozFee = (ticketAmount * ozFees) / 10000; // 50% of ticketAmount
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
            uint256 price = swapQuoteQuery.getPriceForToken(BeraPoolId, WETH); 
            uint256 requiredWETH = (totalAmount * 1e18) / price; 
            require(msg.value >= requiredWETH, "Incorrect ETH amount sent");

            IWBERA(WETH).deposit{value: msg.value}();
            IWBERA(WETH).approve(address(vault), requiredWETH);

            uint256 minAmountOut = (totalAmount * 95) / 100; // 5% slippage
            swapTokens(
                BeraPoolId,
                WETH,
                baseToken,
                requiredWETH,
                minAmountOut,
                address(this)
            );

            IERC20(baseToken).transfer(teamAddress, teamAmount);
            IERC20(baseToken).transfer(admin, ozFee);
            IERC20(baseToken).transfer(valutAddress, ticketAmount);
        } else {
            TokenInfo memory tokenInfo = supportedTokens[_token];
            require(
                tokenInfo.tokenAddress != address(0),
                "Token not supported"
            );

            uint256 price = swapQuoteQuery.getPriceForToken(
                tokenInfo.poolIdWithHoney,
                _token
            ); 
            uint256 requiredTokenAmount = (totalAmount * 1e18) / price; 

            require(
                IERC20(_token).transferFrom(
                    msg.sender,
                    address(this),
                    requiredTokenAmount
                ),
                "Transfer failed"
            );
            IERC20(_token).approve(address(vault), requiredTokenAmount);
            uint256 minAmountOut = (totalAmount * 95) / 100; // 5% slippage
            swapTokens(
                tokenInfo.poolIdWithHoney,
                _token,
                baseToken,
                requiredTokenAmount,
                minAmountOut,
                address(this)
            );
            IERC20(baseToken).transfer(teamAddress, teamAmount);
            IERC20(baseToken).transfer(admin, ozFee);
            IERC20(baseToken).transfer(valutAddress, ticketAmount);
        }
        userInfo[msg.sender].ticketBalance += numOfTicket;
        userInfo[msg.sender].lastDepositedTime = block.timestamp;
        emit TicketPurchased(msg.sender, numOfTicket, _token);
    }

    // function feesTransfer(uint256 teamAmnt, uint256 ozFeeAmnt) internal {
    //     token = IERC20(baseToken);
    //     bool approveForAdmin = token.approve(teamAddress, teamAmnt);
    //     require(approveForAdmin, "Admin approvel not done");
    //     bool teamTransfer = token.transferFrom(
    //         msg.sender,
    //         teamAddress,
    //         teamAmnt
    //     );
    //     require(teamTransfer, "Team transfer failed");
    //     if (ozFeeAmnt > 0) {
    //         bool approveForTeam = token.approve(admin, ozFeeAmnt);
    //         require(approveForTeam, "Team approvel not done");
    //         bool transferOZFeesToAdmin = token.transferFrom(
    //             msg.sender,
    //             admin,
    //             ozFeeAmnt
    //         );
    //         require(transferOZFeesToAdmin, "OZ fees transfer failed");
    //     }

    //     emit FeesTransfered(teamAmnt, baseToken);
    // }

    // ================ Setter Functions ================
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    function setVaultAddress(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid Vault address");
        valutAddress = newVault;
        emit setVaultAddresss(newVault);
    }

    function setBaseToken(address newBaseToken) external onlyOwner {
        require(newBaseToken != address(0));
        baseToken = newBaseToken;
        emit setBaseTokens(newBaseToken);
    }

    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid OZ fees");
        ozFees = (amount * decimals) / 10000;
        emit SetOZFees(amount);
    }

    function setTeamPercentage(uint256 amount) external onlyOwner {
        require(amount <= 2000, "Max 20%");
        teamPercentage = (ticketPrice * amount) / 10000;
        emit SetTeamPercentage(amount);
    }

    function setTeamAddress(address newTeamAddress) external onlyOwner {
        require(newTeamAddress != address(0), "Invalid team address");
        teamAddress = newTeamAddress;
        emit SetTeamAddress(newTeamAddress);
    }

    function setSwapQuoteQuery(address _swapQuoteQuery) external onlyOwner {
        swapQuoteQuery = SwapQuoteQuery(_swapQuoteQuery);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
