//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// ============== UndergroundWaifusTiers ==============
contract UndergroundWaifusTiers is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using AddressUpgradeable for address;

    //============== VARIABLES ==============
    string[] public discPackNames;

    //============== STRUCT ==============
    /// @dev Struct to store investors data
    struct Tiers {
        bool checkInvestor;
        mapping(string => uint32) max;
    }

    //============== MAPPINGS ==============
    mapping(address => mapping(uint8 => Tiers)) public investers;
    mapping(uint8 => mapping(string => uint256)) public investorsDisc;
    mapping(address => mapping(string => bool)) public whitelisted;

    //============== EVENTS ==============
    event SetInvester(address user, uint8 _tiertype);
    event SetWhiteList(address user, string packs);

    function __WaifusTiers_init(
        string[6] memory _unityNames,
        uint256[6] memory _cost,
        string[7] memory _discPackNames,
        uint8[6] memory _disPercTier1,
        uint8[6] memory _disPercTier2,
        uint8[6] memory _disPercTier3
    ) internal onlyInitializing {
        __WaifusTiers_init_unchained(
            _unityNames,
            _cost,
            _discPackNames,
            _disPercTier1,
            _disPercTier2,
            _disPercTier3
        );
    }

    function __WaifusTiers_init_unchained(
        string[6] memory _unityNames,
        uint256[6] memory _cost,
        string[7] memory _discPackNames,
        uint8[6] memory _disPercTier1,
        uint8[6] memory _disPercTier2,
        uint8[6] memory _disPercTier3
    ) internal onlyInitializing {
        {
            discPackNames = _discPackNames;

            for (uint256 i = 0; i < _unityNames.length; i++) {
                setDiscount(
                    1,
                    _unityNames[i],
                    (_cost[i] * _disPercTier1[i]) / 100
                );
                setDiscount(
                    2,
                    _unityNames[i],
                    (_cost[i] * _disPercTier2[i]) / 100
                );
                setDiscount(
                    3,
                    _unityNames[i],
                    (_cost[i] * _disPercTier3[i]) / 100
                );
            }
            setDiscount(1, "seedfounders", (_cost[5] * 10) / 100);
        }
    }

    //============== PUBLIC FUNCTION ==============
    /// @dev Function to set the discount for a specific tier and pack
    /// @param _tiertype The tier type to set the discount for
    /// @param unityname The pack to set the discount for
    /// @param cost The cost of the pack
    function setDiscount(
        uint8 _tiertype,
        string memory unityname,
        uint256 cost
    ) public onlyOwner whenNotPaused {
        investorsDisc[_tiertype][unityname] = cost;
    }

    /// @dev Function to set the discount for a specific tier and pack
    /// @param _tiertype The tier type to set the discount for
    /// @param _unityName The pack to set the discount for
    /// @param _discPercentage The cost of the pack
    function setBulkDiscount(
        uint8 _tiertype,
        string[] memory _unityName,
        uint256[] memory _discPercentage
    ) external onlyOwner whenNotPaused {
        require(_unityName.length == _discPercentage.length, "Length not same");
        for (uint256 i = 0; i < _unityName.length; i++) {
            investorsDisc[_tiertype][_unityName[i]] = _discPercentage[i];
        }
    }

    //============== EXTERNAL FUNCTIONS ==============
    /// @dev Function to set the admin address
    /// @param _investorAddress to check whether the user is an investor.
    function ifWhitelisted(
        address _investorAddress,
        string memory _unityName
    ) external view returns (bool) {
        return whitelisted[_investorAddress][_unityName];
    }

    /// @dev Function sets the packs which is going to be in d
    /// @param _discPackName name of the pack
    function setDiscPackNames(string memory _discPackName) external onlyOwner {
        discPackNames.push(_discPackName);
    }

    /// @dev retrieves the maximum number of discPackNames available for purchase at discounted cost for the given user
    /// @param user -the address of the user to retrieve maximum discPackNames available.
    /// @return max - an array of maximum pack quantities for each pack.
    function checkMaxAvailable(
        address user,
        uint8 tierType
    ) external view returns (uint32[7] memory max) {
        string[] memory pack = discPackNames;

        for (uint256 i = 0; i < pack.length; i++) {
            max[i] = investers[user][tierType].max[pack[i]];
        }
        return max;
    }

    //============== INTERNAL FUNCTIONS ==============
    /// @dev Internal function to calculate the discount for an investor
    /// @param _unityName The pack to calculate the discount for
    /// @param _cost The cost of the pack
    /// @return cal discounted cost for the investor
    function _calcDisc(
        string memory _unityName,
        uint256 _cost,
        uint8 _tierType
    ) internal returns (uint256 cal) {
        // first it will check for free Founder Pack and mint it
        if (hashed(_unityName) == hashed("founder")) {
            if (investers[_msgSender()][_tierType].max["founder"] > 0) {
                cal =
                    _cost -
                    ((investorsDisc[_tierType]["founder"] * _cost) / 100);
                --investers[_msgSender()][_tierType].max["founder"];
            }
            // then it will check for discounted Founder Pack.
            else if (
                investers[_msgSender()][_tierType].max["seedfounders"] > 0
            ) {
                cal =
                    _cost -
                    (investorsDisc[_tierType]["seedfounders"] * _cost) /
                    100;
                --investers[_msgSender()][_tierType].max["seedfounders"];
            }
            // Else full cost will be charged
            else {
                cal = _cost;
            }
        }
        // Then check for further Unity Names
        else {
            if (investers[_msgSender()][_tierType].max[_unityName] > 0) {
                cal =
                    _cost -
                    (investorsDisc[_tierType][_unityName] * _cost) /
                    100;
                --investers[_msgSender()][_tierType].max[_unityName];
            } else {
                cal = _cost;
            }
        }
        return cal;
    }

    ///  @dev creates a unique hash for the given string
    ///  @param unityName - the string to create a hash for
    ///  @return - the unique hash of the string
    function hashed(string memory unityName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(unityName));
    }
}
