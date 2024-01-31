// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error ADDRESS_ALREADY_WHITELISTED();

contract SoulBound is ERC721 {
    string public uri;
    address public owner;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    mapping(address => bool) public whitelistedAddresses; // Whitelisted addresses to mint tokens
    mapping(address => bool) public tokenMintedAddress; // Addresses that have already minted tokens
    IERC20 token;

    constructor(
        address tokenAddress,
        string memory _uri
    ) ERC721("SoulBound Token", "SBT") {
        owner = msg.sender;
        token = IERC20(tokenAddress);
        uri = _uri;
    }

    function updateUri(string memory newUri) public onlyOwner {
        uri = newUri;
    }

    function addToWhiteList(address _add) public onlyOwner {
        if (whitelistedAddresses[_add]) {
            revert ADDRESS_ALREADY_WHITELISTED();
        }
        whitelistedAddresses[_add] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyWhitelistedUser() {
        require(whitelistedAddresses[msg.sender], "Could not mint the token");
        _;
    }

    function safeMint() public onlyWhitelistedUser {
        whitelistedAddresses[msg.sender] = false;
        tokenMintedAddress[msg.sender] = true;
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
    }

    function burn(uint256 tokenId) external {
        require(
            ownerOf(tokenId) == msg.sender,
            "Only the owner of the token can burn it"
        );
        _burn(tokenId);
    }

    function revoke(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721) {
        require(from == address(0), "Token not transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return super.tokenURI(tokenId);
    }

    function hasToken() external view returns (bool) {
        return tokenMintedAddress[msg.sender];
    }
}
