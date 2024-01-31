// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./EarthERC20Token.sol";
import "./EarthTreasury.sol";
import "./EarthStaking.sol";
import "./SoulBound.sol";

// error ZERO_ADDRESS();
error REQ_INPUT_GREATER_THAN_ZERO();
error MUST_OWN_NFT();

/**
 * Presale campaign, which lets users mint and stake based on current IV and a whitelist
 */
contract Presale is PausableUpgradeable, OwnableUpgradeable {
    IERC20 public STABLEC; // STABLEC contract address
    EarthERC20Token public EARTH; // EARTH ERC20 contract
    EarthTreasury public TREASURY;
    EarthStaking public STAKING;
    SoulBound public SOULBOUND; // New Staking contract

    // Presale mint multiple
    uint256 public mintMultiple;

    // Decimal mint multiple
    //uint256 public decimalMintMultiple = 10;

    event MintComplete(
        address indexed minter,
        uint256 acceptedStablec,
        uint256 mintedEarth,
        uint256 mintedFruit
    );

    event NftAddressUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    event MintMultipleUpdated(uint256 newMintMultiple);

    mapping(uint256 => bool) public mintedRecord;

    function initialize(
        IERC20 _STABLEC,
        EarthERC20Token _EARTH,
        EarthStaking _STAKING,
        EarthTreasury _TREASURY,
        uint256 _mintMultiple,
        SoulBound _SOULBOUND
    ) public initializer {
        if (
            address(_STABLEC) == address(0) ||
            address(_EARTH) == address(0) ||
            address(_STAKING) == address(0) ||
            address(_TREASURY) == address(0) ||
            address(_SOULBOUND) == address(0)
        ) {
            revert ZERO_ADDRESS();
        }

        STABLEC = _STABLEC;
        EARTH = _EARTH;
        STAKING = _STAKING;
        TREASURY = _TREASURY;
        mintMultiple = _mintMultiple;
        SOULBOUND = _SOULBOUND;
        __Ownable_init();
    }

    function updateNftAddress(SoulBound _SOULBOUND) external onlyOwner {
        if (address(_SOULBOUND) == address(0)) {
            revert ZERO_ADDRESS();
        }
        emit NftAddressUpdated(address(SOULBOUND), address(_SOULBOUND));
        SOULBOUND = _SOULBOUND;
    }

    function updateMintMultiple(uint256 _mintMultiple) external onlyOwner {
        if (_mintMultiple == 0) {
            revert REQ_INPUT_GREATER_THAN_ZERO();
        }
        mintMultiple = _mintMultiple;
        emit MintMultipleUpdated(_mintMultiple);
    }

    /**
     * Pause contract. Either emergency or at the end of presale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * Revert pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function mint(uint256 _amountPaidStablec) external whenNotPaused {
        if (SOULBOUND.balanceOf(msg.sender) <= 0) {
            revert MUST_OWN_NFT();
        }
        if (_amountPaidStablec == 0) {
            revert REQ_INPUT_GREATER_THAN_ZERO();
        }

        (uint256 _stablec, uint256 _earth) = TREASURY.intrinsicValueRatio();

        uint256 _earthMinted = (10e18 * _amountPaidStablec * _earth) /
            _stablec /
            mintMultiple;

        SafeERC20.safeTransferFrom(
            STABLEC,
            msg.sender,
            address(TREASURY),
            _amountPaidStablec
        );

        EARTH.mint(msg.sender, _earthMinted);
    }
}
