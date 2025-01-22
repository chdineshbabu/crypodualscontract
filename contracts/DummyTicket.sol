//SPDX-License-Identifier:MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TicketSystemCD
 * @author karan (@cryptofluencerr, https://cryptofluencerr.com)
 * @dev The TicketSystemCD contract is used for purchasing tickets for CryptoDuels.
 */

contract TicketSystemMultiToken is Ownable, ReentrancyGuard, Pausable {
    //============== VARIABLES ==============
    IUniswapV2Router02 public pancakeRouter;
    IERC20 public honeyToken;
    IERC20 public bullasToken;
    uint256 public ticketPrice;
    uint256 public teamPercentage;
    uint256 public rewardPoolPercentage;
    uint256 public burnPercentage;
    uint256 public withdrawLimit;
    uint256 public ozFees;
    address public pancakeRouterAddress;
    address public teamAddress;
    address public rewardPool;
    address public admin;
    uint256 decimals;

    address private honeyPairAddress;
    address private bullasPairAddress;

    enum PaymentToken {
        HONEY,
        BULLAS
    }

    struct UserInfo {
        uint256 ticketBalance;
        uint256 lastWithdrawalTime;
        PaymentToken lastUsedToken;
    }

    //============== MAPPINGS ==============
    mapping(address => UserInfo) public userInfo;
    mapping(string => address) public tokens;

    //============== EVENTS ==============
    event TicketPurchased(
        address indexed buyer,
        uint256 numofTicket,
        uint256 amountPaid,
        PaymentToken token
    );
    event TicketWithdrawn(
        address indexed user,
        uint256 numOfTicket,
        uint256 amountRefund,
        PaymentToken token
    );
    event FeesTransfered(
        uint256 teamAmount,
        uint256 rewardPoolAmount,
        uint256 burnAmount,
        PaymentToken token
    );

    //============== CONSTRUCTOR ==============
    constructor() Ownable(msg.sender) {
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        rewardPoolPercentage = (ticketPrice * 250) / 10000;
        burnPercentage = (ticketPrice * 250) / 10000;
        withdrawLimit = 500 * decimals;
        ozFees = (2500 * decimals) / 10000;

        // pancakeRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        // pancakeRouter = IUniswapV2Router02(pancakeRouterAddress);
        honeyToken = IERC20(tokens["HONEY"]);
        bullasToken = IERC20(tokens["BULLAS"]);
        // honeyPairAddress = ;
        // bullasPairAddress = ;
        // admin = ;
        // teamAddress = ;
        // rewardPool = ;
    }

    //============== VIEW FUNCTIONS ==============
    /**
     * @dev Function to get GQ price from Pancackeswap
     */
    function getPrice(PaymentToken token) public view returns (uint256) {
        address pairAddress = token == PaymentToken.HONEY
            ? honeyPairAddress
            : bullasPairAddress;
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
            .getReserves();
        return (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    //============== EXTERNAL FUNCTIONS ==============
    /**
     * @dev Function to Purchase Tickets
     * @param numOfTicket to select quantity of tickets to purchase
     */
    function purchaseTicket(uint256 numOfTicket, PaymentToken token)
        external
        whenNotPaused
        nonReentrant
    {
        require(
            numOfTicket >= 1,
            "Number of Ticket should be greater than Zero"
        );

        IERC20 paymentToken = token == PaymentToken.HONEY
            ? tokens["HONEY"]
            : tokens["BULLAS"]; 

        uint256 amount;
        uint256 ticketAmount = (numOfTicket * ticketPrice) / decimals;
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) /
            decimals;
        uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;
        uint256 ozFee = (ozFees * getPrice(token)) / decimals;

        amount =
            ticketAmount +
            teamAmount +
            rewardPoolAmount +
            burnAmount +
            ozFee;

        bool success = paymentToken.transferFrom(
            _msgSender(),
            address(this),
            amount
        );
        require(success, "Token transfer failed");

        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, token);
        swapTokensForEth(ozFee, token);

        uint256 BNBBalance = address(this).balance;
        (bool BNBSuccess, ) = admin.call{value: BNBBalance}("");
        require(BNBSuccess, "BNB transfer failed");

        userInfo[_msgSender()].ticketBalance += numOfTicket;
        userInfo[_msgSender()].lastUsedToken = token;

        emit TicketPurchased(_msgSender(), numOfTicket, amount, token);
    }

    /**
     * @dev Function to Withdraw Tickets
     * @param numOfTicket to select quantity of tickets to withdraw
     */

    function withdrawTicket(uint256 numOfTicket, PaymentToken token)
        external
        whenNotPaused
        nonReentrant
    {
        UserInfo storage user = userInfo[_msgSender()];
        require(user.ticketBalance >= numOfTicket, "Insufficient Balance");
        require(numOfTicket >= 1, "Amount should be greater than Zero");
    
        require(
            user.lastWithdrawalTime + 24 hours <= block.timestamp ||
                user.lastWithdrawalTime == 0,
            "Withdrawal is only allowed once every 24 hours"
        );

        IERC20 paymentToken = token == PaymentToken.HONEY
            ? tokens["HONEY"]
            : tokens["BULLAS"];

        uint256 amount = (numOfTicket * ticketPrice) / decimals;
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) / decimals;
        uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;

        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance >= amount, "Not enough balance in the contract");
        require(
            amount <= (withdrawLimit * getPrice(token)) / decimals,
            "Withdrawal amount exceeds Limit"
        );

        uint256 ticketAmount = amount -(teamAmount + rewardPoolAmount + burnAmount);

        user.lastWithdrawalTime = block.timestamp;
        user.ticketBalance -= numOfTicket;
        user.lastUsedToken = token;

        bool success = paymentToken.transfer(_msgSender(), ticketAmount);
        require(success, "Return Failed");

        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, token);

        emit TicketWithdrawn(_msgSender(), numOfTicket, ticketAmount, token);
    }

    /**
     * @notice swaps dedicated amount from GQ -> BNB
     * @param amount total GQ amount that need to be swapped to BNB
     */

    function swapTokensForEth(uint256 amount, PaymentToken token) private {
        address[] memory path = new address[](2);
        path[0] = token == PaymentToken.HONEY
            ? address(tokens["HONEY"])
            : address(tokens["BULLAS"]);
        path[1] = pancakeRouter.WETH();

        IERC20 paymentToken = token == PaymentToken.HONEY
            ? tokens["HONEY"]
            : tokens["BULLAS"];
        paymentToken.approve(address(pancakeRouter), amount);

        pancakeRouter.swapExactTokensForETH(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @notice will set the router address
     * @param _routerAddress pancake router address
     */
    function setRouterAddress(address _routerAddress) external onlyOwner {
        require(
            _routerAddress != address(0),
            "Set Router Address: Invalid router address"
        );
        pancakeRouterAddress = _routerAddress;
        pancakeRouter = IUniswapV2Router02(_routerAddress);
        emit SetRouterAddress(_routerAddress);
    }

    /**
     * @dev Function to Withdraw funds
     */
    function withdraw() external onlyOwner {
        uint256 balance = GQToken.balanceOf(address(this));
        require(balance > 0, "Withdraw: Not enough balance in the contract");
        bool success;
        success = GQToken.transfer(owner(), balance);
        require(success, "Withdraw: Withdraw Failed");
        emit TokenWithdrawn(owner(), balance);
    }

    /**
     * @dev Function to set the user's ticket balance
     * @param user address of user whose balance is to be set
     * @param amount The balance change amount to be set
     */
    function setUserBalance(address user, uint256 amount)
        external
        onlyAdmin
        whenNotPaused
        nonReentrant
    {
        require(user != address(0), "Set User Balance: Invalid user address");
        userInfo[user].ticketBalance = amount;
        emit SetUserBalance(user, amount);
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
     * @dev Function to set the new GQToken address that is used Purchasing tickets
     * @param tokenAdd The new GQToken address
     */
    function setTokenAddress(address tokenAdd, string tokenName) external onlyOwner {
        require(tokenAdd != address(0), "Set Token Address: Invalid address");
        tokens[tokenName] = tokenAdd;
        emit SetTokenAddress(tokenAdd, tokenName);
    }

    /**
     * @dev Function to set the new Pair address of GQToken pool
     * @param pairAdd The new pair address
     */
    function setpairAddress(address pairAdd) external onlyOwner {
        require(pairAdd != address(0), "Set Pair Address: Invalid address");
        pairAddress = pairAdd;
        emit SetpairAddress(pairAdd);
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
     */
    function feesTransfer(
        uint256 teamAmnt,
        uint256 rewardPoolAmnt,
        uint256 burnAmnt,
        PaymentToken token
    ) internal {
        IERC20 paymentToken = token == PaymentToken.HONEY
            ? tokens["HONEY"]
            : tokens["BULLAS"];

        bool teamTransfer = paymentToken.transfer(teamAddress, teamAmnt);
        require(teamTransfer, "Team transfer failed");

        bool rewardPoolTransfer = paymentToken.transfer(
            rewardPool,
            rewardPoolAmnt
        );
        require(rewardPoolTransfer, "RewardPool transfer failed");

        paymentToken.burn(burnAmnt);

        emit FeesTransfered(teamAmnt, rewardPoolAmnt, burnAmnt, token);
    }

    function setHoneyToken(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid address");
        honeyToken = IERC20(_tokenAddress);
    }

    function setBullasToken(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid address");
        bullasToken = IERC20(_tokenAddress);
    }

    function setHoneyPairAddress(address _pairAddress) external onlyOwner {
        require(_pairAddress != address(0), "Invalid address");
        honeyPairAddress = _pairAddress;
    }

    function setBullasPairAddress(address _pairAddress) external onlyOwner {
        require(_pairAddress != address(0), "Invalid address");
        bullasPairAddress = _pairAddress;
    }

    receive() external payable {}
}
