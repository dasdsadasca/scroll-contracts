# ScrollChain.sol: Detailed Breakdown

## 1. Purpose

`ScrollChain.sol` is a critical L1 smart contract at the heart of the Scroll protocol. Its primary purpose is to maintain and manage the canonical state of the Scroll L2 chain on the Ethereum L1. It acts as the bridge and verifier between the L2 execution environment and the L1 security layer.

Its key responsibilities include:

*   **Receiving Batch Commitments:** Sequencers submit batches of L2 transactions to `ScrollChain`. These commitments include L2 transaction data (or references to it, like blob versioned hashes) and metadata about the batch.
*   **Verifying Validity Proofs:** Provers submit ZK (Zero-Knowledge) validity proofs to `ScrollChain` that attest to the correctness of the L2 state transitions within the committed batches. The contract delegates the actual proof verification to a specialized `MultipleVersionRollupVerifier` contract.
*   **Finalizing Batches:** Once a validity proof for a batch (or a bundle of batches) is successfully verified, `ScrollChain` marks these batches as finalized. This means the L2 state transitions are considered canonical and irreversible from the L1 perspective.
*   **Managing L1-L2 Message Queue:** It coordinates with `L1MessageQueueV1` and `L1MessageQueueV2` to ensure that L1-to-L2 messages are correctly processed and finalized as part of the L2 batches.
*   **Maintaining Rollup State:** It stores essential data about the rollup's progress, such as committed batch hashes, finalized L2 state roots, and L2 withdrawal roots (for L2-to-L1 messages).
*   **Enforcing Protocol Rules:** It implements logic for different batch versions, enforced batch submission modes, and access control for critical roles like Sequencers and Provers.

## 2. Key State Variables

*   **`layer2ChainId` (immutable `uint64`):** The chain ID of the corresponding L2 Scroll network.
*   **`messageQueueV1` (immutable `address`):** The address of the `L1MessageQueueV1` contract, used for older L1->L2 messages.
*   **`messageQueueV2` (immutable `address`):** The address of the `L1MessageQueueV2` contract, used for newer L1->L2 messages.
*   **`verifier` (immutable `address`):** The address of the `MultipleVersionRollupVerifier` contract, which is responsible for verifying the ZK proofs.
*   **`systemConfig` (immutable `address`):** The address of the `SystemConfig` contract, which stores various system-wide parameters like gas limits and enforced mode triggers.
*   **`maxNumTxInChunk` (`uint256`):** The maximum number of L2 transactions allowed within a single chunk of a batch.
*   **`isSequencer` (mapping `address => bool`):** A mapping indicating whether an address is authorized to act as a Sequencer.
*   **`isProver` (mapping `address => bool`):** A mapping indicating whether an address is authorized to act as a Prover.
*   **`committedBatches` (mapping `uint256 => bytes32`):** Stores the hash of each committed batch, indexed by the batch index. For newer batch versions (V7+), this mapping becomes sparse, only storing the hash of the *last* batch in a multi-batch commit.
*   **`finalizedStateRoots` (mapping `uint256 => bytes32`):** Stores the L2 state root after a batch (or bundle) is finalized, indexed by the batch index. This mapping is also sparse for newer versions.
*   **`withdrawRoots` (mapping `uint256 => bytes32`):** Stores the Merkle root of L2-to-L1 messages for each finalized batch, indexed by the batch index. This is crucial for proving L2->L1 message inclusion. This mapping is also sparse.
*   **`initialEuclidBatchIndex` (`uint256`):** Marks the batch index where the Euclid upgrade (introducing specific batch versions like V5) occurred.
*   **`miscData` (`ScrollChainMiscData` struct):** A packed struct containing several important state variables to save storage slots:
    *   `lastCommittedBatchIndex` (`uint64`): The index of the most recently committed batch.
    *   `lastFinalizedBatchIndex` (`uint64`): The index of the most recently finalized batch.
    *   `lastFinalizeTimestamp` (`uint32`): The timestamp of the last batch finalization.
    *   `flags` (`uint8`): A bitfield for boolean flags:
        *   `V1_MESSAGES_FINALIZED_OFFSET (0)`: Indicates if all messages from `L1MessageQueueV1` have been finalized.
        *   `ENFORCED_MODE_OFFSET (1)`: Indicates if the contract is currently in "enforced batch mode".
    *   `reserved` (`uint88`): Reserved space for future flags or small data.

## 3. Key Functions

*   **`initialize()` / `initializeV2()`:**
    *   `initialize()`: Sets up initial parameters like `maxNumTxInChunk`. Called once upon deployment.
    *   `initializeV2()`: A reinitializer to migrate state (like `lastCommittedBatchIndex`, `lastFinalizedBatchIndex`) from older storage slots into the `miscData` struct for gas optimization.

*   **`importGenesisBatch(bytes calldata _batchHeader, bytes32 _stateRoot)`:**
    *   Initializes the rollup by setting the state for batch 0.
    *   The `_batchHeader` contains metadata for the genesis batch (typically with many fields zeroed out except for data commitment).
    *   `_stateRoot` is the initial L2 state root.
    *   Emits `CommitBatch` and `FinalizeBatch` for batch 0.

*   **`commitBatchWithBlobProof(uint8 version, bytes calldata parentBatchHeader, bytes[] memory chunks, bytes calldata skippedL1MessageBitmap, bytes calldata blobDataProof)`:**
    *   Called by **Sequencers** to commit L2 batches (versions 4-6, before V7).
    *   `version`: Specifies the batch header encoding version.
    *   `parentBatchHeader`: The header of the preceding batch.
    *   `chunks`: An array of encoded L2 transaction data chunks.
    *   `skippedL1MessageBitmap`: A bitmap indicating which L1->L2 messages from the `L1MessageQueueV1` were skipped by the Sequencer.
    *   `blobDataProof`: Proof related to EIP-4844 blob data, verifying that the transaction data was made available (via `POINT_EVALUATION_PRECOMPILE_ADDR`).
    *   Validates batch structure, versioning, chunk limits, and blob data.
    *   Pops messages from `L1MessageQueueV1` based on the `skippedL1MessageBitmap`.
    *   Calculates and stores the `batchHash` in `committedBatches`.
    *   Updates `miscData.lastCommittedBatchIndex`.
    *   Emits `CommitBatch`.

*   **`commitBatches(uint8 version, bytes32 parentBatchHash, bytes32 lastBatchHash)`:**
    *   Called by **Sequencers** to commit L2 batches (version 7+).
    *   This function supports committing multiple batches where transaction data is expected to be in blobs associated with the L1 transaction.
    *   `version`: Batch version (must be >= 7).
    *   `parentBatchHash`: The hash of the batch preceding the first batch in this commit.
    *   `lastBatchHash`: The hash of the *last* batch being committed in this transaction (used for consistency checks).
    *   Iterates through blob versioned hashes (via `blobhash` opcode) to derive individual batch hashes.
    *   Stores only the `lastBatchHash` in `committedBatches` (making the mapping sparse).
    *   Updates `miscData.lastCommittedBatchIndex`.
    *   Emits `CommitBatch` for each derived batch.

*   **`finalizeBundleWithProof(bytes calldata batchHeader, bytes32 postStateRoot, bytes32 withdrawRoot, bytes calldata aggrProof)`:**
    *   Called by **Provers** to finalize a bundle of batches (versions <= 4 or >= 6, but not mixing pre/post Euclid batches).
    *   `batchHeader`: The header of the *last* batch in the bundle being finalized.
    *   `postStateRoot`: The L2 state root after executing all transactions in the bundle.
    *   `withdrawRoot`: The Merkle root of L2->L1 messages generated by the batches in this bundle.
    *   `aggrProof`: The ZK validity proof for the entire bundle of batches.
    *   Constructs public inputs for the proof using `committedBatches`, `finalizedStateRoots` of the previous batch, and the provided parameters.
    *   Calls `IRollupVerifier(verifier).verifyBundleProof()` to verify the `aggrProof`.
    *   If verification succeeds, updates `finalizedStateRoots`, `withdrawRoots`, and `miscData.lastFinalizedBatchIndex`, `miscData.lastFinalizeTimestamp`.
    *   Finalizes messages in `L1MessageQueueV1` via `_finalizePoppedL1Messages`.
    *   Emits `FinalizeBatch`.

*   **`finalizeBundlePostEuclidV2(bytes calldata batchHeader, uint256 totalL1MessagesPoppedOverall, bytes32 postStateRoot, bytes32 withdrawRoot, bytes calldata aggrProof)`:**
    *   Called by **Provers** to finalize a bundle of batches (typically version 7+). This is the primary finalization function for modern batches.
    *   Similar to `finalizeBundleWithProof` but tailored for newer batch versions and interacts with `L1MessageQueueV2`.
    *   `totalL1MessagesPoppedOverall`: The total number of L1 messages popped from `L1MessageQueueV2` up to and including this bundle. This is used to get a `messageQueueHash` from `L1MessageQueueV2` for the proof input.
    *   Constructs public inputs including the `messageQueueHash`.
    *   Calls `IRollupVerifier(verifier).verifyBundleProof()`.
    *   If verification succeeds, updates state similarly to `finalizeBundleWithProof`.
    *   Finalizes messages in `L1MessageQueueV2`.
    *   Emits `FinalizeBatch`.
    *   Includes logic to mark all V1 messages as finalized (`miscData.flags`) if conditions are met.

*   **`revertBatch(bytes calldata batchHeader)`:**
    *   Called by the **Owner** (typically a multisig or DAO with a timelock).
    *   Allows reverting committed but *unfinalized* batches.
    *   `batchHeader`: The header of the last batch that should *remain* after the revert. Batches after this one are effectively deleted from `committedBatches`.
    *   Ensures that only V7+ batches are reverted with this function (older versions might require contract downgrade for revert).
    *   Updates `miscData.lastCommittedBatchIndex`.
    *   Emits `RevertBatch`.

*   **`commitAndFinalizeBatch(uint8 version, bytes32 parentBatchHash, FinalizeStruct calldata finalizeStruct)`:**
    *   A permissionless function that can be called by anyone if the chain enters "enforced batch mode".
    *   Enforced mode is triggered if `L1MessageQueueV2` has pending messages for too long (`maxDelayMessageQueue` from `SystemConfig`) or if no batches have been finalized for too long (`maxDelayEnterEnforcedMode` from `SystemConfig`).
    *   If these conditions are met and the contract is not already in enforced mode, it first reverts any pending unfinalized batches and then enables enforced mode by setting `miscData.flags`.
    *   Once in enforced mode, this function allows committing (via `_commitBatchesFromV7`) and finalizing (via `_finalizeBundlePostEuclidV2`) a single batch using the provided `finalizeStruct` which includes the batch header and ZK proof.
    *   This ensures chain liveness even if regular Sequencers/Provers are offline.

*   **`addSequencer(address _account)` / `removeSequencer(address _account)`:**
    *   Called by the **Owner**.
    *   Adds or removes an address from the `isSequencer` mapping.
    *   Emits `UpdateSequencer`.

*   **`addProver(address _account)` / `removeProver(address _account)`:**
    *   Called by the **Owner**.
    *   Adds or removes an address from the `isProver` mapping.
    *   Emits `UpdateProver`.

*   **`setPause(bool _status)`:**
    *   Called by the **Owner**.
    *   Pauses or unpauses critical functions like `commitBatchWithBlobProof`, `finalizeBundleWithProof`, etc., using OpenZeppelin's `PausableUpgradeable`.

*   **`disableEnforcedBatchMode()`:**
    *   Called by the **Owner**.
    *   Allows manually exiting the "enforced batch mode".
    *   Emits `UpdateEnforcedBatchMode`.

## 4. Key Events

*   **`CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash)`:** Emitted when a new batch is successfully committed.
*   **`FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot)`:** Emitted when a batch (or a bundle ending with this batch) is successfully finalized after proof verification.
*   **`RevertBatch(uint256 indexed startBatchIndex, uint256 indexed finishBatchIndex)`:** Emitted when a range of batches is reverted. (Note: The `IScrollChain` interface also defines an event for reverting a single batch, but the implementation `revertBatch` in `ScrollChain.sol` emits this range-based event).
*   **`UpdateSequencer(address indexed account, bool status)`:** Emitted when a sequencer's status is updated.
*   **`UpdateProver(address indexed account, bool status)`:** Emitted when a prover's status is updated.
*   **`UpdateMaxNumTxInChunk(uint256 oldMaxNumTxInChunk, uint256 newMaxNumTxInChunk)`:** Emitted when `maxNumTxInChunk` is updated.
*   **`UpdateEnforcedBatchMode(bool enabled, uint256 lastCommittedBatchIndex)`:** Emitted when the contract enters or exits enforced batch mode.

## 5. Interactions

*   **`L1MessageQueueV1` / `L1MessageQueueV2`:**
    *   `ScrollChain` reads L1 message hashes from `L1MessageQueueV1` (via `getCrossDomainMessage`) during the `commitBatchWithBlobProof` process (specifically in `_loadL1MessageHashes`).
    *   It calls `popCrossDomainMessage` on `L1MessageQueueV1` to mark messages as included in a batch (some potentially skipped).
    *   It calls `finalizePoppedCrossDomainMessage` on `L1MessageQueueV1` or `L1MessageQueueV2` when batches are finalized to confirm these messages have been processed and proven.
    *   `ScrollChain` queries `L1MessageQueueV2` for `getMessageRollingHash` (for proof input) and `getFirstUnfinalizedMessageEnqueueTime` (for enforced mode checks).

*   **`MultipleVersionRollupVerifier` (and specific `IZkEvmVerifierV1`/`IZkEvmVerifierV2` versions):**
    *   `ScrollChain` calls `verifyBundleProof` (or older `verifyAggregateProof` indirectly through `MultipleVersionRollupVerifier`'s interface) on the `verifier` contract.
    *   The `verifier` contract (`MultipleVersionRollupVerifier`) internally selects the correct version of `IZkEvmVerifier` based on the batch version and index, and then calls its `verify` method.

*   **`SystemConfig`:**
    *   `ScrollChain` reads `enforcedBatchParameters` (specifically `maxDelayEnterEnforcedMode` and `maxDelayMessageQueue`) from `SystemConfig` to determine if it should enter enforced batch mode during `commitAndFinalizeBatch`.

*   **Sequencers (External Actors):**
    *   EOAs or smart contracts authorized via `isSequencer`.
    *   Call `commitBatchWithBlobProof()` or `commitBatches()` to submit L2 data to L1.

*   **Provers (External Actors):**
    *   EOAs or smart contracts authorized via `isProver`.
    *   Call `finalizeBundleWithProof()` or `finalizeBundlePostEuclidV2()` to submit ZK validity proofs.

*   **Owner (External Actor, typically a Timelock/Multisig):**
    *   Calls administrative functions like `revertBatch()`, `addSequencer()`, `removeSequencer()`, `addProver()`, `removeProver()`, `setPause()`, `updateMaxNumTxInChunk()`, `disableEnforcedBatchMode()`, and `importGenesisBatch()`.

This detailed breakdown should provide a comprehensive understanding of `ScrollChain.sol`'s role, structure, and interactions within the Scroll protocol.
