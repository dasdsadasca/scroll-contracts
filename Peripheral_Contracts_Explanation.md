# Scroll Protocol: Explanation of Message Queues, Standard Gateways, and Verifier

This document provides an explanation for several key contracts within the Scroll protocol that support the main architectural components like Routers, Messengers, and the `ScrollChain`.

## 1. L1 Message Queues: `L1MessageQueueV1.sol` and `L1MessageQueueV2.sol`

*   **Purpose:**
    These Layer 1 (L1) smart contracts are designed to queue messages that are being sent from L1 to Layer 2 (L2). They act as a persistent, ordered store for these cross-domain messages until they are processed by the L2 network.

*   **Interaction:**

    *   **`L1ScrollMessenger` Interaction:**
        *   `L1ScrollMessenger.sendMessage()` and `L1ScrollMessenger.replayMessage()` primarily interact with **`L1MessageQueueV2.appendCrossDomainMessage()`** to add new L1-to-L2 messages or retry existing ones. The message data, along with associated ETH/WETH value, is passed to the queue.
        *   `L1ScrollMessenger.estimateCrossDomainMessageFee()` calls **`L1MessageQueueV2.estimateCrossDomainMessageFee()`** to calculate the cost of sending a message, which is crucial for users.
        *   For dropping messages (primarily older ones), `L1ScrollMessenger.dropMessage()` interacts with **`L1MessageQueueV1.dropCrossDomainMessage()`**, which involves marking a message as dropped and facilitating the return of associated value.

    *   **`ScrollChain` Interaction:**
        *   **`L1MessageQueueV1`:**
            *   `popCrossDomainMessage`: Called internally by `ScrollChain` (e.g., within `_popL1Messages` which is used by `commitBatchWithBlobProof`) when a Sequencer commits an older version batch. The Sequencer provides a `skippedL1MessageBitmap` indicating which messages were included or skipped in that L2 batch. `ScrollChain` uses this to update the state of `L1MessageQueueV1`.
            *   `finalizePoppedCrossDomainMessage`: Called by `ScrollChain` during `finalizeBundleWithProof` (for older batches). This marks the messages that were popped (processed or skipped) by a now-finalized L2 batch as fully finalized on L1.
        *   **`L1MessageQueueV2`:**
            *   `finalizePoppedCrossDomainMessage`: Called by `ScrollChain` during `finalizeBundlePostEuclidV2` (for newer batches). Similar to V1, this finalizes messages in `L1MessageQueueV2` that were processed in a now-finalized L2 batch.
            *   `getMessageRollingHash`: `ScrollChain` uses this function during `finalizeBundlePostEuclidV2`. The rolling hash of messages from `L1MessageQueueV2` is part of the public input for the ZK proof, ensuring that the Prover correctly processed the L1 messages.

*   **Key Difference Indication:**
    *   `L1MessageQueueV1` is primarily associated with older batch versions (pre-EuclidV2) and their specific message handling logic, including a "skip" mechanism that `L1ScrollMessenger.dropMessage` can act upon.
    *   `L1MessageQueueV2` is integrated with newer batch versions (post-EuclidV2). It offers features like on-chain fee estimation (`estimateCrossDomainMessageFee`) and provides a `messageRollingHash` which is a more robust way to include the state of the L1 message queue in the L2 proofs, enhancing security and data integrity for cross-chain messaging.

## 2. L2 Message Queue: `L2MessageQueue.sol`

*   **Purpose:**
    This is a predeployed smart contract on Layer 2 (L2) responsible for queuing messages originating from L2 that are destined for L1. It acts as an outbox for L2-to-L1 communications.

*   **Interaction:**
    *   **`L2ScrollMessenger` Interaction:**
        *   When a user or L2 contract calls `L2ScrollMessenger.sendMessage()`, the messenger computes a hash of the message details (`_from`, `_to`, `_value`, `_nonce`, `_message`).
        *   It then calls **`L2MessageQueue.appendMessage(messageHash)`** to add this single hash to the queue. The full message content is not stored in the `L2MessageQueue` contract itself to save L2 state space; the hash is sufficient to prove its inclusion.
    *   **Inclusion in L2 Batches and `ScrollChain`:**
        *   The L2 Sequencer, when creating an L2 block and subsequently a batch, includes these message hashes from `L2MessageQueue`.
        *   A Merkle tree is constructed from these message hashes (or a sequence of them). The root of this tree is known as the **`withdrawRoot`** (or `messageRoot`).
        *   This `withdrawRoot` is part of the data for each L2 batch that the Sequencer commits to `ScrollChain.sol` on L1.
        *   When `L1ScrollMessenger.relayMessageWithProof()` is called on L1 to process an L2-to-L1 message, the provided proof includes this message and its path in the Merkle tree. `L1ScrollMessenger` verifies this proof against the `withdrawRoot` (obtained from `ScrollChain` for the finalized batch) to ensure the message is authentic and was indeed part of a finalized L2 batch.

*   **Data:**
    The `L2MessageQueue` primarily stores message hashes. These hashes are used to build a Merkle tree. The Merkle root (`withdrawRoot`) is the critical piece of data that gets committed to L1 via `ScrollChain`, enabling secure and verifiable L2-to-L1 message relay.

## 3. Standard Gateway Contracts (General Concept)

*   **Purpose:**
    Standard Gateway contracts are specialized contracts on both L1 and L2 that implement the detailed logic for bridging specific types of assets (like ETH or standard ERC20 tokens) between the two layers. They work in conjunction with Gateway Routers (which direct traffic to them) and Scroll Messengers (which they use to send cross-chain messages).

*   **L1 Gateways (`L1ETHGateway.sol`, `L1StandardERC20Gateway.sol`):**
    *   These are called by `L1GatewayRouter.sol` during deposit operations.
    *   **`depositETH` (in `L1ETHGateway`):**
        *   Receives ETH from the user.
        *   Locks this ETH within the `L1ETHGateway` contract itself (or wraps it into WETH and locks the WETH).
        *   Calls `L1ScrollMessenger.sendMessage()` with details such as the L2 recipient, amount, and any necessary L2 execution gas, instructing the L2 side to credit the user with ETH.
    *   **`depositERC20` (in `L1StandardERC20Gateway`):**
        *   The user must first approve the `L1StandardERC20Gateway` to spend their ERC20 tokens.
        *   The gateway then calls `transferFrom` on the ERC20 token contract to pull the tokens from the user and lock them within the gateway.
        *   Calls `L1ScrollMessenger.sendMessage()` with details to inform L2 to mint corresponding wrapped ERC20 tokens for the user.
    *   **`finalizeWithdrawETH` / `finalizeWithdrawERC20`:**
        *   These functions are called by `L1ScrollMessenger.relayMessageWithProof()` when a valid withdrawal message from L2 (initiated by the user on L2 via `L2ETHGateway` or `L2StandardERC20Gateway`) is successfully processed on L1.
        *   For ETH: Unlocks the previously locked ETH (or unwraps WETH) and transfers it to the user's L1 address.
        *   For ERC20: Transfers the previously locked ERC20 tokens from the gateway back to the user's L1 address.

*   **L2 Gateways (`L2ETHGateway.sol`, `L2StandardERC20Gateway.sol`):**
    *   These are called by `L2GatewayRouter.sol` during withdrawal initiation or deposit finalization.
    *   **`withdrawETH` (in `L2ETHGateway`):**
        *   Receives ETH from the user on L2.
        *   This ETH is effectively burned or taken from the user on L2.
        *   Calls `L2ScrollMessenger.sendMessage()` to send a message to L1, instructing the `L1ETHGateway` to release the corresponding amount of ETH to the user on L1.
    *   **`withdrawERC20` (in `L2StandardERC20Gateway`):**
        *   The L2 representation of the ERC20 token (which was minted during deposit) is burned from the user's L2 balance.
        *   Calls `L2ScrollMessenger.sendMessage()` to inform L1, instructing `L1StandardERC20Gateway` to unlock the original ERC20 tokens for the user on L1.
    *   **`finalizeDepositETH` / `finalizeDepositERC20`:**
        *   These functions are called by `L2ScrollMessenger.relayMessage()` when a valid deposit message from L1 (initiated by the user on L1 via `L1ETHGateway` or `L1StandardERC20Gateway`) is successfully processed on L2.
        *   For ETH: Credits the user's L2 account with the specified amount of ETH.
        *   For ERC20: Mints the corresponding amount of the L2 wrapped representation of the ERC20 token and credits it to the user's L2 account.

## 4. `MultipleVersionRollupVerifier.sol` (Briefly)

*   **Purpose:**
    `MultipleVersionRollupVerifier.sol` on L1 acts as a **registry or dispatcher for different versions of Zero-Knowledge (ZK) proof verifier contracts.** As ZK-proof technology and the Scroll protocol's proof system evolve, new verifier contracts might be deployed to handle new proof formats or optimizations. This contract provides a stable interface for `ScrollChain` while allowing for backend verifier upgrades.

*   **Interaction:**
    *   When `ScrollChain.finalizeBundleWithProof()` or `ScrollChain.finalizeBundlePostEuclidV2()` is called by a Prover, it passes along the ZK proof and a `batchVersion` identifier.
    *   `ScrollChain` then calls `MultipleVersionRollupVerifier.verifyBundleProof(proof, publicInputs, batchVersion)`.
    *   Inside `MultipleVersionRollupVerifier`, there's logic (e.g., a mapping from `batchVersion` to verifier addresses) that determines which specific ZK-proof verifier contract is responsible for validating proofs of that particular `batchVersion`.
    *   It then **delegates the actual proof verification call to that specific underlying verifier contract.**
    *   This design allows the Scroll team to deploy new verifier contracts and simply update the registry in `MultipleVersionRollupVerifier` (e.g., via an ownership/admin function) to point to the new verifier for future batch versions, without needing to modify `ScrollChain`'s core logic each time the proof system is upgraded. This enhances modularity and upgradeability.
