// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TicketSystem is Ownable, ReentrancyGuard, Pausable {
    // ================ Variables ================
    IERC20 public token;
    
    uint256 public decimals;
    uint256 public ticketPrice;
    uint256 public teamPercentage;
    uint256 public rewardPoolPercentage;
    uint256 public burnPercentage;
    uint256 public ozFees;
    uint256 public withdrawLimit;
    
    address public teamAddress;
    address public rewardPool;
    address public admin;
    address public baseToken;
    uint256 public tokenBalances;

    // ================ Structs ================
    struct TokenInfo {
        address tokenAddress;
        address poolIdWithHoney;
    }

    struct UserInfo {
        uint256 ticketBalance;
        uint256 lastWithdrawalTime;
        uint256 lastDepositedTime;
    }

    // ================ Mappings ================
    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => UserInfo) public userInfo;

    // ================ Events ================
    event FeesTransfered(
        uint256 teamAmount,
        uint256 rewardPoolAmount,
        uint256 burnAmount,
        address token
    );
    event TicketWithdrawn(
        address indexed user,
        uint256 numOfTicket,
        address token
    );
    event TicketPurchased(
        address indexed user,
        uint256 numOfTicket,
        address token
    );
    event TokenWithdrawn(address indexed owner, uint256 amount);
    event SetUserBalance(address indexed user, uint256 amount);
    event SetTokenAddress(address tokenAddr);
    event SetpairAddress(address pairAddr);
    event SetTicketprice(uint256 price);
    event SetTeamPercentage(uint256 teamPercent);
    event SetRewardPoolPercentage(uint256 rewardPoolPercent);
    event SetBurnPercentage(uint256 burnPercent);
    event SetWithdrawLimit(uint256 withdrawLimit);
    event SetOZFees(uint256 ozFees);
    event SetTeamAddress(address teamAddr);
    event SetRewardAddress(address rewardPoolAddr);
    event SetAdmin(address newAdmin);
    event SetRouterAddress(address _routerAddress);

    constructor(
        address _baseToken,
        address _teamAddress,
        address _rewardPool,
        address _admin
    ) Ownable(msg.sender) {
        baseToken = _baseToken;
        teamAddress = _teamAddress;
        rewardPool = _rewardPool;
        admin = _admin;
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;        // 10%
        rewardPoolPercentage = (ticketPrice * 250) / 10000;   // 2.5%
        burnPercentage = (ticketPrice * 250) / 10000;         // 2.5%
        withdrawLimit = 500 * decimals;
        ozFees = (2500 * decimals) / 10000;                   // 0.25%
    }

    function getPrice(address _quoteToken) public view returns (uint256 pricePerToken) {
        require(_quoteToken != address(0), "Invalid token address");
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");

        if (_quoteToken == baseToken) {
            return ticketPrice;
        } else {
            // Using the price you provided
            // Currently dummy Price
            uint256 tempTokenPrice = 35739331609132833436351;
            require(tempTokenPrice > 0, "Invalid token price");

            // Calculate amount of tokens needed for one ticket
            uint256 amountOfTokenPerTicket = (ticketPrice / tempTokenPrice) * decimals;
            return amountOfTokenPerTicket;
        }
    }

    function addToken(
        address _token,
        address poolIdWithHoney
    ) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(poolIdWithHoney != address(0), "Invalid pool address");
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

    function swapTokenForHoney(address _token, address _poolIdWithHoney) public {
        token = IERC20(_token);

        // Add your swap logic here
        // This should integrate with BEX for token to HONEY swaps
    }

    // function purchaseTicketDummy(uint256 numOfTicket) external view returns (uint256 finalAmount) {
    //     address _token = 0xf44C597C3f6Cce487F134D6FE185feA270B28fb0;
    //     require(numOfTicket > 0, "Invalid amount");
        
    //     uint256 ticketAmount = (numOfTicket * ticketPrice) / decimals;
    //     uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
    //     uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) / decimals;
    //     uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;
    //     uint256 ozFee = (ozFees * getPrice(_token)) / decimals;

    //     uint256 totalAmount = ticketAmount + teamAmount + rewardPoolAmount + burnAmount + ozFee;
    //     return totalAmount;
    // }

    function purchaseTicket(
        address _token,
        uint256 numOfTicket
    ) external payable whenNotPaused nonReentrant {
        require(numOfTicket > 0, "Invalid amount");
        
        uint256 ticketAmount = (numOfTicket * ticketPrice) / decimals;
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) / decimals;
        uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;
        uint256 ozFee = (ozFees * getPrice(_token)) / decimals;

        uint256 totalAmount = ticketAmount + teamAmount + rewardPoolAmount + burnAmount + ozFee;

        if (_token == baseToken) {
            token = IERC20(_token);
            bool success = token.transferFrom(msg.sender, address(this), totalAmount);
            require(success, "Purchase token failed");
        } else {
            swapTokenForHoney(_token, supportedTokens[_token].poolIdWithHoney);
        }

        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, ozFee);
        userInfo[msg.sender].ticketBalance += numOfTicket;
        userInfo[msg.sender].lastDepositedTime = block.timestamp;
        
        emit TicketPurchased(msg.sender, numOfTicket, _token);
    }

    function withdrawTickets(
        uint256 numOfTicket
    ) external whenNotPaused nonReentrant {
        require(
            userInfo[msg.sender].ticketBalance >= numOfTicket,
            "Insufficient Balance"
        );
        require(numOfTicket >= 1, "Amount should be greater than Zero");
        
        token = IERC20(baseToken);
        uint256 amount = (numOfTicket * ticketPrice) / decimals;
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) / decimals;
        uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;

        require(numOfTicket <= withdrawLimit, "Exceeds withdraw limit");
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        uint256 ticketAmount = amount - (teamAmount + rewardPoolAmount + burnAmount);
        
        userInfo[msg.sender].lastWithdrawalTime = block.timestamp;
        userInfo[msg.sender].ticketBalance -= numOfTicket;
        
        bool success = token.transfer(msg.sender, ticketAmount);
        require(success, "Withdraw failed");
        
        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, 0); // No OZ fees on withdrawal
        emit TicketWithdrawn(msg.sender, numOfTicket, baseToken);
    }

    function feesTransfer(
        uint256 teamAmnt,
        uint256 rewardPoolAmnt,
        uint256 burnAmnt,
        uint256 ozFeeAmnt
    ) internal {
        token = IERC20(baseToken);
        
        bool teamTransfer = token.transfer(teamAddress, teamAmnt);
        require(teamTransfer, "Team transfer failed");

        bool rewardPoolTransfer = token.transfer(rewardPool, rewardPoolAmnt);
        require(rewardPoolTransfer, "RewardPool transfer failed");
        
        bool transferBurnAmountToAdmin = token.transfer(admin, burnAmnt);
        require(transferBurnAmountToAdmin, "Burn amount transfer failed");

        if (ozFeeAmnt > 0) {
            bool transferOZFeesToAdmin = token.transfer(admin, ozFeeAmnt);
            require(transferOZFeesToAdmin, "OZ fees transfer failed");
        }

        emit FeesTransfered(teamAmnt, rewardPoolAmnt, burnAmnt, baseToken);
    }

    // ================ Setter Functions ================
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    function setTicketPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid ticket price");
        ticketPrice = newPrice * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        rewardPoolPercentage = (ticketPrice * 250) / 10000;
        burnPercentage = (ticketPrice * 250) / 10000;
        emit SetTicketprice(newPrice);
    }

    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid OZ fees");
        ozFees = (amount * decimals) / 10000;
        emit SetOZFees(amount);
    }

    function setWithdrawLimit(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid withdraw limit");
        withdrawLimit = amount * decimals;
        emit SetWithdrawLimit(amount);
    }

    function setTeamPercentage(uint256 amount) external onlyOwner {
        require(amount <= 2000, "Max 20%");
        teamPercentage = (ticketPrice * amount) / 10000;
        emit SetTeamPercentage(amount);
    }

    function setRewardPoolPercentage(uint256 amount) external onlyOwner {
        require(amount <= 1000, "Max 10%");
        rewardPoolPercentage = (ticketPrice * amount) / 10000;
        emit SetRewardPoolPercentage(amount);
    }

    function setBurnPercentage(uint256 amount) external onlyOwner {
        require(amount <= 1000, "Max 10%");
        burnPercentage = (ticketPrice * amount) / 10000;
        emit SetBurnPercentage(amount);
    }

    function setTeamAddress(address newTeamAddress) external onlyOwner {
        require(newTeamAddress != address(0), "Invalid team address");
        teamAddress = newTeamAddress;
        emit SetTeamAddress(newTeamAddress);
    }

    function setRewardAddress(address newRewardPoolAddress) external onlyOwner {
        require(newRewardPoolAddress != address(0), "Invalid reward pool address");
        rewardPool = newRewardPoolAddress;
        emit SetRewardAddress(newRewardPoolAddress);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}