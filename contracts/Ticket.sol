// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrocQuery {
    function queryPrice(
        address base,
        address quote,
        uint256 poolIdx
    ) external view returns (uint128);      
}
interface ICrocSwapDex{
function multiSwap (
    SwapStep[] memory _steps,
    uint128 _amount,
    uint128 _minOut
) external  payable returns (uint128 out);
struct SwapStep {
    uint256 poolIdx;
    address base;
    address quote;
    bool isBuy;
}   
}


interface IBurnableToken is IERC20 {
    function burn(uint256 amount) external;
}

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
    address public baseToken;
    address public quoteToken;
    uint256 public poolIdx;
    uint256 public decimals;
    address public swapRouter;
    ICrocQuery public crocQuery;
    ICrocSwapDex public crocSwapDex;

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
        uint256 amountRefund,
        address token
    );
    event TicketPurchased(
        address indexed user,
        uint256 numOfTicket,
        uint256 amount,
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

    // ================ Constructor ================
    constructor(
        address _teamAddress,
        address _admin,
        address _rewardPool
    ) Ownable(msg.sender) {
        require(_teamAddress != address(0), "Invalid team address");
        require(_admin != address(0), "Invalid admin address");
        require(_rewardPool != address(0), "Invalid reward pool address");

        decimals = 10**18;
        ticketPrice = 1 * decimals;
        teamPercentage = (ticketPrice * 1000) / 10000;
        rewardPoolPercentage = (ticketPrice * 250) / 10000;
        burnPercentage = (ticketPrice * 250) / 10000;
        withdrawLimit = 500 * decimals;
        ozFees = (2500 * decimals) / 10000;
        crocQuery = ICrocQuery(0x31DAc06019D983f79cEAc819fAAC0612518597D7);
        crocSwapDex = ICrocSwapDex(0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D);

        teamAddress = _teamAddress;
        admin = _admin;
        rewardPool = _rewardPool;
        baseToken = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03; //Currently Honey token is the base token
        poolIdx = 36000;
        swapRouter = 0x21e2C0AFd058A89FCf7caf3aEA3cB84Ae977B73D;
    }

    // ================ Modifiers ================
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    //================== View Functions ==================
    function getPrice(address quoteToken) public view returns (uint128) {
        uint128 priceRoot = crocQuery.queryPrice(
            baseToken,
            quoteToken,
            poolIdx
        );

        uint256 sq = (uint256(priceRoot) * 1e18) / (2**64);
        uint256 honeyPerLick = (sq * sq) / 1e18;

        return uint128(honeyPerLick);
    }

    //================== Functions ==================
    function addToken(address _token, uint256 _priceInTokens)
        external
        onlyOwner
    {
        require(_token != address(0), "Invalid token address");
        require(_priceInTokens > 0, "Invalid price");
        require(
            supportedTokens[_token].tokenAddress == address(0),
            "Token already exists"
        );

        supportedTokens[_token] = TokenInfo(_token, _priceInTokens);
    }

    function removeToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(
            supportedTokens[_token].tokenAddress != address(0),
            "Token does not exist"
        );

        delete supportedTokens[_token];
    }

    function purchaseTicket(address _token, uint256 _amount)
        external
        whenNotPaused
        nonReentrant
    {
        require(_amount > 0, "Invalid amount");
        require(
            supportedTokens[_token].tokenAddress != address(0),
            "Token not supported"
        );

        uint256 tokenPrice = supportedTokens[_token].priceInTokens;
        uint256 totalTokenAmount = _amount * tokenPrice;

        uint256 teamAmount = (totalTokenAmount * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (totalTokenAmount * rewardPoolPercentage) /
            decimals;
        uint256 burnAmount = (totalTokenAmount * burnPercentage) / decimals;
        uint256 ozFee = (ozFees * getPrice(_token)) / decimals;

        uint256 totalAmount = totalTokenAmount +
            teamAmount +
            rewardPoolAmount +
            burnAmount +
            ozFee;

        IERC20 token = IERC20(_token);
        require(
            token.transferFrom(msg.sender, address(this), totalAmount),
            "Transfer failed"
        );

        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, _token);
        swapToken(ozFee, _token);
        uint256 ethAmount = address(this).balance;
        (bool ethSuccess, ) = admin.call{value: ethAmount}("");
        require(ethSuccess, "ETH transfer failed");

        userInfo[msg.sender].ticketBalance += _amount;
        userInfo[msg.sender].lastUsedToken = _token;

        emit TicketPurchased(msg.sender, _amount, totalAmount, _token);
    }

    function withdrawTickets(uint256 _amount, address _token)
        external
        whenNotPaused
        nonReentrant
    {
        require(_amount > 0, "Invalid amount");
        require(
            userInfo[msg.sender].ticketBalance >= _amount,
            "Insufficient balance"
        );
        require(
            block.timestamp - userInfo[msg.sender].lastWithdrawalTime >=
                withdrawLimit,
            "Withdrawal limit not reached"
        );

        IERC20 token = IERC20(_token);
        uint256 tokenPrice = supportedTokens[_token].priceInTokens;
        uint256 totalTokenAmount = _amount * tokenPrice;

        uint256 teamAmount = (totalTokenAmount * teamPercentage) / decimals;
        uint256 rewardPoolAmount = (totalTokenAmount * rewardPoolPercentage) /
            decimals;
        uint256 burnAmount = (totalTokenAmount * burnPercentage) / decimals;

        require(
            totalTokenAmount <= (withdrawLimit * getPrice(_token)) / decimals,
            "Withdrawal amount exceeds limit"
        );

        require(
            token.balanceOf(address(this)) >= totalTokenAmount,
            "Insufficient contract balance"
        );

        userInfo[msg.sender].ticketBalance -= _amount;
        userInfo[msg.sender].lastWithdrawalTime = block.timestamp;
        userInfo[msg.sender].lastUsedToken = _token;

        require(
            token.transfer(msg.sender, totalTokenAmount),
            "Transfer failed"
        );
        feesTransfer(teamAmount, rewardPoolAmount, burnAmount, _token);

        emit TicketWithdrawn(msg.sender, _amount, totalTokenAmount, _token);
    }


function swapToken(uint256 ozFee, address _token) private {
    IERC20(_token).approve(address(crocSwapDex), ozFee);
    
    ICrocSwapDex.SwapStep[] memory steps = new ICrocSwapDex.SwapStep[](1);
    steps[0] = ICrocSwapDex.SwapStep({
        poolIdx: poolIdx,
        base: _token,
        quote: baseToken,
        isBuy: false
    });
    
    crocSwapDex.multiSwap{value: 0}(
        steps,
        uint128(ozFee),
        0 
    );
}
    /**
     * @dev Function to withdraw accumulated fees
     * @param _token The token address to withdraw
     */
    function withdraw(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        require(token.transfer(owner(), balance), "Withdraw failed");
        emit TokenWithdrawn(owner(), balance);
    }

    /**
     * @dev Internal function to transfer fees
     */
    function feesTransfer(
        uint256 teamAmnt,
        uint256 rewardPoolAmnt,
        uint256 burnAmnt,
        address _token
    ) internal {
        IERC20 token = IERC20(_token);
        IBurnableToken burnableToken = IBurnableToken(_token);

        require(token.transfer(teamAddress, teamAmnt), "Team transfer failed");
        require(
            token.transfer(rewardPool, rewardPoolAmnt),
            "Reward pool transfer failed"
        );
        burnableToken.burn(burnAmnt);

        emit FeesTransfered(teamAmnt, rewardPoolAmnt, burnAmnt, _token);
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

    function setBaseToken(address _baseToken) external onlyOwner {
        require(_baseToken != address(0), "Invalid base token address");
        baseToken = _baseToken;
    }

    function setPoolIdx(uint256 _poolIdx) external onlyOwner {
        poolIdx = _poolIdx;
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
