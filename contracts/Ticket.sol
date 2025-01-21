// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrocQuery {
    function queryPrice(
        address base,
        address quote,
        uint256 poolIdx
    ) external view returns (uint128);
}


contract TicketSystem is Ownable, ReentrancyGuard, Pausable {
    // ================ Variables ================
    IERC20 public token;
    uint256 public ticketPrice;
    uint256 public teamPercentage;
    uint256 public rewardPoolPercentage;
    uint256 public burnPercentage;
    uint256 public ozFees;
    uint256 public withDrawLimit;
    address public teamAddress;
    address public rewardPool;
    address public admin;
    uint256 decimals;
    ICrocQuery crocQuery;


    // ================ Structs ================
    struct TokenInfo {
        address tokenAddress;
        uint256 priceInTokens; // Price of one ticket in this token
    }
        struct UserInfo {
        uint256 ticketBalance;
        uint256 lastWithdrawalTime;
        address lastUsedToken;
    }

    // ================ Mappings ================
    mapping(address => TokenInfo) public supportedTokens;
    mapping (address => UserInfo) as userInfo;

    // ================ Events ================
    event FeesTransfered(uint256 teamAmount,uint256 rewardPoolAmount,uint256 burnAmount,address token);
    event TicketWithdrawn(address indexed user,uint256 numOfTicket,uint256 amountRefund,PaymentToken token);
    event FeesTransfered(uint256 teamAmount,uint256 rewardPoolAmount,uint256 burnAmount,PaymentToken token);
    event TicketPurchased(address indexed user,uint256 numOfTicket,uint256 amount,PaymentToken token);
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
    // ================ Constructor ================
    constructor() Ownable(msg.sender){
        decimals = 10 ** 18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        rewardPoolPercentage = (ticketPrice * 250) / 10000;
        burnPercentage = (ticketPrice * 250) / 10000;
        withdrawLimit = 500 * decimals;
        ozFees = (2500 * decimals) / 10000;
        crocQuery = ICrocQuery(0x31DAc06019D983f79cEAc819fAAC0612518597D7);
        admin = ;
        teamAddress = ;
        rewardPool = ;
    }
    // ================ Modifiers ================
        modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }
    //================== View Functions ==================
    function getPrice(address base, address quote, uint256 poolIdx) external view returns (uint128) {
        return crocQuery.queryPrice(base, quote, poolIdx);
    }

    //================== Functions ==================

    function addToken(address _token, uint256 _priceInTokens) public {
        require(supportedTokens[_token].tokenAddress == address(0), "Token already exists");
        supportedTokens[_token] = TokenInfo(_token, _priceInTokens);
    }

    function removeToken(address _token) public {
        require(supportedTokens[_token].tokenAddress != address(0), "Token does not exist");
        delete supportedTokens[_token];
    }
    
    /**
     * @dev Function to Withdraw Tickets
     * @param _amount to select quantity of tickets to withdraw
     */

    function purchaseTicket(address _token, uint256 _amount) public {
        require(supportedTokens[_token].tokenAddress != address(0), "Token does not exist");
        require(supportedTokens[_token].priceInTokens * _amount == _amount, "Invalid amount");
        IERC20 token = IERC20(_token);
        uint256 amount;
        uint256 ticketAmount = (_amount * ticketPrice) / decimals;
        uint256 teamAmount = (_amount * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (_amount * rewardPoolPercentage) /decimals;
        uint256 burnAmount = (_amount * burnPercentage) / decimals;
        uint256 ozFee = (ozFees * getPrice()) / decimals;//getPrice parameter not yet given
        amount =
            ticketAmount +
            teamAmount +
            rewardPoolAmount +
            burnAmount+
            ozFee;
        bool success = token.transferFrom(msg.sender, address(this), supportedTokens[_token].priceInTokens * amount);
        require(success, "Token Transfer failed");
        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, token);
        swapExactTokensForETH(ozFee, token);
        uint256 ethAmount = address(this).balance;
        (bool ethSuccess, ) = admin.call{value: ethAmount}("");
        require(ethSuccess, "ETH Transfer failed");\
        userInfo[msg.sender].ticketBalance += _amount;
        userInfo[msg.sender].lastUsedToken = token;
        emit TicketPurchased(msg.sender, _amount,amount, _token);
    }
        /**
     * @dev Function to Withdraw Tickets
     * @param _amount to select quantity of tickets to withdraw
     */
    function withdrawTickets(uint256 _amount, address _token) public {
        require(userInfo[msg.sender].ticketBalance >= _amount, "Insufficient balance");
        require(block.timestamp - userInfo[msg.sender].lastWithdrawalTime >= withDrawLimit, "Withdrawal limit not reached");
        require(_amount > 0, "Amount should be greater than 0");
        IERC20 token = IERC20(_token);
        uint256 amount; 
        uint256 ticketAmount = (_amount * ticketPrice) / decimals;
        uint256 teamAmount = (_amount * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (_amount * rewardPoolPercentage) /decimals;
        uint256 burnAmount = (_amount * burnPercentage) / decimals;
        uint256 balance = token.balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance in contract");
        require(
            _amount <= (withdrawLimit * getPrice(token)) / decimals,
            "Withdrawal amount exceeds Limit"
        );
         uint256 ticketAmount = amount -(teamAmount + rewardPoolAmount + burnAmount);
        userInfo[msg.sender].ticketBalance -= _amount;
        userInfo[msg.sender].lastWithdrawalTime = block.timestamp;
        userInfo[msg.sender].lastUsedToken = _token;
        bool success = token.transfer(msg.sender, _amount)
        require(success, "Token Transfer failed");
        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, _token);
        emit TicketWithdrawn(msg.sender, numOfTicket, _amount, _token);
    }
    /**
     * @dev Function to Withdraw funds
     */
    function withdraw(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Withdraw: Not enough balance in the contract");
        bool success;
        success = token.transfer(owner(), balance);
        require(success, "Withdraw: Withdraw Failed");
        emit TokenWithdrawn(owner(), balance);
    }


    function swapTokensForEth(uint256 amount, address token) private {
        
    }
    /**
     * @dev Function to set the admin address
     * @param newAdmin The new address to set as the admin
     */
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Set Admin: Invalid address");
        admin = newAdmin;
        emit SetAdmin(admin);
    }
        /**
     * @dev Function to set the Ticket Price
     * @param newPrice The new tick price in wei for 1 ticket.
     */
    function setTicketPrice(uint256 newPrice) external onlyOwner {
        require(
            newPrice > 0,
            "Set Ticket Price: New Price should be greater than Zero"
        );
        ticketPrice = newPrice;
        emit SetTicketprice(newPrice);
    }
    /**
     * @dev Function to set the Ticket OpenZepellin Fees.
     * @param amount The new limit amount in wei.
     */
    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Set OZ Fees: OZ Fees be greater than Zero");
        ozFees = amount;
        emit SetOZFees(amount);
    }

    /**
     * @dev Function to set the Ticket withdraw limit.
     * @param amount The new limit amount in wei.
     */
    function setWithdrawLimit(uint256 amount) external onlyOwner {
        require(
            amount > 0,
            "Set Withdraw limit: Withdraw limit be greater than Zero"
        );
        withdrawLimit = amount;
        emit SetWithdrawLimit(amount);
    }

    /**
     * @dev Function to set amount that will be transfered to Team
     * @param amount The new team share amount in wei for 1 ticket price
     */
    function setTeamPercentage(uint256 amount) external onlyOwner {
        teamPercentage = amount;
        emit SetTeamPercentage(amount);
    }

    /**
     * @dev Function to set amount that will be transfered to Reward pool
     * @param amount The new reward pool share amount in wei for 1 ticket price
     */
    function setRewardPoolPercentage(uint256 amount) external onlyOwner {
        rewardPoolPercentage = amount;
        emit SetRewardPoolPercentage(amount);
    }

    /**
     * @dev Function to set GQToken amount that will be burned.
     * @param amount The new burn share amount in wei for 1 ticket price
     */
    function setBurnPercentage(uint256 amount) external onlyOwner {
        burnPercentage = amount;
        emit SetBurnPercentage(amount);
    }

    /**
     * @dev Function to set the Team address
     * @param newTeamAddress The new address to set as the Team address
     */
    function setTeamAddress(address newTeamAddress) external onlyOwner {
        require(
            newTeamAddress != address(0),
            "Set Team Address: Invalid address"
        );
        teamAddress = newTeamAddress;
        emit SetTeamAddress(teamAddress);
    }

    /**
     * @dev Function to set the admin address
     * @param newRewardPoolAddress The new address to set as the Rewardpool address
     */
    function setRewardAddress(address newRewardPoolAddress) external onlyOwner {
        require(
            newRewardPoolAddress != address(0),
            "Set Reward Address: Invalid address"
        );
        rewardPool = newRewardPoolAddress;
        emit SetRewardAddress(rewardPool);
    }

    /**
     * @notice Pauses the contract.
     * @dev This function can only be called by the contract owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev This function can only be called by the contract owner.
     */
    function unPause() external onlyOwner {
        _unpause();
    }
    /**
     * @dev Internal function to transfer the fees.
     * @param teamAmnt amount to transfer to team.
     * @param rewardPoolAmnt amount to transfer to reward pool.
     * @param burnAmnt amount to burn tokens.
     * @param _token address of the token.
     */

    function feesTransfer(uint256 teamAmnt, uint256 rewardPoolAmnt, uint256 burnAmnt, address _token) internal {
        bool teamTransfer = token.transfer(teamAddress, teamAmnt);
        require(teamTransfer, "Team Transfer failed");
        bool rewardPoolTransfer = token.transfer(rewardPool, rewardPoolAmnt);
        require(rewardPoolTransfer, "Reward Pool Transfer failed");
        token.burn(burnAmnt);
        emit FeesTransfered(teamAmnt, rewardPoolAmnt, burnAmnt, _token);

    }

    receive() external payable {}
}