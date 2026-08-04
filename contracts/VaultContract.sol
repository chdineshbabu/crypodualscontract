// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title DuelsVault
 * @dev Pooled custody of the base token for the Crypto Duels game. Users (or the
 * TicketContract) deposit the base token; a dedicated `admin` withdraws to pay out.
 * Includes Ownable, ReentrancyGuard, and Pausable protections.
 */
contract DuelsVault is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public baseToken;
    address public admin;

    event WithdrawEvent(address indexed to, uint256 amount);
    event DepositEvent(address indexed from, uint256 amount);
    event AdminSetEvent(address indexed newAdmin, address indexed oldAdmin);
    event TokenSetEvent(address indexed newToken, address indexed oldToken);
    event PausedStateChanged(bool isPaused);

    /**
     * @dev Modifier to restrict function access to the admin.
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _baseToken) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_baseToken != address(0), "Invalid token address");
        baseToken = IERC20(_baseToken);
        admin = msg.sender;
    }

    /**
     * @dev Allows users to deposit base tokens into the vault.
     * @param amount Amount of tokens to deposit.
     */
    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        emit DepositEvent(msg.sender, amount);
    }

    /**
     * @dev Allows the admin to withdraw base tokens from the vault.
     * @param user Address to receive the withdrawn tokens.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(address user, uint256 amount) external onlyAdmin whenNotPaused nonReentrant {
        require(user != address(0), "Invalid recipient");
        uint256 balance = baseToken.balanceOf(address(this));
        require(balance >= amount, "Not enough balance in the vault");
        baseToken.safeTransfer(user, amount);
        emit WithdrawEvent(user, amount);
    }

    /**
     * @dev Returns the current balance of the vault.
     * @return uint256 Balance of the vault in base tokens.
     */
    function vaultBalance() external view returns (uint256) {
        return baseToken.balanceOf(address(this));
    }

    //================= Setter Functions =======================

    /**
     * @dev Sets the address of the base token contract.
     * @param _baseToken New token contract address.
     */
    function setBaseToken(address _baseToken) public onlyOwner {
        require(_baseToken != address(0), "Invalid token address");
        // Switching the custody token while the current one still has a balance would
        // strand those funds (no code path withdraws a non-current token). Require the
        // vault be emptied of the current token first.
        require(baseToken.balanceOf(address(this)) == 0, "Withdraw current token first");
        emit TokenSetEvent(_baseToken, address(baseToken));
        baseToken = IERC20(_baseToken);
    }

    /**
     * @dev Sets a new admin address.
     * @param _adminAddress New admin address.
     */
    function setAdmin(address _adminAddress) public onlyOwner {
        require(_adminAddress != address(0), "Invalid admin address");
        emit AdminSetEvent(_adminAddress, admin);
        admin = _adminAddress;
    }

    /**
     * @dev Allows the owner to pause or unpause the contract.
     * @param _pauseState Boolean indicating whether to pause (true) or unpause (false) the contract.
     */
    function setPaused(bool _pauseState) public onlyOwner {
        if (_pauseState) {
            _pause();
        } else {
            _unpause();
        }
        emit PausedStateChanged(_pauseState);
    }

    /// @dev Reserved storage to allow appending state in future upgrades without collisions.
    uint256[50] private __gap;
}
