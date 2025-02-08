// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
contract HoneyVault is Ownable, ReentrancyGuard, Pausable {
    IERC20 public honeyToken;
    address admin;
    event WithdrawEvent(address indexed to, uint256 amount);
    event DepositEvent(address indexed from,uint256 amount);
    event adminSetEvent(address indexed newAdmin, address indexed oldAdmin );
    event tokenSetEvent(address indexed newToken, address indexed oldToken);
    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }
    constructor() Ownable(msg.sender) {
        honeyToken = IERC20(0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03);
        admin = msg.sender;
    }
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        bool success = honeyToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Token transfer failed");
        emit DepositEvent(msg.sender, amount);
    }
    // Function to withdraw Honey tokens from the vault
function withdraw(address user, uint256 amount) external onlyAdmin {
    uint256 balance = honeyToken.balanceOf(address(this));
    require(balance >= amount, "Not enough balance in the vault");
    bool success = honeyToken.transfer(user, amount);
    require(success, "Token transfer failed");
}
    function vaultBalance() external view returns (uint256) {
        return honeyToken.balanceOf(address(this));
    }

    //=================Setter function =======================
    function setHoneyAddress(address _honeyAddress) public onlyOwner {
        honeyToken = IERC20(_honeyAddress);
        emit tokenSetEvent(_honeyAddress, address(0));
    }
    function setAdmin(address _adminAddress) public onlyOwner{
        admin = _adminAddress;
        emit adminSetEvent(_adminAddress, address(0));
    }
}
