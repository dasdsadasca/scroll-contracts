# Scroll Protocol: High-Level Architectural Overview

## 1. Introduction to Scroll as an L2 Scaling Solution

Scroll is a Layer 2 (L2) scaling solution for Ethereum, designed to enhance transaction throughput and reduce gas fees while maintaining a high degree of security and decentralization by leveraging the security of the Ethereum mainnet (Layer 1). It operates as a zkRollup, specifically a zkEVM (Zero-Knowledge Ethereum Virtual Machine), meaning it aims to be fully compatible with existing Ethereum applications and tools. Scroll bundles (or "rolls up") multiple transactions executed on its L2 network, generates a cryptographic proof (a ZK-proof) attesting to the validity of these transactions, and then submits this proof to a smart contract on L1. This way, the computationally expensive work is done off-chain on L2, and L1 is primarily used for data availability and proof verification, leading to significant scaling benefits.

## 2. Interaction between L1 (Ethereum Mainnet) and L2 (Scroll Network)

The interaction between L1 and L2 in the Scroll protocol is bidirectional and crucial for its operation:

*   **L2 to L1 (Rollup):**
    *   **Transaction Batching:** Sequencers on L2 collect user transactions, order them, and form batches.
    *   **State Commitment:** These batches are executed on L2, leading to a new L2 state. The Sequencer then commits a summary of these batches (e.g., a Merkle root of transaction data and state roots) to the `ScrollChain` contract on L1.
    *   **Proof Generation:** Off-chain Provers generate ZK-proofs for the validity of the state transitions corresponding to the committed batches.
    *   **Proof Verification & Finalization:** These proofs are submitted to the `ScrollChain` contract (which uses a `Verifier` contract) on L1. If the proof is valid, the L2 state transition is considered finalized on L1. This ensures that L2 operations are anchored to L1 security.

*   **L1 to L2 (Bridging & Messaging):**
    *   **Asset Bridging (Deposits):** Users can deposit assets (ETH, ERC20 tokens) from L1 to L2. They interact with Gateway contracts on L1 (e.g., `L1GatewayRouter`), which lock the assets on L1 and trigger a message to L2 (via `L1ScrollMessenger`) to mint corresponding wrapped assets or unlock native assets on L2.
    *   **Asset Bridging (Withdrawals):** Users initiate withdrawals on L2 by interacting with Gateway contracts on L2 (e.g., `L2GatewayRouter`). This burns the assets on L2 and sends a message to L1 (via `L2ScrollMessenger`). After a challenge period and L2 batch finalization on L1, users can claim their assets on L1 from the L1 Gateway contracts.
    *   **Generic Message Passing:** Besides asset bridging, the `L1ScrollMessenger` and `L2ScrollMessenger` contracts enable arbitrary data and contract calls to be passed between L1 and L2, facilitating complex cross-chain interactions.

## 3. Core Components and Their Roles

### Gateways (Routers & Specific Asset Gateways)

*   **Function:** Gateways are responsible for facilitating the movement of assets (ETH and ERC20 tokens) between L1 and L2.
*   **`L1GatewayRouter` (on L1) & `L2GatewayRouter` (on L2):** These act as the primary entry points for users wanting to bridge assets. They route deposit/withdrawal requests to the appropriate specific asset gateway (e.g., `L1ETHGateway`, `L1ERC20Gateway` on L1, and their counterparts on L2).
    *   **Deposits (L1 to L2):** A user interacts with `L1GatewayRouter` to deposit, say, ETH. The router calls the `L1ETHGateway` which locks the ETH and then uses `L1ScrollMessenger` to send a message to L2. On L2, this message is picked up, and the corresponding amount of ETH is made available to the user (e.g., by minting wrapped ETH or assigning native L2 ETH).
    *   **Withdrawals (L2 to L1):** A user interacts with `L2GatewayRouter` to withdraw ETH. The router calls the L2 ETH Gateway which burns/locks the L2 ETH and then uses `L2ScrollMessenger` to send a message to L1. After the L2 transaction batch containing this withdrawal is finalized on L1 (via `ScrollChain`), the user can claim their ETH from the `L1ETHGateway`.
*   **Specific Asset Gateways (e.g., `L1ETHGateway`, `L1ERC20Gateway`, `L2ETHGateway`, `L2ERC20Gateway`):** These contracts handle the actual locking/unlocking of assets on L1 and minting/burning of corresponding assets on L2.

### Messengers (`L1ScrollMessenger` & `L2ScrollMessenger`)

*   **Function:** These contracts are responsible for generic message passing between L1 and L2. They are the communication backbone for more than just asset bridging; they can relay arbitrary data and trigger contract calls across layers.
*   **`L1ScrollMessenger` (on L1):**
    *   Relays messages from L1 to L2. When a contract on L1 (like a Gateway) wants to send a message to L2, it calls `L1ScrollMessenger`.
    *   It interacts with `L1MessageQueueV1` (or `V2`) to queue the outgoing message.
    *   The `ScrollChain` contract (specifically, Sequencers via `ScrollChain`) reads from this queue to include L1 messages in L2 blocks.
*   **`L2ScrollMessenger` (on L2):**
    *   Relays messages from L2 to L1. When a contract on L2 (like an L2 Gateway) wants to send a message to L1, it calls `L2ScrollMessenger`.
    *   It interacts with the `L2MessageQueue` to queue the outgoing message.
    *   These messages are included in L2 blocks, and their hashes are part of the commitment submitted to `ScrollChain` on L1. Once a batch is finalized on L1, these messages can be executed/relayed on L1.

### Rollup Contract (`ScrollChain` on L1)

*   **Function:** This is the core L1 contract that anchors the L2 chain to Ethereum. It has several key responsibilities:
    *   **Receiving L2 Transaction Batches:** Sequencers submit batches of L2 transactions (or commitments to them) to `ScrollChain`.
    *   **Managing Commitments:** It stores these commitments, which represent sequences of L2 blocks.
    *   **Interacting with Verifiers:** When a ZK-proof for a sequence of batches is submitted (by a Prover), `ScrollChain` calls the `MultipleVersionRollupVerifier` contract to verify the proof's validity.
    *   **Finalizing Batches:** If a proof is valid, `ScrollChain` marks the corresponding L2 batches as finalized. This means the L1 state now recognizes the L2 state transitions as canonical.
    *   **Processing L1 Messages:** It plays a role in ensuring messages from `L1MessageQueue` are eventually processed on L2 by including them in the L2 blocks whose commitments are submitted.
    *   **Processing L2 Messages:** It facilitates the execution of messages sent from L2 (via `L2ScrollMessenger` and its queue) after the corresponding L2 batch is finalized on L1.

### Message Queues (`L1MessageQueueV1`/`V2` on L1, `L2MessageQueue` on L2)

*   **`L1MessageQueueV1`/`V2` (on L1):**
    *   **Role:** Stores messages sent from L1 destined for L2. `L1ScrollMessenger` enqueues messages here.
    *   **Ordering:** Ensures messages are processed in the order they were sent from L1.
    *   **Consumption:** Sequencers (interacting with `ScrollChain`) read messages from this queue to be included and processed on L2.
*   **`L2MessageQueue` (on L2):**
    *   **Role:** Stores messages sent from L2 destined for L1. `L2ScrollMessenger` enqueues messages here.
    *   **Ordering:** Ensures messages are processed in the order they were sent from L2.
    *   **Commitment:** The Merkle root of this queue (or messages within it) is part of the L2 state commitment submitted to `ScrollChain`. Once an L2 batch is finalized on L1, messages from this queue can be proven and executed on L1.

### Verifiers (`MultipleVersionRollupVerifier` on L1)

*   **Role:** This L1 contract is responsible for verifying the ZK-proofs submitted by off-chain Provers.
*   **Interaction:** The `ScrollChain` contract calls the `verifyProof` (or similar) function on the `MultipleVersionRollupVerifier` when a proof is submitted for a set of L2 batches.
*   **Multiple Versions:** The name suggests it can support different versions of ZK-proof systems or provers, allowing for upgrades to the proving technology without disrupting the entire protocol. If the proof is valid, it confirms that the L2 state transitions occurred according to the protocol rules.

### Sequencers & Provers (Off-Chain Roles)

*   **Sequencers (Off-Chain):**
    *   **Role:** These are nodes responsible for collecting L2 transactions from users, ordering them, executing them to produce L2 blocks, and batching them together.
    *   **Interaction:** Sequencers submit these batches (or commitments to them, like Merkle roots of transactions and state roots) to the `ScrollChain` contract on L1. They also fetch messages from `L1MessageQueue` to include in L2 blocks.
*   **Provers (Off-Chain):**
    *   **Role:** These are specialized, computationally intensive systems that take the transaction batches executed by Sequencers and generate ZK-proofs for them. These proofs mathematically attest to the validity of every transaction in the batch and the resulting state transition.
    *   **Interaction:** Provers submit these generated proofs to the `ScrollChain` contract on L1, which then uses the `MultipleVersionRollupVerifier` to verify them. The generation of proofs is decoupled from sequencing to allow for efficiency and specialization.

This overview describes the fundamental components and their interactions, forming the basis of Scroll's L2 scaling solution.
