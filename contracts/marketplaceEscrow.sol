// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Vault.sol";
import "./Escrow.sol";

contract MarketplaceEscrow {
    // Track valid SessionWallets (closed system)
    mapping(address => bool) public isSessionWallet;
    address[] public sessionWallets;

    // Track valid Escrow contracts (closed system)
    mapping(address => bool) public isEscrow;

    // Deploy a new SessionWallet for an agent
    function createSessionWallet(address _agent) external returns (address) {
        Vault wallet = new Vault(address(this), _agent);
        isSessionWallet[address(wallet)] = true;
        sessionWallets.push(address(wallet));
        return address(wallet);
    }

    // Deploy a new Escrow contract for a trade
    function createEscrow(address _seller, address _validator, uint256 _deadline, bytes memory _expectedHash) external payable {
        require(isSessionWallet[msg.sender], "Only SessionWallets");
        require(isSessionWallet[_seller], "Seller must be SessionWallet");

        Escrow escrow = new Escrow{value: msg.value}(msg.sender, _seller, _validator, _deadline, _expectedHash);
        isEscrow[address(escrow)] = true;
    }

    // Let SessionWallets verify Escrow validity
    function isValidEscrow(address _escrow) external view returns (bool) {
        return isEscrow[_escrow];
    }
}