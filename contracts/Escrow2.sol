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
    bytes   public finalproduct;

    event EscrowCreated(address indexed customer, address indexed provider, address indexed validator, uint256 amount, uint256 deadline);
    event AmountIncreased(uint256 newAmount);
    event EscrowCompleted(address indexed provider, uint256 amount);
    event EscrowRefunded(address indexed customer, uint256 amount);

    modifier notClosed() {
        require(!closed, "Escrow ist bereits geschlossen");
        _;
    }

    /// @param _duration seconds from now until the funds can be refunded
    constructor(
        address _provider,
        address _validator,
        uint256 _duration,
        bytes memory _expectedHash
    ) payable {
        require(_provider != address(0), "Provider Adresse ungueltig");
        require(_validator != address(0), "Validator Adresse ungueltig");
        require(_duration > 0, "Deadline muss in der Zukunft liegen");

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
        require(msg.sender == customer, "Nur Customer darf aufstocken");
        require(msg.value > 0, "Betrag muss > 0 sein");
        amount += msg.value;
        emit AmountIncreased(amount);
    }

    /// @notice Provider delivers the product; on valid product they get paid.
    function callEscrow(bytes calldata product) external notClosed {
        require(msg.sender == provider, "Nur Provider darf aufrufen");
        require(IValidator(validator).validate(product, expectedHash), "Validierung fehlgeschlagen");

        uint256 payout = amount;
        amount = 0;
        closed = true;
        finalproduct = product;             // customer can read the delivered product

        (bool success, ) = provider.call{value: payout}("");
        require(success, "Auszahlung an Provider fehlgeschlagen");

        emit EscrowCompleted(provider, payout);
    }

    /// @notice After the deadline the funds go back to the customer (the vault).
    function refund() external notClosed {
        require(block.timestamp > deadline, "Deadline noch nicht erreicht");

        uint256 payout = amount;
        amount = 0;
        closed = true;

        (bool success, ) = customer.call{value: payout}("");
        require(success, "Rueckzahlung an Customer fehlgeschlagen");

        emit EscrowRefunded(customer, payout);
    }
}
