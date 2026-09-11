// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================
//  VALIDATOR INTERFACE
// ============================================================
interface IValidator {
    function validate(bytes calldata product, bytes calldata expectedHash) external view returns (bool);
}

// ============================================================
//  ESCROW  (one deal: customer <-> provider)
//  Deployed and funded BY the vault. The vault is the customer,
//  so refunds flow back into the vault automatically.
// ============================================================
contract Escrow {
    address public immutable customer;   // = the vault
    address public immutable provider;
    address public immutable validator;
    bytes   public expectedHash;
    uint256 public deadline;             // absolute timestamp
    uint256 public amount;
    bool    public closed;
    bool    private locked;
    bytes   public finalproduct;

    event EscrowCreated(address indexed customer, address indexed provider, address indexed validator, uint256 amount, uint256 deadline);
    event AmountIncreased(uint256 newAmount);
    event EscrowCompleted(address indexed provider, uint256 amount);
    event EscrowRefunded(address indexed customer, uint256 amount);

    modifier notClosed() {
        require(!closed, "Escrow is already closed.");
        _;
    }

    modifier nonReentrant(){
        require(!locked, "Reentrant call.");
        locked = true;
        _;
        locked = false;
    }

    /// @param _duration seconds from now until the funds can be refunded
    constructor(
        address _provider,
        address _validator,
        uint256 _duration,
        bytes memory _expectedHash
    ) payable {
        require(_provider != address(0), "Provider address invalid.");
        require(_validator != address(0), "Validator address invalid.");
        require(_duration > 0, "Deadline must be in future.");

        customer     = msg.sender;              // the vault
        provider     = _provider;
        validator    = _validator;
        deadline     = block.timestamp + _duration;
        expectedHash = _expectedHash;
        amount       = msg.value;

        emit EscrowCreated(customer, provider, validator, amount, deadline);
    }

    /// @notice Only the customer (the vault) can add funds.
    function increaseAmount() external payable notClosed {
        require(msg.sender == customer, "Only customer can increase funds.");
        require(msg.value > 0, "Value must be > 0.");
        amount += msg.value;
        emit AmountIncreased(amount);
    }

    /// @notice Provider delivers the product; on valid product they get paid.
    function callEscrow(bytes calldata product) external notClosed nonReentrant {
        require(msg.sender == provider, "Only Provider can call.");
        require(IValidator(validator).validate(product, expectedHash), "Validation failed.");

        uint256 payout = amount;
        amount = 0;
        closed = true;
        finalproduct = product;             // customer can read the delivered product

        (bool success, ) = provider.call{value: payout}("");
        require(success, "Payout to provider failed.");
        emit EscrowCompleted(provider, payout);
    }

    /// @notice After the deadline the funds go back to the customer (the vault).
    function refund() external notClosed nonReentrant {
        require(msg.sender == customer, "Only customer can refund.");
        require(block.timestamp > deadline, "Deadline not reached.");

        uint256 payout = amount;
        amount = 0;
        closed = true;

        (bool success, ) = customer.call{value: payout}("");
        require(success, "Refund to customer failed.");
        emit EscrowRefunded(customer, payout);
    }
}
