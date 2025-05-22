// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Minimal interface for L1ScrollMessenger
interface IL1ScrollMessenger {
    function sendMessage(
        address target,
        uint256 value,
        bytes memory message,
        uint256 gasLimit,
        address refundAddress
    ) external payable;

    function relayMessageWithProof(
        address _from,
        address _to,
        uint256 _value,
        uint256 _nonce,
        bytes memory _message,
        L2MessageProof memory _proof
    ) external payable;
}

// Minimal interface for L1MessageQueueV2
interface IL1MessageQueueV2 {
    function appendCrossDomainMessage(
        address target,
        uint256 gasLimit,
        bytes memory message
    ) external;

    function nextCrossDomainMessageIndex() external view returns (uint256);

    function estimateCrossDomainMessageFee(uint256 gasLimit)
        external
        view
        returns (uint256);
}

// Minimal interface for IScrollChain
interface IScrollChain {
    function isBatchFinalized(uint256 batchIndex) external view returns (bool);
    function withdrawRoots(uint256 batchIndex) external view returns (bytes32);
}

// L2MessageProof struct (simplified for PoC)
struct L2MessageProof {
    uint256 batchIndex;
    bytes32 l2OracleRoot; // Simplified, actual proof might be more complex
    bytes merkleProof; // Simplified
}

// ScrollMessengerBase relevant parts (if needed for DelegateAttackContract storage layout)
// For now, we'll assume direct slot setting or public variables in DelegateAttackContract
// If DelegateAttackContract inherits, we'd import the actual ScrollMessengerBase
// import {ScrollMessengerBase} from "../../../src/libraries/ScrollMessengerBase.sol";

// Helper struct for decoding xDomain messages (if needed, often done in test script)
struct CrossDomainMessage {
    address sender;
    address target;
    uint256 value;
    uint256 nonce;
    bytes message;
}
