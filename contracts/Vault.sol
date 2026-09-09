// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./marketplaceEscrow.sol";

contract Vault {
//=============== VARIABLES =================
//___________________________________________
    address public owner;
    address payable vault; 
    MarketplaceEscrow public immutable marketplace;

    mapping(address => uint256) public agentExpiry;
    mapping(address => uint256) public transactionLimits;

//================ EVENTS ===================
//___________________________________________
    event AgentAuthorized(address indexed agent, uint256 expiry);
    event AgentRevoked(address indexed agent);
    event Transfer(address indexed to, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

//================= STRUCT ==================
//___________________________________________
struct Transaction {
    address from;
    address to;
    uint256 amount;
    uint256 timestamp;
}
Transaction[] public transactions;

//============== CONSTRUCTOR ================
//___________________________________________
    constructor(address _marketplace, address _owner) payable {
        owner = _owner;
        vault = payable(address(this));
        marketplace = MarketplaceEscrow(_marketplace);
    }

//=============== MODIFIERS =================
//___________________________________________
    modifier onlyAgent() {
        require(agentExpiry[msg.sender] > block.timestamp, "Not agent or expired");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

//============= OWNER FUNCTIONS =============
//___________________________________________

    function authorizeAgent(address _agent, uint256 _duration) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        require(_duration > 0, "Duration too short");
        agentExpiry[_agent] = block.timestamp + _duration;
        emit AgentAuthorized(_agent, block.timestamp + _duration);
    }

    function revokeAgent(address _agent) external onlyOwner {
        delete agentExpiry[_agent];
        emit AgentRevoked(_agent);
    }

    function setAgentLimit(address _agent, uint256 _limit) external onlyOwner {
        transactionLimits[_agent] = _limit;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(vault.balance >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }

    function withdrawAll() external onlyOwner {
        uint256 amount = vault.balance;
        require(amount > 0, "No balance");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }

//============= AGENT FUNCTIONS =============
//___________________________________________
    function transfer(address payable _to, uint256 _amount) external onlyAgent {
        require(_to != address(0), "Invalid address");
        require(vault.balance >= _amount, "Insufficient balance");
        if (transactionLimits[msg.sender] > 0) {
            require(_amount <= transactionLimits[msg.sender], "Exceeds limit");
        }

        (bool success, ) = _to.call{value: _amount}("");
        require(success,"Call function failed.");
        emit Transfer(_to, _amount);

        transactions.push(Transaction({
            from: msg.sender,
            to: _to,
            amount: _amount,
            timestamp: block.timestamp
        }));
    }

//============= PUBLIC FUNCTIONS ============
//___________________________________________
    function balance() external view returns (uint256) {
        return vault.balance;
    }
}