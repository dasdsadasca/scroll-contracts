# L1 Messaging Contracts: Detailed Breakdown

This document provides a detailed breakdown of the core Layer 1 (L1) contracts responsible for messaging in the Scroll protocol: `L1ScrollMessenger.sol`, `L1MessageQueueV1.sol`, and `L1MessageQueueV2.sol`.

## 1. L1ScrollMessenger.sol

### Purpose

`L1ScrollMessenger.sol` is the primary L1 interface for cross-domain communication between L1 and L2. It orchestrates the sending of messages from L1 to L2 and the relaying and verification of messages from L2 to L1. It also handles scenarios like message failure (replay) and messages being skipped by sequencers (drop).

Key functionalities include:

*   **Sending L1->L2 Messages:** Users and L1 contracts (like Gateways) call `sendMessage` to initiate a message to L2. The messenger then queues this message into the appropriate `L1MessageQueue` (primarily `L1MessageQueueV2` for current versions).
*   **Relaying L2->L1 Messages:** It processes messages originating from L2. The `relayMessageWithProof` function takes a message and its Merkle proof (proving its inclusion in a finalized L2 batch's `withdrawRoot` stored in `ScrollChain`) and executes it on L1 if the proof is valid.
*   **Replaying Failed L1->L2 Messages:** If an L1->L2 message fails execution on L2 (e.g., due to insufficient gas), users can call `replayMessage`. This re-queues the message, potentially with a new gas limit, for another attempt.
*   **Dropping Skipped L1->L2 Messages:** If an L1->L2 message (from `L1MessageQueueV1`) was skipped by L2 sequencers (e.g., due to batch capacity limits) and is finalized as skipped, users can call `dropMessage`. This allows the original sender (often a gateway) to reclaim any locked assets via the `IMessageDropCallback` interface.

### Key State Variables

*   **`rollup` (immutable `address`):** The address of the `ScrollChain` contract, used for verifying L2->L1 message proofs against finalized withdrawal roots.
*   **`messageQueueV1` (immutable `address`):** The address of the `L1MessageQueueV1` contract, used for dropping messages that were originally sent through it.
*   **`messageQueueV2` (immutable `address`):** The address of the `L1MessageQueueV2` contract, primarily used for sending new L1->L2 messages and estimating their fees.
*   **`enforcedTxGateway` (immutable `address`):** The address of the `EnforcedTxGateway`, referenced but not directly called by users through the messenger for standard messaging. Its presence indicates a connection point for a specific type of L1->L2 transaction.
*   **`messageSendTimestamp` (mapping `bytes32 => uint256`):** Records the L1 timestamp when an L1->L2 message (identified by its xDomain calldata hash) was sent.
*   **`isL2MessageExecuted` (mapping `bytes32 => bool`):** Tracks whether an L2->L1 message (identified by its xDomain calldata hash) has been successfully executed on L1.
*   **`isL1MessageDropped` (mapping `bytes32 => bool`):** Tracks whether an L1->L2 message has been dropped.
*   **`replayStates` (mapping `bytes32 => ReplayState`):** Stores the replay status for L1->L2 messages, including the number of times replayed (`times`) and the queue index of the latest replay attempt (`lastIndex`).
    *   `ReplayState` struct: `{ uint128 times; uint128 lastIndex; }`
*   **`prevReplayIndex` (mapping `uint256 => uint256`):** Links replayed message queue indices to their predecessors, forming a chain back to the original message nonce.
*   **`maxReplayTimes` (`uint256`):** The maximum number of times an L1->L2 message can be replayed.
*   **`feeVault` (`address`):** Inherited from `ScrollMessengerBase`. The address where collected L1->L2 messaging fees are sent.
*   **`counterpart` (immutable `address`):** Inherited from `ScrollMessengerBase`. The address of the `L2ScrollMessenger` contract on L2.
*   **`xDomainMessageSender` (`address`):** Inherited from `ScrollMessengerBase`. Stores the L2 sender address during an L2->L1 message relay, or a special constant during a drop operation.

### Key Functions

*   **`sendMessage(address _to, uint256 _value, bytes memory _message, uint256 _gasLimit)` / `sendMessage(address _to, uint256 _value, bytes calldata _message, uint256 _gasLimit, address _refundAddress)`:**
    *   Called by users or L1 contracts to send a message to L2.
    *   It calculates the required fee using `L1MessageQueueV2.estimateCrossDomainMessageFee()`.
    *   It constructs the cross-domain calldata (encoding sender, target, value, nonce, and message).
    *   Appends the message to `L1MessageQueueV2` via `appendCrossDomainMessage()`.
    *   Records `messageSendTimestamp` and emits `SentMessage`.
    *   Handles fee payment to `feeVault` and refunds any excess `msg.value`.

*   **`relayMessageWithProof(address _from, address _to, uint256 _value, uint256 _nonce, bytes memory _message, L2MessageProof memory _proof)`:**
    *   Called to process an L2->L1 message.
    *   Verifies that the message hasn't been executed (`!isL2MessageExecuted`).
    *   Checks with `ScrollChain.isBatchFinalized()` and `ScrollChain.withdrawRoots()` using the provided `_proof` (batchIndex, merkleProof) to ensure the message is valid and included in a finalized L2 batch. Uses `WithdrawTrieVerifier.verifyMerkleProof()`.
    *   If valid, it sets `xDomainMessageSender = _from` and executes the message by calling `_to.call{value: _value}(_message)`.
    *   Updates `isL2MessageExecuted` and emits `RelayedMessage` on success, or `FailedRelayedMessage` on failure of the L1 execution.

*   **`replayMessage(address _from, address _to, uint256 _value, uint256 _messageNonce, bytes memory _message, uint32 _newGasLimit, address _refundAddress)`:**
    *   Allows re-trying an L1->L2 message that may have failed on L2.
    *   Checks that the original message was sent and not dropped.
    *   Checks `replayStates` to ensure `maxReplayTimes` is not exceeded.
    *   Calculates a new fee based on `_newGasLimit` via `L1MessageQueueV2`.
    *   Appends a new message (with the same original content but new queue index and potentially new gas limit) to `L1MessageQueueV2`.
    *   Updates `replayStates` and `prevReplayIndex` to link this replay to the original message chain.

*   **`dropMessage(address _from, address _to, uint256 _value, uint256 _messageNonce, bytes memory _message)`:**
    *   Allows handling L1->L2 messages (from `L1MessageQueueV1`) that were finalized as "skipped" on L2.
    *   Checks that the message was sent and not already dropped.
    *   Iteratively calls `L1MessageQueueV1.dropCrossDomainMessage()` for the original message and any of its replayed versions to mark them as dropped in `L1MessageQueueV1`.
    *   Sets `isL1MessageDropped` to true.
    *   Calls `IMessageDropCallback(_from).onDropMessage()` to allow the original sender (e.g., a gateway) to reclaim assets. The `_value` is forwarded in this call.
    *   Sets `xDomainMessageSender` to `ScrollConstants.DROP_XDOMAIN_MESSAGE_SENDER` during the callback.

*   **`updateMaxReplayTimes(uint256 _newMaxReplayTimes)`:**
    *   Owner-only function to change the `maxReplayTimes` value.
    *   Emits `UpdateMaxReplayTimes`.

### Key Events

*   **`SentMessage(address indexed sender, address indexed target, uint256 value, uint256 messageNonce, uint256 gasLimit, bytes message)`:** Emitted when an L1->L2 message is successfully sent to `L1MessageQueueV2`.
*   **`RelayedMessage(bytes32 indexed messageHash)`:** Emitted when an L2->L1 message is successfully relayed and executed on L1.
*   **`FailedRelayedMessage(bytes32 indexed messageHash)`:** Emitted if the execution of a relayed L2->L1 message fails on L1.
*   **`UpdateMaxReplayTimes(uint256 oldMaxReplayTimes, uint256 newMaxReplayTimes)`:** Emitted when `maxReplayTimes` is updated.
*   **(Inherited from `ScrollMessengerBase`):** `UpdateFeeVault`, `Paused`, `Unpaused`.

### Interactions

*   **`ScrollChain`:**
    *   Queries `isBatchFinalized()` and `withdrawRoots()` during `relayMessageWithProof`.
*   **`L1MessageQueueV1`:**
    *   Calls `dropCrossDomainMessage()` during `dropMessage`.
*   **`L1MessageQueueV2`:**
    *   Calls `appendCrossDomainMessage()` during `sendMessage` and `replayMessage`.
    *   Calls `estimateCrossDomainMessageFee()` and `nextCrossDomainMessageIndex()` during `sendMessage` and `replayMessage`.
*   **`FeeVault`:**
    *   Receives fees collected during `sendMessage` and `replayMessage`.
*   **User Contracts (implementing `IMessageDropCallback`):**
    *   Calls `onDropMessage()` on the original L1 sender during `dropMessage`.
*   **`L2ScrollMessenger` (Counterpart):**
    *   Receives messages sent via `L1MessageQueueV2` on L2.
    *   Sends messages that are eventually relayed by `L1ScrollMessenger` on L1.
*   **Users/L1 Gateways:**
    *   Call `sendMessage()` to send messages to L2.
    *   Call `relayMessageWithProof()` to process L2->L1 messages.
    *   Call `replayMessage()` or `dropMessage()` for specific L1->L2 message outcomes.

## 2. L1MessageQueueV1.sol

### Purpose

`L1MessageQueueV1.sol` is the legacy queue for L1->L2 messages, primarily used for messages sent before the EuclidV2 upgrade. It stores hashes of messages and tracks their status (pending, popped/skipped, finalized, dropped). It interacts closely with `ScrollChain` which dictates the status of messages based on L2 batch processing and with `L1ScrollMessenger` for dropping messages. Fee estimation in this version relies on a configurable `gasOracle`.

### Key State Variables

*   **`messenger` (immutable `address`):** Address of `L1ScrollMessenger`.
*   **`scrollChain` (immutable `address`):** Address of `ScrollChain`.
*   **`enforcedTxGateway` (immutable `address`):** Address of `EnforcedTxGateway`.
*   **`gasOracle` (`address`):** Address of the `IL2GasPriceOracle` used for fee estimation.
*   **`messageQueue` (`bytes32[]`):** An array storing the EIP-2718 typed transaction hashes of the L1->L2 messages.
*   **`pendingQueueIndex` (`uint256`):** The index of the next message to be popped by `ScrollChain`. Messages from `nextUnfinalizedQueueIndex` to `pendingQueueIndex-1` are committed but not yet finalized.
*   **`maxGasLimit` (`uint256`):** The maximum gas limit allowed for a single L1->L2 message processed through this queue.
*   **`droppedMessageBitmap` (`BitMapsUpgradeable.BitMap`):** A bitmap to track messages that have been successfully dropped.
*   **`skippedMessageBitmap` (mapping `uint256 => uint256`):** A mapping of bitmaps to track messages that were skipped by L2 sequencers during batch creation.
*   **`nextUnfinalizedQueueIndex` (`uint256`):** The index of the first message in the queue that has not yet been finalized by `ScrollChain`.

### Key Functions

*   **`appendCrossDomainMessage(address _target, uint256 _gasLimit, bytes calldata _data)`:**
    *   Called by `L1ScrollMessenger` (historically).
    *   Validates `_gasLimit` against `maxGasLimit` and intrinsic gas.
    *   Computes the message hash (using `computeTransactionHash`) and stores it in `messageQueue`.
    *   Emits `QueueTransaction`.

*   **`appendEnforcedTransaction(address _sender, address _target, uint256 _value, uint256 _gasLimit, bytes calldata _data)`:**
    *   Called by `EnforcedTxGateway`.
    *   Similar to `appendCrossDomainMessage` but for enforced transactions.
    *   Emits `QueueTransaction`.

*   **`popCrossDomainMessage(uint256 _startIndex, uint256 _count, uint256 _skippedBitmap)`:**
    *   Called by `ScrollChain` when an L2 batch including messages from this queue is committed to L1.
    *   `_skippedBitmap` indicates which of the `_count` messages starting from `_startIndex` were skipped on L2.
    *   Updates `skippedMessageBitmap` and increments `pendingQueueIndex`.
    *   Emits `DequeueTransaction`.

*   **`resetPoppedCrossDomainMessage(uint256 _startIndex)`:**
    *   Called by `ScrollChain` if a committed L2 batch (that popped messages from this queue) is reverted on L1 before finalization.
    *   Clears the `skippedMessageBitmap` for the affected range and resets `pendingQueueIndex` to `_startIndex`.
    *   Emits `ResetDequeuedTransaction`.

*   **`finalizePoppedCrossDomainMessage(uint256 _newFinalizedQueueIndexPlusOne)`:**
    *   Called by `ScrollChain` when an L2 batch is finalized on L1.
    *   Updates `nextUnfinalizedQueueIndex` to `_newFinalizedQueueIndexPlusOne`, marking messages up to this point as finalized.
    *   Emits `FinalizedDequeuedTransaction`.

*   **`dropCrossDomainMessage(uint256 _index)`:**
    *   Called by `L1ScrollMessenger`'s `dropMessage` function.
    *   Requires the message at `_index` to be finalized (`_index < nextUnfinalizedQueueIndex`), skipped (`_isMessageSkipped(_index)`), and not already dropped.
    *   Sets the corresponding bit in `droppedMessageBitmap`.
    *   Emits `DropTransaction`.

*   **`estimateCrossDomainMessageFee(uint256 _gasLimit)` / `calculateIntrinsicGasFee(bytes calldata _calldata)`:**
    *   View functions to estimate fees based on the `gasOracle`.
    *   `computeTransactionHash()`: Pure function to compute the EIP-2718 typed transaction hash for a message.

### Key Events

*   **`QueueTransaction(address indexed sender, address indexed target, uint256 value, uint64 queueIndex, uint256 gasLimit, bytes data)`:** Emitted when a new message is appended.
*   **`DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap)`:** Emitted when messages are popped.
*   **`ResetDequeuedTransaction(uint256 startIndex)`:** Emitted when popped messages are reset.
*   **`FinalizedDequeuedTransaction(uint256 finalizedIndex)`:** Emitted when messages are finalized.
*   **`DropTransaction(uint256 index)`:** Emitted when a message is dropped.
*   **`UpdateGasOracle(...)`, `UpdateMaxGasLimit(...)`:** Owner-only updates.

### Interactions

*   **`L1ScrollMessenger`:**
    *   Historically called `appendCrossDomainMessage`.
    *   Calls `dropCrossDomainMessage`.
*   **`ScrollChain`:**
    *   Calls `popCrossDomainMessage`, `resetPoppedCrossDomainMessage`, and `finalizePoppedCrossDomainMessage`.
*   **`EnforcedTxGateway`:**
    *   Calls `appendEnforcedTransaction`.
*   **`IL2GasPriceOracle` (Gas Oracle):**
    *   Queried by `estimateCrossDomainMessageFee` and `calculateIntrinsicGasFee`.

## 3. L1MessageQueueV2.sol

### Purpose

`L1MessageQueueV2.sol` is the current primary queue for L1->L2 messages, introduced after the EuclidV2 upgrade. It improves upon `L1MessageQueueV1` by incorporating a rolling hash mechanism for all messages and storing enqueue timestamps. This rolling hash is used as part of the input for ZK proofs in `ScrollChain`, ensuring the integrity and order of messages. Fee estimation is tied to L1 basefee and parameters from `SystemConfig`. Unlike V1, V2 does not have a concept of "skipped" messages that `ScrollChain` needs to manage via a bitmap during popping; messages are expected to be processed in order by L2.

### Key State Variables

*   **`messenger` (immutable `address`):** Address of `L1ScrollMessenger`.
*   **`scrollChain` (immutable `address`):** Address of `ScrollChain`.
*   **`enforcedTxGateway` (immutable `address`):** Address of `EnforcedTxGateway`.
*   **`messageQueueV1` (immutable `address`):** Address of `L1MessageQueueV1`, used during initialization to set starting indices.
*   **`systemConfig` (immutable `address`):** Address of `SystemConfig` contract, used for fee parameters and gas limits.
*   **`messageRollingHashes` (mapping `uint256 => bytes32`):** Stores an encoded value for each message. The top 224 bits are the rolling hash (keccak256(prev_rolling_hash, current_message_hash)), and the lower 32 bits are the `block.timestamp` of when the message was enqueued.
*   **`firstCrossDomainMessageIndex` (`uint256`):** The queue index at which this contract starts managing messages (messages before this are in `L1MessageQueueV1`).
*   **`nextCrossDomainMessageIndex` (`uint256`):** The queue index for the next message to be appended. Represents the total count of messages across V1 and V2.
*   **`nextUnfinalizedQueueIndex` (`uint256`):** The index of the first message in this queue (or V1 if applicable) that has not yet been finalized by `ScrollChain`.

### Key Functions

*   **`appendCrossDomainMessage(address _target, uint256 _gasLimit, bytes calldata _data)`:**
    *   Called by `L1ScrollMessenger`.
    *   Validates `_gasLimit` against `SystemConfig` parameters and intrinsic gas.
    *   Computes the message hash.
    *   Calculates the new rolling hash by hashing the previous rolling hash with the current message hash.
    *   Stores the new rolling hash combined with `block.timestamp` in `messageRollingHashes`.
    *   Increments `nextCrossDomainMessageIndex`.
    *   Emits `QueueTransaction`.

*   **`appendEnforcedTransaction(address _sender, address _target, uint256 _value, uint256 _gasLimit, bytes calldata _data)`:**
    *   Called by `EnforcedTxGateway`.
    *   Similar to `appendCrossDomainMessage` but for enforced transactions.
    *   Emits `QueueTransaction`.

*   **`finalizePoppedCrossDomainMessage(uint256 _nextUnfinalizedQueueIndex)`:**
    *   Called by `ScrollChain` when L2 batches are finalized.
    *   Updates its internal `nextUnfinalizedQueueIndex` to the provided value, marking messages up to this point as finalized.
    *   Emits `FinalizedDequeuedTransaction`.

*   **`getMessageRollingHash(uint256 queueIndex)` / `getMessageEnqueueTimestamp(uint256 queueIndex)`:**
    *   View functions to retrieve the rolling hash and enqueue timestamp for a given message index by decoding the value from `messageRollingHashes`.
    *   `getMessageRollingHash` is crucial for `ScrollChain` when preparing inputs for ZK proof verification.
    *   `getMessageEnqueueTimestamp` (via `getFirstUnfinalizedMessageEnqueueTime`) is used by `ScrollChain` for enforced mode checks.

*   **`estimateL2BaseFee()` / `estimateCrossDomainMessageFee(uint256 _gasLimit)`:**
    *   View functions for fee estimation.
    *   `estimateL2BaseFee` uses `block.basefee` (L1 basefee) and `overhead`/`scalar` parameters from `SystemConfig`.
    *   `estimateCrossDomainMessageFee` multiplies the L2 base fee by `_gasLimit`.
    *   `calculateIntrinsicGasFee()`: Pure function to calculate L1 intrinsic gas for a message.
    *   `computeTransactionHash()`: Pure function to compute the EIP-2718 typed transaction hash.

### Key Events

*   **`QueueTransaction(address indexed sender, address indexed target, uint256 value, uint64 queueIndex, uint256 gasLimit, bytes data)`:** Emitted when a new message is appended.
*   **`FinalizedDequeuedTransaction(uint256 finalizedIndex)`:** Emitted when messages are finalized.

### Interactions

*   **`L1ScrollMessenger`:**
    *   Calls `appendCrossDomainMessage`.
    *   Queries `estimateCrossDomainMessageFee` and `nextCrossDomainMessageIndex`.
*   **`ScrollChain`:**
    *   Calls `finalizePoppedCrossDomainMessage`.
    *   Queries `getMessageRollingHash` and `getFirstUnfinalizedMessageEnqueueTime`.
*   **`EnforcedTxGateway`:**
    *   Calls `appendEnforcedTransaction`.
*   **`SystemConfig`:**
    *   Queried for `messageQueueParameters` (maxGasLimit, baseFeeOverhead, baseFeeScalar) for gas validation and fee estimation.
*   **`L1MessageQueueV1`:**
    *   Referenced during `initialize()` to set the `firstCrossDomainMessageIndex` and `nextCrossDomainMessageIndex` to continue sequentially from where V1 left off.
