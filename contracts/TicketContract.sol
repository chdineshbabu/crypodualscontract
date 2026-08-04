// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV3.sol";

/**
 * @title TicketContract (Uniswap V3)
 * @notice Ticket-purchase contract for the Crypto Duels game on Robinhood Chain.
 *
 * Payment model — EXACT OUTPUT:
 *  - Tickets are priced in a base stablecoin (USDG). A purchase must deliver EXACTLY
 *    `totalAmount` base tokens (ticket + team + oz fee).
 *  - Paying in the base token: transferred directly.
 *  - Paying in native ETH or an allowlisted ERC-20: the contract swaps the input for
 *    exactly `totalAmount` base via Uniswap V3 `SwapRouter02.exactOutput`, capped at a
 *    caller-supplied `amountInMaximum`, and refunds the unspent input.
 *
 * Why the caller supplies the quote/bounds:
 *  - Uniswap V3's QuoterV2 is not a `view` function (it reverts to return its result),
 *    so it cannot be called cheaply on-chain like V2's `getAmountsOut`. The backend
 *    quotes off-chain (QuoterV2 staticcall) and passes `amountInMaximum`, the V3 `path`,
 *    and a `deadline` into `purchaseTicket`. This is the standard V3 integration pattern.
 *
 * Hardening:
 *  - SafeERC20 everywhere (tolerates non-standard/meme ERC-20s that don't return bool).
 *  - Strict allowlist: only `baseToken`, native ETH, or `addToken`-ed tokens are accepted.
 *  - Optional Chainlink deviation bound (off by default) to reject swaps whose effective
 *    price is manipulated too far from the oracle.
 *  - NOTE: fee-on-transfer / rebasing input tokens are NOT supported by Uniswap V3
 *    exact-output; do not allowlist them.
 *
 * Upgradeable via a transparent proxy (fresh deployment on Robinhood Chain).
 */
contract TicketContract is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // ======================== State ========================
    address public baseToken;              // base stablecoin (USDG)
    address public WETH;                    // wrapped native (for ETH swaps / feed lookup)
    IV3SwapRouter public swapRouter;        // Uniswap V3 SwapRouter02

    uint256 public ticketPrice;             // price per ticket, in base-token units (10**baseDecimals)
    uint256 public teamPercentage;          // team cut per ticket, base-token units
    uint256 public ozFees;                  // oz fee per ticket, base-token units
    address public teamAddress;
    address public admin;
    uint256 public baseUnit;                // 10**baseToken.decimals() — one whole base token (e.g. 1e6 for USDG)
    uint256 public ticketScale;             // numOfTicket scaling factor (1e18 == 1 ticket)
    address public valutAddress;            // vault (receives the ticket portion)
    uint256 public slippageTolerance;       // advisory bps; the backend uses it to size amountInMaximum

    // Optional Chainlink oracle bound (off while maxOracleDeviationBps == 0)
    mapping(address => address) public priceFeeds; // token => Chainlink USD feed
    uint256 public maxOracleDeviationBps;          // e.g. 500 = 5%; 0 disables the check
    uint256 public maxOracleStaleness;             // max age (seconds) of a Chainlink round before it is rejected

    // ======================== Structs ========================
    struct TokenInfo { address tokenAddress; }
    struct UserInfo { uint256 ticketBalance; uint256 lastDepositedTime; }

    // ======================== Mappings ========================
    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => UserInfo) public userInfo;

    // ======================== Events ========================
    event TicketPurchased(address indexed user, uint256 numOfTicket, address token);
    event PaymentRefunded(address indexed user, address token, uint256 amount);
    event SetTokenAddress(address tokenAddr);
    event RemoveTokenAddress(address tokenAddr);
    event SetTicketprice(uint256 price);
    event SetTeamPercentage(uint256 teamPercent);
    event SetOZFees(uint256 ozFees);
    event SetTeamAddress(address teamAddr);
    event SetAdmin(address newAdmin);
    event SetRouterAddress(address routerAddress);
    event SetVaultAddress(address vaultAddress);
    event SetBaseTokens(address newBaseTokenAddress);
    event SetSlippageTolerance(uint256 slippageTolerance);
    event SetPriceFeed(address indexed token, address feed);
    event SetMaxOracleDeviation(uint256 bps);
    event SetMaxOracleStaleness(uint256 maxAge);
    event RescueERC20(address indexed token, address indexed to, uint256 amount);
    event RescueETH(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _baseToken,
        address _valutAddress,
        address _WETH,
        address _swapRouter
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_baseToken != address(0), "Invalid base token");
        require(_valutAddress != address(0), "Invalid vault");
        require(_WETH != address(0), "Invalid WETH");
        require(_swapRouter != address(0), "Invalid router");

        // Derive the base-token unit from its ERC-20 decimals (USDG = 6 -> 1e6), so the
        // economics are correct regardless of the base token's decimals.
        baseUnit = 10 ** IERC20Metadata(_baseToken).decimals();
        ticketScale = 1e18;                             // numOfTicket is 1e18-scaled per ticket
        ticketPrice = 1 * baseUnit;                     // 1 base token (e.g. 1 USDG)
        teamPercentage = (ticketPrice * 1000) / 10000;  // 10% of ticketPrice
        ozFees = (ticketPrice * 2500) / 10000;          // 25% of ticketPrice
        slippageTolerance = 50;                         // 0.5% (advisory)
        maxOracleStaleness = 3600;                      // 1h default; only used when the oracle bound is enabled

        teamAddress = msg.sender;
        admin = msg.sender;
        baseToken = _baseToken;
        valutAddress = _valutAddress;
        WETH = _WETH;
        swapRouter = IV3SwapRouter(_swapRouter);
    }

    // ======================== Purchase ========================

    /**
     * @notice Purchase tickets, paying in the base token, native ETH, or an allowlisted ERC-20.
     * @param _token          Payment token (`address(0)` for native ETH).
     * @param numOfTicket     Number of tickets to buy (scaled by `decimals`, matching ticketPrice).
     * @param amountInMaximum Max input token/ETH to spend on the swap (ignored when paying in base token).
     *                        Compute off-chain via QuoterV2 + slippage. Unspent input is refunded.
     * @param swapPath        Uniswap V3 exact-output path (reverse-encoded: baseToken, fee, ..., tokenIn).
     *                        Ignored when `_token == baseToken`.
     * @param deadline        Latest block timestamp this purchase may execute.
     */
    function purchaseTicket(
        address _token,
        uint256 numOfTicket,
        uint256 amountInMaximum,
        bytes calldata swapPath,
        uint256 deadline
    ) external payable whenNotPaused nonReentrant {
        require(numOfTicket > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline passed");

        uint256 ticketAmount = (numOfTicket * ticketPrice) / ticketScale;
        uint256 teamAmount = (numOfTicket * teamPercentage) / ticketScale;
        uint256 ozFee = (numOfTicket * ozFees) / ticketScale;
        uint256 totalAmount = ticketAmount + teamAmount + ozFee;
        require(totalAmount > 0, "Zero total");

        uint256 refundAmount;

        if (_token == baseToken) {
            // Direct payment in the base token — no swap.
            require(msg.value == 0, "No ETH expected");
            IERC20(baseToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        } else if (_token == address(0)) {
            // Native ETH -> base token, exact output.
            require(amountInMaximum > 0, "Zero max in");
            require(msg.value >= amountInMaximum, "Insufficient ETH");
            uint256 spentEth = _swapEthForExactBase(totalAmount, amountInMaximum, swapPath);
            _requireOracleBound(WETH, spentEth, totalAmount);
            refundAmount = msg.value - spentEth; // refunded at the end
        } else {
            // Allowlisted ERC-20 -> base token, exact output.
            require(msg.value == 0, "No ETH expected");
            require(supportedTokens[_token].tokenAddress != address(0), "Token not supported");
            require(amountInMaximum > 0, "Zero max in");
            IERC20(_token).safeTransferFrom(msg.sender, address(this), amountInMaximum);
            uint256 spent = _swapTokenForExactBase(_token, totalAmount, amountInMaximum, swapPath);
            _requireOracleBound(_token, spent, totalAmount);
            uint256 leftover = amountInMaximum - spent;
            if (leftover > 0) {
                IERC20(_token).safeTransfer(msg.sender, leftover);
                emit PaymentRefunded(msg.sender, _token, leftover);
            }
        }

        // At this point the contract holds exactly `totalAmount` base tokens. Distribute.
        IERC20(baseToken).safeTransfer(teamAddress, teamAmount);
        IERC20(baseToken).safeTransfer(valutAddress, ticketAmount);
        IERC20(baseToken).safeTransfer(admin, ozFee);

        userInfo[msg.sender].ticketBalance += numOfTicket;
        userInfo[msg.sender].lastDepositedTime = block.timestamp;
        emit TicketPurchased(msg.sender, numOfTicket, _token);

        // External value transfer last (CEI); nonReentrant also guards.
        if (refundAmount > 0) {
            (bool ok, ) = payable(msg.sender).call{value: refundAmount}("");
            require(ok, "ETH refund failed");
            emit PaymentRefunded(msg.sender, address(0), refundAmount);
        }
    }

    // ======================== Swap helpers ========================

    /// @dev Swaps an allowlisted ERC-20 for exactly `amountOut` base tokens. Returns input spent.
    function _swapTokenForExactBase(
        address tokenIn,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata path
    ) internal returns (uint256 spent) {
        require(path.length > 0, "Path required");
        IERC20(tokenIn).forceApprove(address(swapRouter), amountInMaximum);
        spent = swapRouter.exactOutput(
            IV3SwapRouter.ExactOutputParams({
                path: path,
                recipient: address(this),
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            })
        );
        // Reset allowance so no residual approval lingers.
        IERC20(tokenIn).forceApprove(address(swapRouter), 0);
    }

    /// @dev Swaps native ETH for exactly `amountOut` base tokens via multicall(exactOutput, refundETH).
    ///      Forwards `amountInMaximum` as value; the router wraps only what it needs and refunds the rest.
    function _swapEthForExactBase(
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata path
    ) internal returns (uint256 spent) {
        require(path.length > 0, "Path required");
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            IV3SwapRouter.exactOutput.selector,
            IV3SwapRouter.ExactOutputParams({
                path: path,
                recipient: address(this),
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            })
        );
        calls[1] = abi.encodeWithSelector(IV3SwapRouter.refundETH.selector);
        bytes[] memory results = swapRouter.multicall{value: amountInMaximum}(calls);
        spent = abi.decode(results[0], (uint256));
    }

    // ======================== Optional oracle bound ========================

    /// @dev Reverts if the swap's effective price deviates from the Chainlink cross-rate by
    ///      more than `maxOracleDeviationBps`. No-op unless enabled AND both feeds are set.
    ///      Requires the two feeds to share the same decimals (Chainlink USD feeds are 8).
    ///      Off by default — TEST ON TESTNET before enabling on mainnet.
    function _requireOracleBound(address token, uint256 spent, uint256 baseOut) internal view {
        if (maxOracleDeviationBps == 0) return;
        address tf = priceFeeds[token];
        address bf = priceFeeds[baseToken];
        if (tf == address(0) || bf == address(0)) return;

        (uint80 tRound, int256 tp, , uint256 tUpdated, uint80 tAnswered) =
            AggregatorV3Interface(tf).latestRoundData();
        (uint80 bRound, int256 bp, , uint256 bUpdated, uint80 bAnswered) =
            AggregatorV3Interface(bf).latestRoundData();
        require(tp > 0 && bp > 0, "Bad oracle price");
        // Round must be complete (answeredInRound >= roundId) and fresh (updatedAt within the
        // staleness window). A zero/old updatedAt underflows or exceeds the bound and reverts.
        require(tAnswered >= tRound && bAnswered >= bRound, "Stale oracle round");
        require(
            block.timestamp - tUpdated <= maxOracleStaleness &&
                block.timestamp - bUpdated <= maxOracleStaleness,
            "Oracle price too old"
        );
        require(
            AggregatorV3Interface(tf).decimals() == AggregatorV3Interface(bf).decimals(),
            "Feed decimals mismatch"
        );

        uint256 tDec = IERC20Metadata(token).decimals();
        uint256 bDec = IERC20Metadata(baseToken).decimals();
        // Oracle-implied input to obtain `baseOut` of base token:
        //   implied = baseOut * (basePrice/tokenPrice) * 10^tokenDec / 10^baseDec
        uint256 implied = (baseOut * uint256(bp) * (10 ** tDec)) / (uint256(tp) * (10 ** bDec));
        uint256 diff = spent > implied ? spent - implied : implied - spent;
        require(diff * 10000 <= implied * maxOracleDeviationBps, "Oracle deviation exceeded");
    }

    // ======================== Allowlist ========================

    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_token != baseToken, "Base token is implicit");
        require(supportedTokens[_token].tokenAddress == address(0), "Token already exists");
        supportedTokens[_token] = TokenInfo({tokenAddress: _token});
        emit SetTokenAddress(_token);
    }

    function removeToken(address _token) external onlyOwner {
        require(supportedTokens[_token].tokenAddress != address(0), "Token does not exist");
        delete supportedTokens[_token];
        emit RemoveTokenAddress(_token);
    }

    // ======================== Admin setters ========================

    function setAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    function setVaultAddress(address newVault) external onlyOwner {
        require(newVault != address(0), "Invalid Vault address");
        valutAddress = newVault;
        emit SetVaultAddress(newVault);
    }

    function setRouterAddress(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        swapRouter = IV3SwapRouter(_router);
        emit SetRouterAddress(_router);
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance > 0 && _slippageTolerance <= 1000, "Invalid slippage: 0-10%");
        slippageTolerance = _slippageTolerance;
        emit SetSlippageTolerance(_slippageTolerance);
    }

    /// @notice Change the base token. Also refreshes `baseUnit` from the new token's
    ///         decimals. If decimals differ, re-set `ticketPrice`/`ozFees` afterwards.
    function setBaseToken(address newBaseToken) external onlyOwner {
        require(newBaseToken != address(0), "Invalid base token address");
        baseToken = newBaseToken;
        baseUnit = 10 ** IERC20Metadata(newBaseToken).decimals();
        emit SetBaseTokens(newBaseToken);
    }

    function setOZFees(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid OZ fees");
        ozFees = (amount * baseUnit) / 10000; // `amount` in bps of one base token
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

    function setTicketPrice(uint256 price) external onlyOwner {
        require(price > 0, "Invalid ticket price");
        ticketPrice = price * baseUnit; // `price` is a whole-token count (e.g. 2 => 2 USDG)
        // Reset both derived fees to their default share of the new price (team 10%, oz 25%),
        // matching initialize(). Override afterwards with setTeamPercentage / setOZFees if needed.
        teamPercentage = (ticketPrice * 1000) / 10000;
        ozFees = (ticketPrice * 2500) / 10000;
        emit SetTicketprice(price);
    }

    /// @notice Configure the Chainlink USD feed for a token (or the base token). Set both a
    ///         token feed and the base-token feed, then a non-zero deviation, to enable the bound.
    function setPriceFeed(address token, address feed) external onlyOwner {
        require(token != address(0), "Invalid token");
        priceFeeds[token] = feed; // feed == address(0) clears it
        emit SetPriceFeed(token, feed);
    }

    /// @notice Set the max allowed swap-vs-oracle deviation in bps (0 disables the check).
    function setMaxOracleDeviation(uint256 bps) external onlyOwner {
        require(bps <= 10000, "Max 100%");
        maxOracleDeviationBps = bps;
        emit SetMaxOracleDeviation(bps);
    }

    /// @notice Set the max age (seconds) a Chainlink round may be before the oracle bound
    ///         rejects it. Only consulted while the bound is enabled (maxOracleDeviationBps > 0).
    function setMaxOracleStaleness(uint256 maxAge) external onlyOwner {
        require(maxAge > 0, "Invalid staleness");
        maxOracleStaleness = maxAge;
        emit SetMaxOracleStaleness(maxAge);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ======================== Rescue ========================
    // The contract is designed to hold ~0 assets between purchases (each buy nets to zero),
    // so anything sitting here was sent by mistake. These let the owner recover it.

    /// @notice Recover ERC-20 tokens accidentally sent to (or stranded in) this contract.
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit RescueERC20(token, to, amount);
    }

    /// @notice Recover native ETH accidentally sent to (or stranded in) this contract.
    function rescueETH(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "ETH rescue failed");
        emit RescueETH(to, amount);
    }

    /// @notice Accept ETH (needed to receive `refundETH` surplus from the router).
    receive() external payable {}

    /// @dev Reserved storage to allow appending state in future upgrades without collisions.
    uint256[50] private __gap;
}
