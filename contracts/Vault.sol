// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Escrow.sol";

// ============================================================
//  SESSION VAULT  (holds funds, authorizes agents, spawns escrows)
// ============================================================
contract Vault {
    address public owner;
    address public immutable vaultRegistry;

    bool private locked;
    uint256 public gasMultiplier = 110;

    mapping(address => uint256) public agentExpiry;
    mapping(address => uint256) public transactionLimits;
    mapping(address => TimedLimit) public timedLimits;
    mapping(address => address) public escrowToAgent;

    address[] public escrows;   // every escrow this vault created

    event AgentAuthorized(address indexed agent, uint256 expiry, uint256 limit, uint256 timedLimit);
    event AgentRevoked(address indexed agent);
    event Transfer(address indexed to, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event EscrowDeployed(address indexed escrow, address indexed agent, address provider, uint256 amount);
    event AgentLimitSet(address indexed agent, uint256 limit);
    event TimedAgentLimitSet(address indexed agent, uint256 limit, uint256 window);
    event GasPayed(address indexed to, uint256 amount);

//============== STRUCTS ==============
//_____________________________________
    struct Transaction {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
    }

    struct TimedLimit {
        uint256 limit;      // Max amount per window
        uint256 window;     // Time window (seconds)
        uint256 spent;      // Amount spent in current window
        uint256 windowStart; // Start timestamp of current window
    }

    Transaction[] public transactions;

    constructor(address _VaultRegistry) payable {
        owner = msg.sender;
        vaultRegistry = _VaultRegistry;
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

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ==================== OWNER FUNCTIONS ====================
    function authorizeAgent(address _agent, uint256 _duration, uint256 _limit, uint256 _timedLimit, uint256 _timedWindow, uint256 _startGas) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        require(_duration > 0, "Duration too short");
        require(_timedWindow > 0, "Timed window must be > 0");
        agentExpiry[_agent] = block.timestamp + _duration;
        transactionLimits[_agent] = _limit;
        if (_timedLimit > 0) {
            timedLimits[_agent] = TimedLimit({
                limit: _timedLimit,
                window: _timedWindow,
                spent: 0,
                windowStart: block.timestamp
            });
        }
        emit AgentAuthorized(_agent, block.timestamp + _duration, _limit, _timedLimit);
        if (_startGas > 0) {_sendGas(_agent, _startGas);}
    }

    function revokeAgent(address _agent) external onlyOwner {
        delete agentExpiry[_agent];
        delete transactionLimits[_agent];
        delete timedLimits[_agent];
        emit AgentRevoked(_agent);
    }

    function setAgentLimit(address _agent, uint256 _limit) external onlyOwner {
        transactionLimits[_agent] = _limit;
        emit AgentLimitSet(_agent, _limit);
    }
    function settimedAgentLimit(address _agent, uint256 _limit, uint256 _window) external onlyOwner {
        timedLimits[_agent] = TimedLimit({
            limit: _limit,
            window: _window,
            spent: 0,
            windowStart: block.timestamp
        });
        emit TimedAgentLimitSet(_agent, _limit, _window);
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }

    function withdrawAll() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "No balance");
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Call function failed.");
        emit Withdrawal(owner, amount);
    }

    // ==================== AGENT FUNCTIONS ====================
    /// @notice Agent hires a provider by deploying + funding an escrow from the vault.
    /// @param _duration seconds until the escrow becomes refundable
    /// @param _amount   ETH taken from the vault to lock in the escrow
    function createEscrow (
        address _provider,
        address _validator,
        uint256 _duration,
        bytes calldata _expectedHash,
        uint256 _amount
    ) external onlyAgent nonReentrant returns (address) {
        require(_provider != address(0), "Invalid provider");
        require(_validator != address(0), "Invalid validator");
        require(_amount > 0, "Amount must be > 0");
        require(address(this).balance >= _amount, "Insufficient balance");
        _checkLimit(_amount);

        Escrow escrow = new Escrow{value: _amount}(_provider, _validator, _duration, _expectedHash);
        escrows.push(address(escrow));
        escrowToAgent[address(escrow)] = msg.sender;

        _record(msg.sender, address(escrow), _amount);
        emit EscrowDeployed(address(escrow), msg.sender, _provider, _amount);
        return address(escrow);
    }

    /// @notice Agent adds more funds to an existing escrow (vault is its customer).
    function topUpEscrow(address payable _escrow, uint256 _amount) external onlyAgent nonReentrant {
        require(escrowToAgent[_escrow] == msg.sender, "Not escrow owner");
        require(_amount > 0, "Amount must be > 0");
        require(address(this).balance >= _amount, "Insufficient balance");
        _checkLimit(_amount);

        Escrow(_escrow).increaseAmount{value: _amount}();
        _record(msg.sender, _escrow, _amount);
    }

    function refund(address payable _escrow)external onlyAgent nonReentrant{
        require(escrowToAgent[_escrow] == msg.sender, "Not escrow owner");
        Escrow(_escrow).refund();
    }

    // ==================== PUBLIC / HELPERS ====================
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    function escrowsCount() external view returns (uint256) {
        return escrows.length;
    }

    function _checkLimit(uint256 _amount) internal{
        // Transaction Limit
        if (transactionLimits[msg.sender] > 0) {
            require(_amount <= transactionLimits[msg.sender], "Exceeds limit");
        }
        // Timed Limit
        TimedLimit storage limit = timedLimits[msg.sender];
        if (limit.limit > 0) {
            if (block.timestamp >= limit.windowStart + limit.window) {
                limit.spent = 0;
                limit.windowStart = block.timestamp;
            }
            require(limit.limit >= limit.spent + _amount, "Exceeds timed limit");
            limit.spent += _amount;
        }
    }

    function _sendGas(address _agent, uint256 _gas) internal {
        require((_gas > 0), "No gas to be sent.");
        (bool success, ) = payable(_agent).call{value: _gas}("");
        require(success, "Gas payback failed.");
        emit GasPayed(_agent, _gas);
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
