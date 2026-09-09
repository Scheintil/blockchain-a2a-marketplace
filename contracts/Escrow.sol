// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IValidator {
    function validate(bytes calldata product, bytes calldata expectedHash) external view returns (bool);
}
//works with bytes. Example input "0x6d65696e654c6f6573756e67"
contract Escrow {
    address public immutable customer;
    address public immutable provider;
    address public immutable validator;
    bytes public  expectedHash; // entspricht "valid" im Diagramm
    uint256 public deadline;               // entspricht "timestemp" im Diagramm
    uint256 public amount;
    bool public closed;
    bool public refundable;
    bytes public finalproduct;

    event EscrowCreated(address indexed customer, address indexed provider, address indexed validator,uint256 amount, uint256 deadline);
    event AmountIncreased(uint256 newAmount);
    event EscrowCompleted(address indexed provider, uint256 amount);
    event EscrowRefunded(address indexed customer, uint256 amount);

    modifier notClosed() {
        require(!closed, "Escrow ist bereits geschlossen");
        _;
    }

    /// @param _provider Wallet-Adresse des Providers
    /// @param _deadline Unix-Timestamp, bis zu dem die Mittel maximal gesperrt bleiben
    /// @param _expectedHash keccak256-Hash der erwarteten Loesung ("valid")
    constructor(address _provider,address _validator, uint256 _deadline, bytes memory _expectedHash) payable {
        //require(msg.value > 0, "amount muss > 0 sein"); // entspricht "Refuse" im Diagramm
        require(_provider != address(0), "Provider Adresse ungueltig");
        require(_deadline > 0, "Deadline muss in der Zukunft liegen");
        require(_validator != address(0), "Validator Adresse ungueltig");
        customer = msg.sender;
        provider = _provider;
        validator = _validator;
        deadline = _deadline+block.timestamp;
        expectedHash = _expectedHash;
        amount = msg.value;

        emit EscrowCreated(customer, provider, validator, amount, deadline);
    }

    /// @notice Customer kann weitere Mittel in den Escrow einzahlen ("Increase Amount")
    function increaseAmount() external payable notClosed {
        require(msg.sender == customer, "Nur Customer darf aufstocken");
        require(msg.value > 0, "Betrag muss > 0 sein");
        amount += msg.value;
        emit AmountIncreased(amount);
    }

    /// @notice Provider liefert die Loesung ("product"). Bei korrektem Hash wird ausgezahlt.
    /// @param product Die Loesung/der Input, dessen Hash geprueft wird
    function callEscrow(bytes  calldata product) external notClosed {
        require(msg.sender == provider, "Nur Provider darf aufrufen");
        bool isValid = IValidator(validator).validate(product, expectedHash);
        require(isValid, "Validierung fehlgeschlagen");

        uint256 payout = amount;
        amount = 0;
        closed = true;
        //send product to Costumer
        finalproduct=product;
        (bool success, ) = provider.call{value: payout}("");
        require(success, "Auszahlung an Provider fehlgeschlagen");

        emit EscrowCompleted(provider, payout);
    }

    /// @notice Nach Ablauf der Deadline kann der Customer sein Guthaben zurückholen
    function refund() external notClosed {
        require(block.timestamp > deadline, "Deadline noch nicht erreicht");

        uint256 payout = amount;
        amount = 0;
        closed = true;

        (bool success, ) = customer.call{value: payout}("");
        require(success, "Rueckzahlung an Customer fehlgeschlagen");

        emit EscrowRefunded(customer, payout);
    }
    function deadlineArrieved() external {
        refundable=(block.timestamp>deadline);
    }
}
