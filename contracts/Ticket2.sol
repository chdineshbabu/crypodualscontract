// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TicketSystem is Ownable, ReentrancyGuard, Pausable {
    // ================ Variables ================
    IERC20 public token;
    uint256 public ticketPrice;
    uint256 public teamPercentage;
    uint256 public rewardPoolPercentage;
    uint256 public burnPercentage;
    uint256 public ozFees;
    uint256 public withdrawLimit;
    address public teamAddress;
    address public rewardPool;
    address public admin;
    uint256 public decimals;
    address public baseToken;
    uint256 public tokenBalances; //To track the Total ticket balance in the contract.
    // ================ Structs ================
    struct TokenInfo {
        address tokenAddress; // Suppoted token in the contract
        address poolIdWithHoney; // The pool ID for token to Swap
    }

    struct UserInfo {
        uint256 ticketBalance; // The tickets that Each user has.
        uint256 lastWithdrawalTime; // Last withDraw timestamp
        uint256 lastDepositedTime; // Last deposited Timestamp
    }

    // ================ Mappings ================
    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => UserInfo) public userInfo;
    //=================Events=======================
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

    //==================Contructor================
    constructor() Ownable(msg.sender) {
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        rewardPoolPercentage = (ticketPrice * 250) / 10000;
        burnPercentage = (ticketPrice * 250) / 10000;
        withdrawLimit = 500 * decimals;
        ozFees = (2500 * decimals) / 10000;
        teamAddress = 0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D;
        admin = 0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D;
        rewardPool = 0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D;
        baseToken = 0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D;
    }

    //=======================View functions ==============================

    function getPrice(address _quoteToken)
        public
        view
        returns (uint256 pricePerToken)
    {
        // require(supportedTokens[_quoteToken].tokenAddress != _quoteToken, "Token doesn't Existed");
        require(_quoteToken != address(0), "Invalid token address");
        require(baseToken != address(0), "Base token not set");
        require(ticketPrice > 0, "Ticket price not set");
        if (_quoteToken == baseToken) {
            return ticketPrice;
        } else {
            // Using the price you provided
            uint256 tempTokenPrice = 6873059428165764189;
            require(tempTokenPrice > 0, "Invalid token price");

            // Calculate amount of tokens needed for one ticket
            uint256 amountOfTokenPerTicket = (ticketPrice * 1e18) /
                tempTokenPrice;
            return amountOfTokenPerTicket;
        }
    }

    // ============================= functions=====================================

    function addToken(address _token, address poolIdWithHoney)
        external
        onlyOwner
    {
        require(_token != address(0), "Invalid token address");
        require(poolIdWithHoney != address(0), "Invalid price");
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
    }
    function swapForBera() public{

    }

// function purchaseTicketDummy(address _token, uint256 _amount)external view returns (uint256 finalAmoun){
//     require(_amount > 0, "Invalid amount");
//     // require(supportedTokens[_token].tokenAddress != address(0),"Token not supported");
//     uint256 amountOfTokenPerTicket = getPrice(_token);
//     uint256 totalTokenAmount = _amount * amountOfTokenPerTicket;
//     uint256 teamAmount = (totalTokenAmount * teamPercentage) / decimals;
//     uint256 rewardPoolAmount = (totalTokenAmount * rewardPoolPercentage) / decimals;
//     uint256 burnAmount = (totalTokenAmount * burnPercentage) / decimals;
//     // uint256 ozFee = (ozFees * getPrice(_token)) / decimals;
//     uint256 totalAmount = totalTokenAmount + teamAmount + rewardPoolAmount + burnAmount;// + ozFee;
//     return totalAmount;
// }  // For checking the calculations Dummy function which is not used.

function purchaseTicket(address _token, uint256 _amount)external whenNotPaused nonReentrant {
    require(_amount > 0, "Invalid amount");
    // require(supportedTokens[_token].tokenAddress != address(0),"Token not supported");
    uint256 amountOfTokenPerTicket = getPrice(_token);
    uint256 totalTokenAmount = _amount * amountOfTokenPerTicket;
    uint256 teamAmount = (totalTokenAmount * teamPercentage) / decimals;
    uint256 rewardPoolAmount = (totalTokenAmount * rewardPoolPercentage) / decimals;
    uint256 burnAmount = (totalTokenAmount * burnPercentage) / decimals;
    uint256 totalAmount = totalTokenAmount + teamAmount + rewardPoolAmount + burnAmount;
    if(_token == baseToken){
        token = IERC20(_token);
        bool success = token.transferFrom(msg.sender, address(this), totalAmount);
        require(success,"Purchace token: Purchase token is failed");
    }else{
        swapTokenForHoney(_token, supportedTokens[_token].poolIdWithHoney);
    }
    feesTransfer(teamAmount, rewardPoolAmount, burnAmount);
    // swapForBera();
    // uint256 BeraBalance = address(this).balance;
    // (bool BeraSuccess, ) = admin.call{value: BeraBalance}("");
    // require(BeraSuccess, "Purchase Ticket: Bera transfer failed.");
    userInfo[msg.sender].ticketBalance += _amount;
    emit TicketPurchased(msg.sender, _amount,_token);
}

function withdrawTickets(uint256 numOfTicket) external whenNotPaused nonReentrant{
    require(userInfo[_msgSender()].ticketBalance >= numOfTicket,"Withdraw Ticket: Insufficient Balance");
    require(numOfTicket >= 1,"Withdraw Ticket: Amount should be greater than Zero");
    token = IERC20(baseToken);
    uint256 amount = (numOfTicket * ticketPrice) / decimals;
    uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
    uint256 rewardPoolAmount = (numOfTicket * rewardPoolPercentage) / decimals;
    uint256 burnAmount = (numOfTicket * burnPercentage) / decimals;
    require(numOfTicket <= withdrawLimit,"Withdrawal amount exceeds limit");
    require(token.balanceOf(address(this)) >= amount,"Insufficient contract balance");
    uint256 ticketAmount = amount - (teamAmount + rewardPoolAmount + burnAmount);
    userInfo[_msgSender()].lastWithdrawalTime = block.timestamp;
    userInfo[_msgSender()].ticketBalance -= numOfTicket;
    bool success = token.transfer(msg.sender, ticketAmount);
    require(success, "Withdraw Ticket: Return Failed");
    feesTransfer(teamAmount, rewardPoolAmount, burnAmount);
    emit TicketWithdrawn(msg.sender, numOfTicket, baseToken);
}

    function feesTransfer(uint256 teamAmnt,uint256 rewardPoolAmnt,uint256 burnAmnt) internal {
        token = IERC20(baseToken);
        bool teamTransfer = token.transfer(teamAddress, teamAmnt);
        require(teamTransfer, "Fees transfer: Team transfer failed");

        bool rewardPoolTransfer = token.transfer(rewardPool, rewardPoolAmnt);
        require(
            rewardPoolTransfer,
            "Fees Transfer: RewardPool transfer failed"
        );
        bool transferBurnAmountToAdmin = token.transfer(admin, burnAmnt);
        require(transferBurnAmountToAdmin, "transferBurnAmountToAdmin failed");

        emit FeesTransfered(teamAmnt, rewardPoolAmnt, burnAmnt,baseToken);
    }




    // ================ Setter Functions ================

    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    function setTicketPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid ticket price");
        ticketPrice = newPrice;
        emit SetTicketprice(newPrice);
    }

    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid OZ fees");
        ozFees = amount;
        emit SetOZFees(amount);
    }

    function setWithdrawLimit(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid withdraw limit");
        withdrawLimit = amount;
        emit SetWithdrawLimit(amount);
    }

    function setTeamPercentage(uint256 amount) external onlyOwner {
        require(amount <= 10000, "Percentage exceeds 100%");
        teamPercentage = amount;
        emit SetTeamPercentage(amount);
    }

    function setRewardPoolPercentage(uint256 amount) external onlyOwner {
        require(amount <= 10000, "Percentage exceeds 100%");
        rewardPoolPercentage = amount;
        emit SetRewardPoolPercentage(amount);
    }

    function setBurnPercentage(uint256 amount) external onlyOwner {
        require(amount <= 10000, "Percentage exceeds 100%");
        burnPercentage = amount;
        emit SetBurnPercentage(amount);
    }

    function setTeamAddress(address newTeamAddress) external onlyOwner {
        require(newTeamAddress != address(0), "Invalid team address");
        teamAddress = newTeamAddress;
        emit SetTeamAddress(newTeamAddress);
    }

    function setRewardAddress(address newRewardPoolAddress) external onlyOwner {
        require(
            newRewardPoolAddress != address(0),
            "Invalid reward pool address"
        );
        rewardPool = newRewardPoolAddress;
        emit SetRewardAddress(newRewardPoolAddress);
    }

    /**
     * @notice Pauses all contract functions
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all contract functions
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
