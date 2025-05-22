// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract L2TargetContract {
    address public owner;
    address public l1ScrollMessengerAddress;
    address public lastXDomainSender;

    constructor(address _l1ScrollMessengerAddress) {
        owner = msg.sender;
        l1ScrollMessengerAddress = _l1ScrollMessengerAddress;
    }

    function privilegedAction(address _xDomainSender) external {
        lastXDomainSender = _xDomainSender;
        require(
            _xDomainSender == l1ScrollMessengerAddress,
            "Not L1ScrollMessenger"
        );
        owner = tx.origin; // Attacker's EOA
    }
}
