// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimpleValidator {
    /// @notice Validiert, ob das Produkt mit dem erwarteten Hash übereinstimmt
    /// @param product Die Lösung (z. B. als bytes)
    /// @param expectedHash Der erwartete Hash (z. B. als bytes)
    /// @return true, wenn die Validierung erfolgreich ist
    function validate(bytes calldata product, bytes calldata expectedHash) external pure returns (bool) {
        return (keccak256(product) == keccak256(expectedHash));
    }
}
