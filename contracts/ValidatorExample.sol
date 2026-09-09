// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SimpleValidator {
    /// @notice Validiert, ob das Produkt mit dem erwarteten Hash übereinstimmt
    /// @param product Die Lösung (z. B. als bytes)
    /// @param expectedHash Der erwartete Hash (z. B. als bytes)
    /// @return true, wenn die Validierung erfolgreich ist
    function validate(uint  product, uint  expectedHash) external pure returns (bool) {
        return (product == expectedHash);
    }
}
