pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EarthERC20Token.sol";
import "./ITreasuryAllocation.sol";
import "./MintAllowance.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// import "hardhat/console.sol";

error DistributionPercent_GreaterThan100();
error CannotHarvest();
error MintAllocateLessThanZero();
error AmountStablecLessThanZero();
error Harvert_Less_Than_Zero();
error PoolSpecifiedNotFound();
error ZEROS_ADDRESS();
error OWNER_ALREADY_SEEDED();
error NO_UNUSED_EARTH();
error NO_SUCCESS();

contract EarthTreasury is OwnableUpgradeable {
    // Underlying Earth token
    EarthERC20Token private _EARTH;

    // underlying stable token we are holding and valuing treasury with
    IERC20 private _STABLEC;

    // Minted earth allocated to various investment contracts
    MintAllowance public MINT_ALLOWANCE;

    // Ratio of treasury value in stablec to open supply of earth.
    struct IntrinsicValueRatio {
        uint256 stablec;
        uint256 earth;
    }
    IntrinsicValueRatio public intrinsicValueRatio;

    // Earth rewards harvested, and (yet) to be allocated to a pool
    uint256 public harvestedRewardsEarth;

    // Has treasury been seeded with STABLEC yet (essentially, has seedMint been called)
    // this will bootstrap IV
    bool public seeded;

    // all active pools. A pool is anything
    // that gets allocated some portion of harvest
    address[] public pools;
    mapping(address => uint96) public poolHarvestShare;
    uint96 public totalHarvestShares;

    // Current treasury STABLEC allocations
    mapping(ITreasuryAllocation => uint256) public treasuryAllocationsStablec;
    uint256 public totalAllocationStablec;

    event RewardsHarvested(uint256 _amount);
    event HarvestDistributed(address indexed _contract, uint256 _amount);

    function initialize(
        EarthERC20Token _earth,
        IERC20 _stablec
    ) public initializer {
        if (address(_earth) == address(0)) {
            revert ZEROS_ADDRESS();
        }
        if (address(_stablec) == address(0)) {
            revert ZEROS_ADDRESS();
        }
        _EARTH = _earth;
        _STABLEC = _stablec;
        MINT_ALLOWANCE = new MintAllowance(_EARTH);
        __Ownable_init();
    }

    function numPools() external view returns (uint256) {
        return pools.length;
    }

    /**
     * Seed treasury with STABLEC and Earth to bootstrap
     */

    event TreasurySeeded(uint256 amountStablec, uint256 amountEarth);

    function seedMint(
        uint256 amountStablec,
        uint256 amountEarth
    ) external onlyOwner {
        if (seeded) {
            revert OWNER_ALREADY_SEEDED();
        }
        seeded = true;

        // can this go in the constructor?
        intrinsicValueRatio.stablec = amountStablec;
        intrinsicValueRatio.earth = amountEarth;

        SafeERC20.safeTransferFrom(
            _STABLEC,
            msg.sender,
            address(this),
            amountStablec
        );
        _EARTH.mint(msg.sender, amountEarth);

        emit TreasurySeeded(amountStablec, amountEarth);
    }

    /**
     * Harvest rewards.
     *
     * For auditing, we harvest and allocate in two steps
     */
    function harvest(uint256 distributionPercent) external onlyOwner {
        if (distributionPercent > 100) {
            revert DistributionPercent_GreaterThan100();
        }

        uint256 reserveStablec = _STABLEC.balanceOf(address(this)) +
            totalAllocationStablec;

        // Burn any excess earth, that is Any earth over and beyond harvestedRewardsEarth.
        if (_EARTH.balanceOf(address(this)) > harvestedRewardsEarth) {
            _EARTH.burn(
                _EARTH.balanceOf(address(this)) - harvestedRewardsEarth
            );
        }

        // Burn any excess earth, that is Any earth over and beyond harvestedRewardsEarth.
        // NOTE: If we don't do this, IV could drop...
        if (_EARTH.balanceOf(address(this)) > harvestedRewardsEarth) {
            // NOTE: there isn't a Reentrancy issue as we control the EARTH ERC20 contract, and configure
            //       treasury with an address on contract creation
            _EARTH.burn(
                _EARTH.balanceOf(address(this)) - harvestedRewardsEarth
            );
        }

        uint256 totalSupplyEarth = _EARTH.totalSupply() -
            _EARTH.balanceOf(address(MINT_ALLOWANCE));
        uint256 impliedSupplyAtCurrentIVEarth = (reserveStablec *
            intrinsicValueRatio.earth) / intrinsicValueRatio.stablec;

        if (impliedSupplyAtCurrentIVEarth < totalSupplyEarth) {
            revert CannotHarvest();
        }

        uint256 newHarvestEarth = ((impliedSupplyAtCurrentIVEarth -
            totalSupplyEarth) * distributionPercent) / 100;
        harvestedRewardsEarth += newHarvestEarth;

        intrinsicValueRatio.stablec = reserveStablec;
        intrinsicValueRatio.earth = totalSupplyEarth + newHarvestEarth;

        _EARTH.mint(address(this), newHarvestEarth);
        emit RewardsHarvested(newHarvestEarth);
    }

    /**
     * ResetIV
     *
     * Not expected to be used in day to day operations, as opposed to harvest which
     * will be called ~ once per epoch.
     *
     * Only to be called if we have to post a treasury loss, and restart IV growth from
     * a new baseline.
     */
    event IntrinsicValueReset(
        uint256 newStablecReserve,
        uint256 newEarthSupply
    );

    function resetIV() external onlyOwner {
        uint256 reserveStablec = _STABLEC.balanceOf(address(this)) +
            totalAllocationStablec;
        uint256 totalSupplyEarth = _EARTH.totalSupply() -
            _EARTH.balanceOf(address(MINT_ALLOWANCE));
        intrinsicValueRatio.stablec = reserveStablec;
        intrinsicValueRatio.earth = totalSupplyEarth;

        emit IntrinsicValueReset(reserveStablec, totalSupplyEarth);
    }

    /**
     * Allocate rewards to each pool.
     */
    function distributeHarvest() external onlyOwner {
        // transfer rewards as per defined allocation
        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 allocatedRewards = (harvestedRewardsEarth *
                poolHarvestShare[pools[i]]) / totalHarvestShares;

            // integer rounding may cause the last allocation to exceed harvested
            // rewards. Handle gracefully
            if ((totalAllocated + allocatedRewards) > harvestedRewardsEarth) {
                allocatedRewards = harvestedRewardsEarth - totalAllocated;
            }
            totalAllocated += allocatedRewards;
            SafeERC20.safeTransfer(_EARTH, pools[i], allocatedRewards);
            emit HarvestDistributed(pools[i], allocatedRewards);
        }
        harvestedRewardsEarth -= totalAllocated;
    }

    /**
     * Mint and Allocate treasury EARTH.
     */

    event EarthMintedAndAllocated(
        address indexed contractAddress,
        uint256 amountEarth
    );

    function mintAndAllocateEarth(
        address _contract,
        uint256 amountEarth
    ) external onlyOwner {
        if (amountEarth <= 0) {
            revert MintAllocateLessThanZero();
        }

        // Mint and Allocate EARTH via MINT_ALLOWANCE helper
        _EARTH.mint(address(this), amountEarth);
        SafeERC20.safeIncreaseAllowance(
            _EARTH,
            address(MINT_ALLOWANCE),
            amountEarth
        );
        MINT_ALLOWANCE.increaseMintAllowance(_contract, amountEarth);

        // Update intrinsic value ratio
        intrinsicValueRatio.earth += amountEarth;

        emit EarthMintedAndAllocated(_contract, amountEarth);
    }

    /**
     * Burn minted earth associated with a specific contract
     */
    function unallocateAndBurnUnusedMintedEarth(
        address _contract
    ) external onlyOwner {
        // Get the amount of unused minted Earth tokens
        uint256 unusedMintedEarth = MINT_ALLOWANCE.getUnusedMintAllowance(
            _contract
        );
        if (unusedMintedEarth <= 0) {
            revert NO_UNUSED_EARTH();
        }

        // Burn unused minted Earth tokens
        MINT_ALLOWANCE.burnUnusedMintAllowance(_contract);

        // Update intrinsic value ratio by subtracting the burned Earth tokens
        intrinsicValueRatio.earth -= unusedMintedEarth;
    }

    /**
     * Allocate treasury STABLEC.
     */
    event TreasuryStablecAllocated(
        address indexed contractAddress,
        uint256 amountStablec
    );

    function allocateTreasuryStablec(
        ITreasuryAllocation _contract,
        uint256 amountStablec
    ) external onlyOwner {
        if (amountStablec <= 0) {
            revert AmountStablecLessThanZero();
        }

        treasuryAllocationsStablec[_contract] += amountStablec;
        totalAllocationStablec += amountStablec;
        SafeERC20.safeTransfer(_STABLEC, address(_contract), amountStablec);

        emit TreasuryStablecAllocated(address(_contract), amountStablec);
    }

    /**
     * Update treasury with latest mark to market for a given treasury allocation
     */
    event MarkToMarketUpdated(
        address indexed contractAddress,
        uint256 oldReval,
        uint256 newReval
    );

    function updateMarkToMarket(
        ITreasuryAllocation _contract
    ) external onlyOwner {
        uint256 oldReval = treasuryAllocationsStablec[_contract];
        uint256 newReval = _contract.reval();
        totalAllocationStablec = totalAllocationStablec + newReval - oldReval;
        treasuryAllocationsStablec[_contract] = newReval;

        emit MarkToMarketUpdated(address(_contract), oldReval, newReval);
    }

    /**
     * Withdraw from a contract.
     *
     * Expects that pre-withdrawal reval() includes the unwithdrawn allowance, and post withdrawal reval()
     * drops by exactly this amount.
     */
    function withdraw(ITreasuryAllocation _contract) external onlyOwner {
        uint256 preWithdrawlReval = _contract.reval();
        uint256 pendingWithdrawal = _STABLEC.allowance(
            address(_contract),
            address(this)
        );

        // NOTE: Reentrancy considered and it's safe STABLEC is a well known unchanging contract
        SafeERC20.safeTransferFrom(
            _STABLEC,
            address(_contract),
            address(this),
            pendingWithdrawal
        );
        uint256 postWithdrawlReval = _contract.reval();

        totalAllocationStablec = totalAllocationStablec - pendingWithdrawal;
        treasuryAllocationsStablec[_contract] -= pendingWithdrawal;

        if (postWithdrawlReval + pendingWithdrawal != preWithdrawlReval) {
            revert NO_SUCCESS();
        }
    }

    /**
     * Withdraw from a contract which has some treasury allocation
     *
     * Ejects a contract out of treasury, pulling in any allowance of STABLEC
     * We only expect to use this if (for whatever reason). The booking in
     * The given TreasuryAllocation results in withdraw not working.
     *
     * Precondition, contract given has allocated all of it's Stablec assets
     * to be transfered into treasury as an allowance.
     *
     * This will only ever reduce treasury IV.
     */
    function ejectTreasuryAllocation(
        ITreasuryAllocation _contract
    ) external onlyOwner {
        uint256 pendingWithdrawal = _STABLEC.allowance(
            address(_contract),
            address(this)
        );
        totalAllocationStablec -= treasuryAllocationsStablec[_contract];
        treasuryAllocationsStablec[_contract] = 0;
        SafeERC20.safeTransferFrom(
            _STABLEC,
            address(_contract),
            address(this),
            pendingWithdrawal
        );
    }

    /**
     * Add or update a pool, and transfer in treasury assets
     */
    event PoolUpserted(
        address indexed updatedContract,
        uint256 newPoolHarvestShare
    );

    function upsertPool(
        address _contract,
        uint96 _poolHarvestShare
    ) external onlyOwner {
        if (_poolHarvestShare <= 0) {
            revert Harvert_Less_Than_Zero();
        }

        totalHarvestShares =
            totalHarvestShares +
            _poolHarvestShare -
            poolHarvestShare[_contract];

        // first time, add contract to array as well
        if (poolHarvestShare[_contract] == 0) {
            pools.push(_contract);
        }

        poolHarvestShare[_contract] = _poolHarvestShare;

        emit PoolUpserted(_contract, _poolHarvestShare);
    }

    /**
     * Remove a given investment pool.
     */
    event PoolRemoved(
        uint256 indexed removedIndex,
        address indexed removedContract
    );

    function removePool(uint256 idx) external onlyOwner {
        if (idx >= pools.length) {
            revert PoolSpecifiedNotFound();
        }

        address removedContract = pools[idx];

        pools[idx] = pools[pools.length - 1];
        pools.pop();
        totalHarvestShares -= poolHarvestShare[removedContract];
        delete poolHarvestShare[removedContract];

        emit PoolRemoved(idx, removedContract);
    }
}
