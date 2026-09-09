// SPDX-License-Identifier: MIT
// Code for teaching purposes only. 
// See University of Basel cryptolectures.io

pragma solidity ^0.8.9;

contract Store {
    uint public number = 0;
    // After deployment, this is stored on the blockchain
     
     function store(uint256 _value) public {
        number = _value;
    }

    }