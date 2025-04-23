//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../others/RoyaltiesV2Impl.sol";
import "./UndergroundWaifusTiers.sol";
// import "../../others/interfaces/ICrocQueryPriceFetcher.sol";
import "../../others/interfaces/IPriceOracle.sol";
import "../../others/interfaces/IPacksERC721.sol";

//============== UndergroundWaifusMinter ==============
contract UndergroundWaifusMinter is RoyaltiesV2Impl, UndergroundWaifusTiers {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using StringsUpgradeable for uint256;

    //============== VARIABLES ==============
    uint256[] private _allTokens;
    address public vault;
    IERC20Upgradeable public lickToken;
    IERC20Upgradeable public honey;
    // ICrocQueryPriceFetcher public crocQueryPriceFetcher;
    IPriceOracle public priceOracle;

    enum PaymentMethod {
        LICK,
        HONEY
    }

    //============== STRUCTS ==============
    struct PackDetails {
        uint256 cost;
        string name;
        IPacksERC721 packAddress;
        uint16 totalChest;
        uint16 totalPurchasedChest;
    }

    //============== MAPPINGS ==============
    mapping(string => PackDetails) public packDetails;
    mapping(address => mapping(string => uint8)) public whitelistedCount;

    address public investerRole;

    //============== CONSTRUCTOR ==============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _vault,
        IERC20Upgradeable _lickToken,
        IERC20Upgradeable _honey,
        address _crocQueryPriceFetcher,
        string[6] memory _unityNames,
        uint256[6] memory _cost,
        uint16[6] memory _totalChest,
        address[6] memory _packsAddress,
        string[7] memory _discPackNames,
        uint8[6] memory _disPercTier1,
        uint8[6] memory _disPercTier2,
        uint8[6] memory _disPercTier3
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __WaifusTiers_init(
            _unityNames,
            _cost,
            _discPackNames,
            _disPercTier1,
            _disPercTier2,
            _disPercTier3
        );
        vault = _vault;
        lickToken = _lickToken;
        honey = _honey;
        // crocQueryPriceFetcher = ICrocQueryPriceFetcher(_crocQueryPriceFetcher);
        priceOracle = IPriceOracle(_crocQueryPriceFetcher);
        for (uint256 i = 0; i < _unityNames.length; i++) {
            packDetails[_unityNames[i]].name = _unityNames[i];
            packDetails[_unityNames[i]].cost = _cost[i];
            packDetails[_unityNames[i]].totalChest = _totalChest[i];
            packDetails[_unityNames[i]].packAddress = IPacksERC721(
                _packsAddress[i]
            );
        }
    }

    //============== EVENTS ==============
    event SetUnityDetails(
        string _unityName,
        uint256 _cost,
        uint16 _totalChest,
        address _packAddress
    );
    event BuyPack(string _packName, address requester);

    //============== MODIFIER ==============
    modifier ifInvesterSetter() {
        require(msg.sender == investerRole, "Not investerRole setter");
        _;
    }

    //============== EXTERNAL FUNCTIONS ==============
    /// @param _packName The name of the pack to mint.
    /// @dev The cost of the request is determined by whether the caller is whitelisted, an investor, or neither.
    /// @dev Chainlink subscription should be funded sufficiently.
    /// @dev If the caller has already requested random words, the function will revert.
    function buyPack(
        string memory _packName,
        uint8 _paymentMethod,
        uint8 _tierType
    ) external whenNotPaused {
        _checkAndControlSupply(_packName);
        uint256 cost = _checkDisc(_packName, _paymentMethod, _tierType);
        if (cost > 0) {
            _makePayment(cost, _paymentMethod);
        }
        ++packDetails[_packName].totalPurchasedChest;

        packDetails[_packName].packAddress.purchasePack(_msgSender());
        emit BuyPack(_packName, _msgSender());
    }

    //============== INTERNAL FUNCTION =============
    /// @notice Functions checks whether there is adequate Packs supply
    /// @param _packName is the name for a pack
    function _checkAndControlSupply(string memory _packName) internal view {
        _checkPackDetails(_packName, 0);
    }

    /// @notice Functions checks whether there is adequate Packs supply
    /// @param _packName is the name for a pack
    function _checkPackDetails(
        string memory _packName,
        uint256 _quantity
    ) internal view {
        PackDetails memory _packs = packDetails[_packName];

        require(hashed(_packName) == hashed(_packs.name), "Not a Pack!");
        require(
            _packs.totalPurchasedChest + _quantity < _packs.totalChest,
            "Max minted!"
        );
    }

    /// @notice Functions checks whether there is adequate Packs supply
    /// @param _packName is the name for a pack
    function _checkDisc(
        string memory _packName,
        uint8 _paymentMethod,
        uint8 tierType
    ) internal returns (uint256) {
        string[] memory _discPackNames = discPackNames;
        if (_paymentMethod == uint8(PaymentMethod.LICK)) {
            uint8 count = 0;
            uint256 cost;
            if (whitelisted[_msgSender()][_packName]) {
                cost = 0;
                --whitelistedCount[_msgSender()][_packName];
                if (whitelistedCount[_msgSender()][_packName] < 1) {
                    whitelisted[_msgSender()][_packName] = false;
                }
            } else if (investers[_msgSender()][tierType].checkInvestor) {
                cost = _calcDisc(
                    _packName,
                    packDetails[_packName].cost,
                    tierType
                );

                for (uint256 i = 0; i < _discPackNames.length; i++) {
                    if (
                        investers[_msgSender()][tierType].max[
                            _discPackNames[i]
                        ] > 0
                    ) {
                        ++count;
                    }
                }
                if (count < 1) {
                    investers[_msgSender()][tierType].checkInvestor = false;
                }
            } else {
                cost = packDetails[_packName].cost;
            }
            return cost;
        }
        // If the token is honey then user need to pay full amount.
        else {
            return packDetails[_packName].cost;
        }
    }

    /// @notice Functions which control the payment
    /// @param _paymentMethod Indicates the payment method (honey or Other)
    function _makePayment(uint256 cost, uint8 _paymentMethod) internal {
        if (_paymentMethod == uint8(PaymentMethod.HONEY)) {
            _paymentWithHONEY(cost);
        } else if (_paymentMethod == uint8(PaymentMethod.LICK)) {
            _paymentWithLICK(cost);
        } else {
            revert("Make Payment: Incorrect Payment Method");
        }
    }

    /// @notice This function makes the payment in honey
    function _paymentWithHONEY(uint256 price) internal {
        bool success = false;
        success = honey.transferFrom(_msgSender(), vault, price);
        require(success, "honey Payment: Insufficient Balance.");
    }

    /// @notice This function makes the payment in other token
    /// @notice This function makes the payment in LICK tokens
    function _paymentWithLICK(uint256 honeyPrice) internal {
        // uint256 lickPrice = crocQueryPriceFetcher.getAmountsOutByLick(
        //     honeyPrice
        // );
        uint256 lickPrice = priceOracle.getAmountsOutByLick(honeyPrice);
        bool success = lickToken.transferFrom(_msgSender(), vault, lickPrice);
        require(success, "LICK Payment: Transfer failed.");
    }

    //============== ONLY OWNER FUNCTIONS =============
    /// @notice Adds a users to the whitelist.
    /// @param _users The address of the users to be added to the whitelist.
    /// @param _packName An array of pack name that the users should be whitelisted for.
    /// @dev The function sets the value of the `whitelisted[users][pack]` mapping to `true`
    function setWhitelist(
        address[] memory _users,
        string[] memory _packName,
        uint8[] memory _num
    ) external onlyOwner whenNotPaused {
        require(
            _users.length == _packName.length && _users.length == _num.length,
            "Length not same"
        );
        for (uint256 i = 0; i < _users.length; i++) {
            _checkPackDetails(_packName[i], _num[i]);
        }

        for (uint256 i = 0; i < _users.length; i++) {
            if (_num[i] == 0) whitelisted[_users[i]][_packName[i]] = false;
            else whitelisted[_users[i]][_packName[i]] = true;
            whitelistedCount[_users[i]][_packName[i]] += _num[i];
            emit SetWhiteList(_users[i], _packName[i]);
        }
    }

    /// @notice sets the investments tier for the given users
    /// @param users- the address of the users to set the investments tier for
    /// @param investments- the amount of the user's investments
    function setInvester(
        address[] memory users,
        uint32[] memory investments,
        bool enterBool
    ) external ifInvesterSetter whenNotPaused {
        string[] memory _discPackNames = discPackNames;

        require(users.length == investments.length, "Length not same");
        for (uint32 i = 0; i < users.length; i++) {
            if (enterBool) {
                _setInvester(
                    users[i],
                    investments[i],
                    _discPackNames,
                    enterBool
                );
            } else {
                _setInvesterFalse(
                    users[i],
                    investments[i],
                    _discPackNames,
                    enterBool
                );
            }
        }
    }

    function _setInvester(
        address user,
        uint32 investment,
        string[] memory _discPackNames,
        bool enterBool
    ) internal {
        _checkPackDetails("founder", 1);
        if (investment >= 1000) {
            // Tier 1
            investers[user][1].checkInvestor = enterBool;
            uint32 cal = investment / 1000;
            investers[user][1].max["founder"] += 1;

            if (investment >= 2000) {
                investers[user][1].max["seedfounders"] += cal - 1;
            }

            for (uint256 i = 1; i < _discPackNames.length; i++) {
                if (hashed(_discPackNames[i]) != hashed("founder")) {
                    _checkPackDetails(_discPackNames[i], 4);
                    investers[user][1].max[_discPackNames[i]] += 4 * cal;
                }
            }
            emit SetInvester(user, 1);
        }

        if (investment < 1000 && investment > 499) {
            // Tier 2
            investers[user][2].checkInvestor = enterBool;
            investers[user][2].max["founder"] += 1;
            for (uint256 i = 1; i < _discPackNames.length; i++) {
                if (hashed(_discPackNames[i]) != hashed("founder")) {
                    _checkPackDetails(_discPackNames[i], 2);
                    investers[user][2].max[_discPackNames[i]] += 2;
                }
            }
            emit SetInvester(user, 2);
        }

        if (investment == 0) {
            // Private Investor
            investers[user][3].checkInvestor = enterBool;
            investers[user][3].max["founder"] += 1;
            for (uint256 i = 1; i < _discPackNames.length; i++) {
                if (hashed(_discPackNames[i]) != hashed("founder")) {
                    _checkPackDetails(_discPackNames[i], 1);
                    investers[user][3].max[_discPackNames[i]] += 1;
                }
            }
            emit SetInvester(user, 3);
        }
    }

    function _setInvesterFalse(
        address user,
        uint32 investment,
        string[] memory _discPackNames,
        bool enterBool
    ) internal {
        if (investment >= 1000) {
            investers[user][1].checkInvestor = enterBool;
            for (uint256 i = 0; i < _discPackNames.length; i++) {
                investers[user][1].max[_discPackNames[i]] = 0;
            }
        }

        if (investment < 1000 && investment > 499) {
            investers[user][2].checkInvestor = enterBool;
            for (uint256 i = 0; i < _discPackNames.length; i++) {
                investers[user][2].max[_discPackNames[i]] = 0;
            }
        }

        if (investment == 0) {
            investers[user][3].checkInvestor = enterBool;
            for (uint256 i = 0; i < _discPackNames.length; i++) {
                investers[user][3].max[_discPackNames[i]] += 1;
            }
        }
    }

    /// @dev Triggers stopped state.
    /// Requirements: The contract must not be paused.
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    /// @dev Returns to normal state.
    /// Requirements: The contract must be paused.
    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    /// @notice This function updates the vault address
    /// @param newVault The new discount value
    function changeVault(address newVault) external onlyOwner {
        vault = newVault;
    }

    /// @notice This function changes the LICK Token address
    /// @param _newPaymentToken The new discount value
    function changePaymentToken(address _newPaymentToken) external onlyOwner {
        lickToken = IERC20Upgradeable(_newPaymentToken);
    }

    /// @notice Sets the address of the ERC20 token contract.
    /// @param _newhoneyToken The address of the ERC20 token contract.
    function changehoneyToken(address _newhoneyToken) external onlyOwner {
        honey = IERC20Upgradeable(_newhoneyToken);
    }

    /// @notice Sets the details for an NFT pack.
    /// @param _packName The name of the NFT pack.
    /// @param _cost The cost of the NFT pack.
    /// @param _totalChest The total number of NFT pack.
    function setNewPackDetails(
        string memory _packName,
        uint256 _cost,
        uint16 _totalChest,
        address _packAddress
    ) external onlyOwner {
        packDetails[_packName].name = _packName;
        packDetails[_packName].cost = _cost;
        packDetails[_packName].totalChest = _totalChest;
        packDetails[_packName].packAddress = IPacksERC721(_packAddress);

        emit SetUnityDetails(_packName, _cost, _totalChest, _packAddress);
    }

    /// @notice Sets the address for an NFT pack.
    /// @param _packName The array names of the NFT pack.
    /// @param _packAddress The array addresses of the NFT pack.
    function changePackAddress(
        string[] memory _packName,
        IPacksERC721[] memory _packAddress
    ) external onlyOwner {
        require(_packName.length == _packAddress.length, "Length not same.");
        for (uint256 i = 0; i < _packName.length; i++) {
            packDetails[_packName[i]].packAddress = _packAddress[i];
        }
    }

    /// @notice Sets the costs for an NFT pack.
    /// @param _packName The array names of the NFT pack.
    /// @param _packCost The array costs of the NFT pack.
    function changePackCost(
        string[] memory _packName,
        uint256[] memory _packCost
    ) external onlyOwner {
        require(_packName.length == _packCost.length, "Length not same.");
        for (uint256 i = 0; i < _packName.length; i++) {
            packDetails[_packName[i]].cost = _packCost[i];
        }
    }

    /// @notice Sets the investerSetterRole
    /// @param _investerRole The array costs of the NFT pack.
    function changeInvesterRole(address _investerRole) external onlyOwner {
        investerRole = _investerRole;
    }
}
