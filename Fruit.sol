pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Fruit is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Fruit", "FRUIT") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
