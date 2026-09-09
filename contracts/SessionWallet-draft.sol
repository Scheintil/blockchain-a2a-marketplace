// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract SessionWallet {
    address public owner;
    address payable wallet; 

    mapping(address => uint256) public agentExpiry;

    event AgentAuthorized(address indexed agent, uint256 expiry);
    event AgentRevoked(address indexed agent);
    event Transfer(address indexed to, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    constructor() payable {
        owner = msg.sender;
        wallet = payable(address(this));
    }
    
    modifier onlyAgent() {
        require(agentExpiry[msg.sender] > block.timestamp, "Not agent or expired");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

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

    function transfer(address payable to, uint256 amount) external onlyAgent {
        require(to != address(0), "Invalid address");
        require(wallet.balance >= amount, "Insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success,"Call function failed.");
        emit Transfer(to, amount);
    }

    function balance() external view returns (uint256) {
        return wallet.balance;
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(wallet.balance >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }

    function withdrawAll() external onlyOwner {
        uint256 amount = wallet.balance;
        require(amount > 0, "No balance");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }
}