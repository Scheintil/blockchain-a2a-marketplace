// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Vault.sol";

contract VaultRegistry {
    address public owner;  // Kept for potential future use (e.g., upgrades)

    // Vault registry (auto-populated by factory)
    mapping(address => bool) public isVault;

    // Agent registry: agent => their vault
    mapping(address => address) public agentToVault;

    // Events
    event VaultCreated(address indexed vault, address indexed creator);
    event AgentRegistered(address indexed agent, address indexed vault);
    event AgentsRegistered(address[] agents, address indexed vault);

    constructor() {
        owner = msg.sender;
    }

    // ========== FACTORY (Option 1B) ==========
    /// @notice Anyone can create a new vault (or restrict to owner if needed)
    function createVault() external returns (address) {
        Vault newVault = new Vault(address(this));
        isVault[address(newVault)] = true;
        emit VaultCreated(address(newVault), msg.sender);
        return address(newVault);
    }

    // ========== SELF-REGISTRATION (Decentralized) ==========
    /// @notice Only vaults can register their own agents (single)
    function registerAgent(address agent) external {
        require(isVault[msg.sender], "Not a vault");
        agentToVault[agent] = msg.sender;
        emit AgentRegistered(agent, msg.sender);
    }

    /// @notice Only vaults can register their own agents (batch)
    function registerAgents(address[] calldata agents) external {
        require(isVault[msg.sender], "Not a vault");
        for (uint256 i = 0; i < agents.length; i++) {
            agentToVault[agents[i]] = msg.sender;
        }
        for (uint256 i = 0; i < agents.length; i++) {
            emit AgentRegistered(agents[i], msg.sender);
        }
    }
}