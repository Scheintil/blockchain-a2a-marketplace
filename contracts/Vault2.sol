// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Escrow.sol";

// ============================================================
//  SESSION VAULT  (holds funds, authorizes agents, spawns escrows)
// ============================================================
contract SessionVault {
    address public owner;
    address payable vault;

    mapping(address => uint256) public agentExpiry;
    mapping(address => uint256) public transactionLimits;
    mapping(address => uint256[4]) public timedtransactionLimits;

    address[] public escrows;   // every escrow this vault created

    event AgentAuthorized(address indexed agent, uint256 expiry);
    event AgentRevoked(address indexed agent);
    event Transfer(address indexed to, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event EscrowDeployed(address indexed escrow, address indexed agent, address provider, uint256 amount);

    struct Transaction {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
    }
    Transaction[] public transactions;

    constructor() payable {
        owner = msg.sender;
        vault = payable(address(this));
    }

    // ---- so the vault can receive escrow refunds and top-up deposits ----
    receive() external payable {}

    modifier onlyAgent() {
        require(agentExpiry[msg.sender] > block.timestamp, "Not agent or expired");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ==================== OWNER FUNCTIONS ====================
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
    function settimedAgentLimit(address _agent, uint256 _limit,uint _time) external onlyOwner {

        timedtransactionLimits[_agent] = [_limit,_time,0,block.timestamp];
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

    // ==================== AGENT FUNCTIONS ====================
    function transfer(address payable _to, uint256 _amount) external onlyAgent {
        require(_to != address(0), "Invalid address");
        require(vault.balance >= _amount, "Insufficient balance");
        _checkLimit(_amount);

        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Call function failed.");
        emit Transfer(_to, _amount);

        _record(msg.sender, _to, _amount);
    }

    /// @notice Agent hires a provider by deploying + funding an escrow from the vault.
    /// @param _duration seconds until the escrow becomes refundable
    /// @param _amount   ETH taken from the vault to lock in the escrow
    function createEscrow(
        address _provider,
        address _validator,
        uint256 _duration,
        bytes calldata _expectedHash,
        uint256 _amount
    ) external onlyAgent returns (address) {
        require(_amount > 0, "Amount must be > 0");
        require(vault.balance >= _amount, "Insufficient balance");
        _checkLimit(_amount);

        Escrow escrow = new Escrow{value: _amount}(_provider, _validator, _duration, _expectedHash);
        escrows.push(address(escrow));

        _record(msg.sender, address(escrow), _amount);
        emit EscrowDeployed(address(escrow), msg.sender, _provider, _amount);
        return address(escrow);
    }

    /// @notice Agent adds more funds to an existing escrow (vault is its customer).
    function topUpEscrow(address payable _escrow, uint256 _amount) external onlyAgent {
        require(_amount > 0, "Amount must be > 0");
        require(vault.balance >= _amount, "Insufficient balance");
        _checkLimit(_amount);

        Escrow(_escrow).increaseAmount{value: _amount}();
        _record(msg.sender, _escrow, _amount);
    }

    function refund(address payable _escrow)external onlyAgent{
        Escrow(_escrow).refund();
    }

    // ==================== PUBLIC / HELPERS ====================
    function balance() external view returns (uint256) {
        return vault.balance;
    }

    function escrowsCount() external view returns (uint256) {
        return escrows.length;
    }

    function _checkLimit(uint256 _amount) internal{
        if (transactionLimits[msg.sender] > 0) {
            require(_amount <= transactionLimits[msg.sender], "Exceeds limit");
        }
        if (timedtransactionLimits[msg.sender][0]>0){
            if(timedtransactionLimits[msg.sender][3]>block.timestamp-timedtransactionLimits[msg.sender][1]){
                require(timedtransactionLimits[msg.sender][0]>=timedtransactionLimits[msg.sender][2]+_amount, "Exceeds timed limit");
                timedtransactionLimits[msg.sender][2]+_amount;
            }
            else{
                timedtransactionLimits[msg.sender][3]=block.timestamp+timedtransactionLimits[msg.sender][1];
                require(timedtransactionLimits[msg.sender][0]>=_amount, "Exceeds timed limit");

                timedtransactionLimits[msg.sender][2]=_amount;
            }

        }

    }

    function _record(address _from, address _to, uint256 _amount) internal {
        transactions.push(Transaction({
            from: _from,
            to: _to,
            amount: _amount,
            timestamp: block.timestamp
        }));
    }
}
