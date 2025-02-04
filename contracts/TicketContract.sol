// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract TicketContract is Ownable, ReentrancyGuard, Pausable {
    //========================Varibales=========================
    IERC20 public token;
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
        address poolIdWithHoney; // The pool ID for token to Swap
    }
    struct UserInfo {
        uint256 ticketBalance; // The tickets that Each user has.
        uint256 lastDepositedTime; // Last deposited Timestamp.
    }
    // ================ Mappings ================
    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => UserInfo) public userInfo;
    //=================Events=======================
    event FeesTransfered(
        uint256 teamAmount,
        address token
    );
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

    constructor() Ownable(msg.sender){
        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        ozFees = (5000 * decimals) / 10000;
        teamAddress = msg.sender;
        admin = msg.sender;
        baseToken = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
        valutAddress = 0xb99d6Bb136764C110bA4229008170D1D3C073Abd;
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
    function addToken(address _token,address poolIdWithHoney) external onlyOwner {
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
    function swapHoneyForBera(uint256 _amount) public {
        //Logic to swap for Honey to actual bera
    }


    function purchaseTicket(address _token,uint256 numOfTicket) external payable whenNotPaused nonReentrant {
        require(numOfTicket > 0, "Invalid amount");
        uint256 ticketAmount = (numOfTicket * ticketPrice) / decimals;
        uint256 teamAmount = (numOfTicket * teamPercentage) / decimals;
        uint256 ozFee = (ozFees * getPrice(_token)) / decimals;
        uint256 totalAmount = ticketAmount + teamAmount + ozFee;
        if (_token == baseToken) {
            token = IERC20(_token);
            bool success = token.transferFrom(msg.sender, valutAddress, totalAmount);
            require(success, "Purchase token failed");
        } else {
            swapTokenForHoney(_token, supportedTokens[_token].poolIdWithHoney);
        }
        // feesTransfer(teamAmount, ozFee);
        userInfo[msg.sender].ticketBalance += numOfTicket;
        userInfo[msg.sender].lastDepositedTime = block.timestamp;
        
        emit TicketPurchased(msg.sender, numOfTicket, _token);
    }
    function feesTransfer(uint256 teamAmnt,uint256 ozFeeAmnt) internal {
        token = IERC20(baseToken);
        bool teamTransfer = token.transfer(teamAddress, teamAmnt);
        require(teamTransfer, "Team transfer failed");
        if (ozFeeAmnt > 0) {
            bool transferOZFeesToAdmin = token.transfer(admin, ozFeeAmnt);
            require(transferOZFeesToAdmin, "OZ fees transfer failed");
        }

        emit FeesTransfered(teamAmnt, baseToken);
    }
        // ================ Setter Functions ================
    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
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
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
    receive() external payable {}


}