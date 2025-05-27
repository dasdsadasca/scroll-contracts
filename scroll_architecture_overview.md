# Scroll Protocol: High-Level Architectural Overview

## 1. Introduction

Scroll is a Layer 2 (L2) scaling solution for Ethereum, designed to enhance transaction throughput and reduce gas costs while maintaining a high level of security and decentralization by leveraging Ethereum's consensus. It achieves this through a zkEVM (Zero-Knowledge Ethereum Virtual Machine) based rollup technology. Transactions are executed on Scroll's L2, bundled into batches, and then proven to L1 Ethereum via validity proofs.

## 2. Core Layers

The Scroll architecture primarily consists of two layers:

*   **Layer 1 (L1 - Ethereum Mainnet):** This is the foundational security layer. L1 contracts are responsible for:
    *   Verifying proofs of L2 state transitions.
    *   Finalizing L2 batches.
    *   Managing asset bridging between L1 and L2.
    *   Facilitating communication between L1 and L2.
*   **Layer 2 (L2 - Scroll Network):** This is the execution layer where user transactions occur. L2 is designed to be EVM-equivalent, allowing Ethereum smart contracts to be deployed and executed with minimal changes. Key functions include:
    *   Executing transactions.
    *   Bundling transactions into batches.
    *   Generating data for validity proofs.
    *   Facilitating communication with L1.

## 3. Key Components on Layer 1 (Ethereum)

*   **`ScrollChain` (e.g., `IScrollChain.sol`):**
    *   The core L1 contract responsible for managing the state of the Scroll rollup.
    *   It receives committed batches of L2 transactions from Sequencers.
    *   It receives and verifies validity proofs from Provers (potentially via `MultipleVersionRollupVerifier` which can use different `ZkEvmVerifier` versions).
    *   It finalizes batches once proofs are verified, making the L2 state changes canonical on L1.
    *   Manages sequencer and prover whitelisting/permissions.
    *   Interacts with `L1MessageQueue` to process L1->L2 messages.

*   **`L1ScrollMessenger` (e.g., `IL1ScrollMessenger.sol`, `ScrollMessengerBase.sol`):**
    *   Facilitates communication from L2 to L1 and L1 to L2.
    *   For L2->L1 messages, it allows relaying messages with proof of inclusion in an L2 batch (verified against `ScrollChain`'s `withdrawRoots`).
    *   For L1->L2 messages, it enqueues messages into the `L1MessageQueue`.
    *   Handles message replays and dropping of messages.

*   **`L1MessageQueue` (e.g., `IL1MessageQueueV1.sol`, `IL1MessageQueueV2.sol`):**
    *   A queue for messages initiated on L1 destined for L2.
    *   Sequencers on L2 read messages from this queue to include them in L2 blocks.
    *   `ScrollChain` marks messages as processed/popped and finalized.
    *   Manages message fee estimation (`estimateCrossDomainMessageFee`).
    *   `IL1MessageQueueV2` introduces concepts like message rolling hash and enqueue timestamps.

*   **L1 Gateways:** These contracts manage the bridging of assets between L1 and L2.
    *   **`L1GatewayRouter` (e.g., `IL1GatewayRouter.sol`):**
        *   A central router that directs asset bridging requests to the appropriate specific gateway based on the token type.
        *   Manages mappings from token addresses to their respective gateway contracts.
    *   **`L1ETHGateway` (part of `IL1GatewayRouter.sol`):** Handles ETH deposits and withdrawals.
    *   **`L1StandardERC20Gateway` / `L1CustomERC20Gateway` / `L1ERC20Gateway.sol` (base):** Handles bridging of standard and custom ERC20 tokens. Users deposit tokens on L1, which are then locked, and corresponding tokens are minted/unlocked on L2. For withdrawals, L2 tokens are burned/locked, and L1 tokens are unlocked.
    *   **`L1ERC721Gateway` / `L1ERC1155Gateway`:** Handle bridging of ERC721 and ERC1155 NFTs.
    *   **`L1BatchBridgeGateway` (e.g., `L1BatchBridgeGateway.sol`):** A specialized gateway for batching multiple ERC20 token deposits into fewer L2 transactions, optimizing gas costs. It collects deposits, and a keeper triggers the batch execution to L2.
    *   **`L1LidoGateway` (e.g., `L1LidoGateway.sol`):** A specialized gateway for bridging Lido's stETH and wstETH tokens between L1 and L2, interacting with Lido's specific contracts and ensuring proper accounting of staking rewards.

## 4. Key Components on Layer 2 (Scroll Network)

*   **`L2ScrollMessenger` (e.g., `IL2ScrollMessenger.sol`, `ScrollMessengerBase.sol`):**
    *   Facilitates communication from L1 to L2 and L2 to L1.
    *   For L1->L2 messages, it receives relayed messages (originally from `L1MessageQueue`) and executes them on L2.
    *   For L2->L1 messages, it sends messages to the `L2MessageQueue` to be included in the L2 state root.

*   **`L2MessageQueue` (e.g., `L2MessageQueue.sol`):**
    *   A queue for messages initiated on L2 destined for L1.
    *   It uses an `AppendOnlyMerkleTree` to store message hashes. The root of this tree (`withdrawRoot`) is included in L2 batch headers and submitted to `ScrollChain` on L1. This root is crucial for proving L2->L1 message inclusion on L1.

*   **L2 Gateways:** Counterparts to the L1 Gateways, managing assets on the L2 side.
    *   **`L2GatewayRouter` (e.g., `IL2GatewayRouter.sol`):**
        *   Similar to its L1 counterpart, it routes asset bridging requests to the appropriate L2 gateway.
    *   **`L2ETHGateway`:** Handles ETH deposits (minting L2 ETH) and withdrawals (burning L2 ETH).
    *   **`L2StandardERC20Gateway` / `L2CustomERC20Gateway` / `L2ERC20Gateway.sol` (base):** Handles the L2 side of ERC20 bridging, typically involving minting "Scroll-wrapped" tokens upon deposit from L1 and burning them upon withdrawal to L1.
    *   **`L2ERC721Gateway` / `L2ERC1155Gateway`:** Handle the L2 side of NFT bridging.
    *   **`L2BatchBridgeGateway` (e.g., `L2BatchBridgeGateway.sol`):** The L2 counterpart to the `L1BatchBridgeGateway`. It receives batched deposit instructions from L1 and distributes the tokens to the respective users on L2.
    *   **`L2LidoGateway` (e.g., `L2LidoGateway.sol`):** The L2 counterpart for Lido token bridging, managing L2 wstETH.

*   **Predeployed Contracts:** These are special contracts at fixed addresses on L2, providing essential functionalities.
    *   **`L1GasPriceOracle` (e.g., `IL1GasPriceOracle.sol` on L2):** Provides L1 gas price information on L2, which is necessary for calculating the L1 component of L2 transaction fees.
    *   **`L1BlockContainer` (e.g., `IL1BlockContainer.sol`):** Stores information about L1 blocks on L2.
    *   **`L2MessageQueue` (already mentioned):** A predeploy for L2->L1 message passing.
    *   **`WrappedEther` (e.g., `WrappedEther.sol`):** The WETH contract on L2.
    *   **`L2TxFeeVault`:** Collects transaction fees on L2.

## 5. Transaction and Data Flow

1.  **Transaction Execution (L2):** Users submit transactions to L2 Sequencers.
2.  **Batching (L2):** Sequencers execute transactions, order them, and group them into batches.
3.  **Commit (L1):** Sequencers commit these batches to the `ScrollChain` contract on L1. This involves submitting transaction data (often as calldata or via blobs after EIP-4844) and a batch header.
4.  **Proof Generation (Off-chain):** Provers take the committed batch data and generate Zero-Knowledge proofs (validity proofs) demonstrating the correctness of the L2 state transition.
5.  **Proof Submission (L1):** Provers submit these proofs to the `ScrollChain` (often via a `RollupVerifier` or `MultipleVersionRollupVerifier` which uses specific `ZkEvmVerifier` contracts).
6.  **Verification and Finalization (L1):** The `ScrollChain` contract verifies the submitted proofs. If valid, the batch is finalized, and the L2 state transition becomes canonical. The `ScrollChain` updates its state roots and withdrawal roots.

## 6. Message Flow

*   **L1 to L2 Communication:**
    1.  A user or contract on L1 calls a function on `L1ScrollMessenger` (often via a Gateway like `L1ETHGateway` or `L1ERC20Gateway`).
    2.  `L1ScrollMessenger` appends the message to the `L1MessageQueue`.
    3.  L2 Sequencers observe the `L1MessageQueue` and include pending messages in L2 blocks.
    4.  The `L2ScrollMessenger` executes the message on L2, calling the target L2 contract.
    5.  `ScrollChain` on L1 marks messages as processed when batches containing them are finalized.

*   **L2 to L1 Communication:**
    1.  A user or contract on L2 calls a function on `L2ScrollMessenger` (often via an L2 Gateway).
    2.  `L2ScrollMessenger` appends the message hash to the `L2MessageQueue` (which builds a Merkle tree). The `withdrawRoot` of this tree is part of the L2 batch data.
    3.  The batch containing this `withdrawRoot` is committed and finalized on L1 by `ScrollChain`.
    4.  To execute the message on L1, the user (or a relayer) calls `relayMessageWithProof` on `L1ScrollMessenger`, providing the message details and a Merkle proof verifying its inclusion in a finalized `withdrawRoot` stored in `ScrollChain`.
    5.  `L1ScrollMessenger` verifies the proof and executes the message on L1.

## 7. Specialized Bridges

*   **Batch Bridge (`L1BatchBridgeGateway`, `L2BatchBridgeGateway`):**
    *   Allows users to deposit ERC20 tokens on L1, which are then grouped by a keeper.
    *   The keeper triggers a single message to L2 containing all deposits for a token in that batch.
    *   `L2BatchBridgeGateway` receives this message and distributes the tokens to the individual recipients on L2.
    *   This reduces the L1 gas cost per individual deposit.

*   **Lido Bridge (`L1LidoGateway`, `L2LidoGateway`):**
    *   Specifically designed for bridging Lido's stETH (and wstETH).
    *   Handles the complexities of rebasing tokens and ensures that staked ETH value is correctly represented and transferable between L1 and L2.
    *   Interacts with Lido's core contracts on L1.

This overview provides a foundational understanding of the Scroll protocol's architecture, highlighting its key components and their interactions in facilitating a scalable and secure L2 solution for Ethereum.
