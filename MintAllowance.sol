pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "contracts/EarthERC20Token.sol";

/**
 * Newly minted earth allocated to various earth strategies
 *
 * Any earth held by this contract is assumed to be unused,
 * and hence doesn't effect the intrinsinc value calculation.
 *
 * It's only considered in circulation once a pool pulls
 * it's allowance.
 */
contract MintAllowance is Ownable {
    EarthERC20Token public immutable earth;

    constructor(EarthERC20Token _EARTH) {
        earth = _EARTH;
    }

    /**
     * Increase mint allowance for the given pool
     *
     * Atomically pulls amount from treasury before increasing allownance
     * as an extra check and balance
     */
    function increaseMintAllowance(
        address _pool,
        uint256 _amount
    ) external onlyOwner {
        SafeERC20.safeTransferFrom(earth, msg.sender, address(this), _amount);
        SafeERC20.safeIncreaseAllowance(earth, _pool, _amount);
    }

    /**
     * Burn any unused mint allowance for a given pool
     */
    function burnUnusedMintAllowance(address _pool) external onlyOwner {
        uint256 unusedMintAllowance = earth.allowance(address(this), _pool);
        SafeERC20.safeDecreaseAllowance(earth, _pool, unusedMintAllowance);
        earth.burn(unusedMintAllowance);
    }

    function getUnusedMintAllowance(
        address _pool
    ) public view onlyOwner returns (uint256) {
        uint256 unusedMintAllowance = earth.allowance(address(this), _pool);
        return (unusedMintAllowance);
    }
}
