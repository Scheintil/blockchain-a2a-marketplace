// SPDX-License-Identifier: MIT
// Code for teaching purposes only. 
// See University of Basel cryptolectures.io

pragma solidity ^0.8.9;

contract RestrictedStore {
    // Contract owner
    address public owner;

    // Stored number
    uint256 public number = 0;

    // Set the owner at deployment
    constructor() {
        owner = msg.sender;
    }

    // Modifier to restrict function access to the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Ah ah ah, you did not say the magic word!");
        _;
    }

    // Store a number (only owner can do this)
    function store(uint256 _value) public onlyOwner {
        number = _value;
    }

    // Retrieve the stored number
    function retrieve() public view returns (uint256) {
        return number;
    }
}

// testest test
