// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title HoneyVault
 * @dev This contract allows users to deposit and withdraw Honey tokens.
 * It includes security features such as Ownable, ReentrancyGuard, and Pausable.
 */
contract HoneyVault is Ownable, ReentrancyGuard, Pausable {
    IERC20 public honeyToken;
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

    /**
     * @dev Constructor initializes the contract with the given token address and sets the deployer as the owner and admin.
     * @param _honeyToken Address of the ERC20 token contract.
     */
    constructor() Ownable(msg.sender) {
        // honeyToken = IERC20(_honeyToken);
        honeyToken = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
        admin = msg.sender;
    }

    /**
     * @dev Allows users to deposit Honey tokens into the vault.
     * @param amount Amount of tokens to deposit.
     */
    function deposit(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");
        bool success = honeyToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        emit DepositEvent(msg.sender, amount);
    }

    /**
     * @dev Allows the admin to withdraw Honey tokens from the vault.
     * @param user Address to receive the withdrawn tokens.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(address user, uint256 amount) external onlyAdmin whenNotPaused {
        uint256 balance = honeyToken.balanceOf(address(this));
        require(balance >= amount, "Not enough balance in the vault");
        bool success = honeyToken.transfer(user, amount);
        require(success, "Token transfer failed");
        emit WithdrawEvent(user, amount);
    }

    /**
     * @dev Returns the current balance of the vault.
     * @return uint256 Balance of the vault in Honey tokens.
     */
    function vaultBalance() external view returns (uint256) {
        return honeyToken.balanceOf(address(this));
    }

    //================= Setter Functions =======================

    /**
     * @dev Sets the address of the Honey token contract.
     * @param _honeyAddress New token contract address.
     */
    function setHoneyAddress(address _honeyAddress) public onlyOwner {
        require(_honeyAddress != address(0), "Invalid token address");
        emit TokenSetEvent(_honeyAddress, address(honeyToken));
        honeyToken = IERC20(_honeyAddress);
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
}
