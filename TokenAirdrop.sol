// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TokenAirdrop is Initializable, OwnableUpgradeable {
    IERC20Upgradeable public token;
    mapping(address => uint256) public claimableAmount;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAuthorized;

    function initialize(address _tokenAddress) public initializer {
        __Ownable_init();
        token = IERC20Upgradeable(_tokenAddress);
    }

    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || isAuthorized[msg.sender], "Not the contract owner or authorized");
        _;
    }

    // Add or update an address to the whitelist with a specific claimable amount.
    function whitelistAddress(address _recipient, uint256 _amount) public onlyOwnerOrAuthorized {
        claimableAmount[_recipient] = _amount;
        isWhitelisted[_recipient] = true;
    }

    // Bulk whitelist multiple addresses with specific claimable amounts.
    function batchWhitelistAddresses(address[] memory _recipients, uint256[] memory _amounts) public onlyOwnerOrAuthorized {
        require(_recipients.length == _amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < _recipients.length; i++) {
            claimableAmount[_recipients[i]] = _amounts[i];
            isWhitelisted[_recipients[i]] = true;
        }
    }

    // Remove an address from the whitelist.
    function removeFromWhitelist(address _recipient) public onlyOwnerOrAuthorized {
        claimableAmount[_recipient] = 0;
        isWhitelisted[_recipient] = false;
    }

    // Claim tokens for a whitelisted address.
    function claimTokens() public {
        uint256 claimAmount = claimableAmount[msg.sender];
        require(claimAmount > 0, "You are not whitelisted or have already claimed");
        claimableAmount[msg.sender] = 0;
        token.transfer(msg.sender, claimAmount);
    }

    // Deposit tokens into the contract.
    function depositTokens(uint256 _amount) public onlyOwnerOrAuthorized {
        require(_amount > 0, "Amount must be greater than 0");
        token.transferFrom(owner(), address(this), _amount);
    }

    // Receive Ether function to handle Ether transfers.
    receive() external payable {}

    // Prevent the contract from accepting Ether through the fallback function.
    fallback() external {}

    // Check the claimable amount for a specific address.
    function getClaimableAmount(address _recipient) public view returns (uint256) {
        return claimableAmount[_recipient];
    }

    // Authorize another address to perform whitelist operations.
    function authorize(address _authorized) public onlyOwner {
        isAuthorized[_authorized] = true;
    }

    // Deauthorize an address from performing whitelist operations.
    function deauthorize(address _authorized) public onlyOwner {
        isAuthorized[_authorized] = false;
    }
}
