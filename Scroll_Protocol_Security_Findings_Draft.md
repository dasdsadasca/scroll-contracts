# Scroll Protocol - Security Findings (Draft)

This document summarizes potential security findings and concerns identified during a review of selected Scroll protocol smart contracts. The review included analysis of individual contracts and their interactions, focusing on architectural patterns, access controls, and data flow.

**Disclaimer:** This is a draft based on a limited review of specific contracts and inferred functionalities. It is not a comprehensive security audit. The soundness of ZK circuits and formal verification of verifier contracts, which are paramount to the overall security of a zkRollup, were not part of this review.

## Overall Systemic Risks:

*   **Vulnerability/Concern:** Centralization of Critical Roles
    *   **Affected Contract(s):** Primarily `ScrollChain`, `L1GatewayRouter`, `L2GatewayRouter`, `L1ScrollMessenger`, `MultipleVersionRollupVerifier`, and other ownable/configurable contracts.
    *   **Description/Potential Exploit Scenario:**
        *   **Owner:** A compromised or malicious Owner key can reconfigure critical contract addresses (e.g., gateways, verifiers, message queues), pause the system, add malicious sequencers/provers, or drain funds from contracts where it has withdrawal privileges.
        *   **Sequencer:** A compromised Sequencer can censor transactions, reorder transactions to its benefit (MEV), or temporarily halt batch submissions. While ZK proofs prevent invalid state transitions, liveness can be affected.
        *   **Prover:** A compromised Prover could theoretically try to submit invalid proofs, but these should be rejected by the Verifier. However, it could withhold proofs, affecting finalization.
    *   **Existing Mitigations (if any):**
        *   Multi-sig arrangements for Owner roles (common practice, assumed).
        *   Time-locks on critical configuration changes (common practice, assumed).
        *   The ZK-proof mechanism itself prevents Sequencers/Provers from creating invalid states.
        *   Enforced batch mode in `ScrollChain` aims to mitigate Sequencer/Prover liveness issues.
        *   Prover Network diversity.
    *   **Assessed Severity:** High (if Owner key is compromised without mitigation like timelocks/multisig), Medium (for Sequencer/Prover liveness).

*   **Vulnerability/Concern:** Reliance on Off-Chain Monitoring and Relaying
    *   **Affected Contract(s):** Entire system, particularly message passing and withdrawal flows.
    *   **Description/Potential Exploit Scenario:** The system relies on off-chain components (Sequencers, Provers, Relayers) to be operational. Failure or malicious behavior of these components can lead to liveness issues (e.g., messages not relayed, withdrawals not processable). Users often rely on third-party relayers.
    *   **Existing Mitigations (if any):**
        *   Protocol design allows users to potentially self-relay messages if needed (though complex).
        *   Decentralization of Sequencer/Prover roles is a long-term goal for most rollups.
    *   **Assessed Severity:** Medium (Liveness risk).

*   **Vulnerability/Concern:** ZK Circuit and Verifier Soundness
    *   **Affected Contract(s):** `ScrollChain`, `MultipleVersionRollupVerifier`, and underlying ZK Verifier contracts.
    *   **Description/Potential Exploit Scenario:** A flaw in the ZK circuit design or the verifier contract implementation could allow a malicious Prover to submit a convincing proof for an invalid state transition, potentially leading to theft of funds or breaking L2 state integrity.
    *   **Existing Mitigations (if any):**
        *   Rigorous mathematical proofs, multiple audits by ZK experts, bug bounties, formal verification (assumed to be part of Scroll's security strategy).
        *   This review did not audit the circuits/verifier logic itself.
    *   **Assessed Severity:** Critical (if a flaw exists).

*   **Vulnerability/Concern:** Upgradeability Risks
    *   **Affected Contract(s):** All core contracts, especially if using proxy patterns (e.g., UUPS, Transparent).
    *   **Description/Potential Exploit Scenario:**
        *   Flaws in upgrade mechanisms (e.g., storage clashes, uninitialized state in new implementations, incorrect proxy admin) could lead to bricked contracts or vulnerabilities.
        *   A malicious or compromised Owner could upgrade to a malicious implementation.
    *   **Existing Mitigations (if any):**
        *   Use of standard, well-audited proxy patterns.
        *   Time-locks and multi-sig for upgrades.
        *   Rigorous testing and audit of new implementations before upgrade.
    *   **Assessed Severity:** High.

## Contract-Specific Findings:

### 1. `L1GatewayRouter.sol` & `L2GatewayRouter.sol`

*   **Vulnerability/Concern:** Malicious Gateway Registration by Owner
    *   **Affected Contract(s):** `L1GatewayRouter`, `L2GatewayRouter`.
    *   **Description/Potential Exploit Scenario:** The Owner can set the `ethGateway` or `defaultERC20Gateway` to a malicious contract. If a user then attempts to deposit/withdraw ETH or a default ERC20 token, their funds could be routed to this malicious contract and stolen. Similarly, registering a malicious gateway for a specific token via `setERC20Gateway` would trap funds for that token.
    *   **Existing Mitigations (if any):**
        *   Owner access controls (should be multi-sig with time-lock).
        *   Event emission upon gateway changes for off-chain monitoring.
    *   **Assessed Severity:** High (if Owner is compromised).

*   **Vulnerability/Concern:** Data Integrity of `_routerData` (Implicit)
    *   **Affected Contract(s):** `L1GatewayRouter`, `L2GatewayRouter`, `L1ScrollMessenger`, `L2ScrollMessenger`, L1/L2 Gateways.
    *   **Description/Potential Exploit Scenario:** While not explicitly detailed in the router code, routers often pass along original sender information to Messengers, which then relay it. If this data (`_routerData` or similar packed struct) is not correctly parsed or if its integrity is not maintained through the chain of calls (Router -> Gateway -> Messenger -> Target on other layer), it could lead to misattribution of sender identity on the destination layer, potentially bypassing authorization checks in user contracts.
    *   **Existing Mitigations (if any):**
        *   Standardized data encoding and decoding across contracts.
        *   The `xDomainMessageSender` mechanism in Messengers aims to provide the L1/L2 initiator's address.
    *   **Assessed Severity:** Medium (if such data passing exists and is flawed).

### 2. `L1ScrollMessenger.sol`

*   **Vulnerability/Concern:** Reentrancy in Target Contracts
    *   **Affected Contract(s):** Contracts called by `L1ScrollMessenger.relayMessageWithProof` (target L1 contracts) and `IMessageDropCallback` implementers called by `dropMessage`.
    *   **Description/Potential Exploit Scenario:** If a target L1 contract called via `relayMessageWithProof` or a callback contract in `dropMessage` makes an external call back into `L1ScrollMessenger` or another contract involved in the message flow before completing its state changes, it could lead to inconsistent states or exploits. For example, a malicious L1 contract could try to re-trigger message relay or fund release.
    *   **Existing Mitigations (if any):**
        *   `L1ScrollMessenger` itself uses `notInExecution` (acting like a reentrancy guard for its main execution logic) and `nonReentrant` modifiers on `relayMessageWithProof` and `dropMessage`.
        *   Target contracts are responsible for their own reentrancy protection.
    *   **Assessed Severity:** Medium (depends on target contract vulnerabilities).

*   **Vulnerability/Concern:** Message Spoofing via Privileged Contracts (Partially Fixed)
    *   **Affected Contract(s):** `L1ScrollMessenger`, potentially any L2 contract.
    *   **Description/Potential Exploit Scenario:** The `EnforcedTxGateway` vulnerability demonstrated that a contract on L1, callable by users, could craft a call to `L1ScrollMessenger.relayMessageWithProof` if it could somehow obtain/forge a valid proof for a message. The critical part was if such a contract could then *send a new message to L2* using `L1ScrollMessenger.sendMessage` where the `xDomainMessageSender` on L2 would appear as `alias(L1ScrollMessenger)`. This could trick L2 contracts into thinking the call originated from the L1 Scroll system itself.
    *   **Existing Mitigations (if any):**
        *   The `EnforcedTxGateway` vulnerability was fixed by ensuring it cannot call `relayMessageWithProof`.
        *   `L1ScrollMessenger` has a `blocklist` for the `_to` address in `relayMessageWithProof`, preventing it from directly calling sensitive contracts like itself or gateway routers.
        *   The `xDomainMessageSender` is set to the L2 `msg.sender` when `L1ScrollMessenger` calls `sendMessage`.
    *   **Assessed Severity:** High (for the original vulnerability class), Low (for `L1ScrollMessenger` itself due to blocklist, but vigilance needed for new privileged L1 contracts).
    *   **Further Question:** Are there other L1 contracts with special privileges that could interact with `L1ScrollMessenger` in unexpected ways that should be on the `blocklist`?

*   **Vulnerability/Concern:** Complexity of L1 Message Replay/Drop Logic
    *   **Affected Contract(s):** `L1ScrollMessenger`, `L1MessageQueueV1`.
    *   **Description/Potential Exploit Scenario:** The logic for `replayMessage`, `dropMessage`, `replayStates`, `prevReplayIndex`, and interaction with `L1MessageQueueV1` is complex.
        *   Potential for gas griefing in `dropMessage`: If `maxReplayTimes` is very high, a user might replay a message many times, increasing gas costs for dropping, although the `dropMessage` itself is `payable` and should be self-funded. The dev comment "list is very long, message may never be dropped" in `L1MessageQueueV1.sol` (related to `replayMessage` in `L1ScrollMessenger`) hints at potential liveness issues for dropping certain messages if they are replayed extensively.
        *   Off-by-one errors or incorrect state updates in `replayStates` or `prevReplayIndex` could lead to messages being incorrectly processed, dropped, or becoming stuck.
    *   **Existing Mitigations (if any):**
        *   Capped `maxReplayTimes`.
        *   Thorough testing of edge cases.
    *   **Assessed Severity:** Medium (due to complexity and potential for liveness/correctness issues).

*   **Vulnerability/Concern:** Fund Handling Correctness
    *   **Affected Contract(s):** `L1ScrollMessenger`.
    *   **Description/Potential Exploit Scenario:** Incorrect logic in fee collection, ETH value forwarding (`msg.value` vs. `_value` parameter in `sendMessage`), or refund processing (especially in `dropMessage` where WETH is unwrapped from `L1MessageQueueV1` and sent via callback) could lead to loss of funds for users or the protocol.
    *   **Existing Mitigations (if any):**
        *   Internal accounting should be precise.
        *   Standard `SafeTransfer` equivalents for ETH/WETH.
    *   **Assessed Severity:** Medium.

### 3. `L2ScrollMessenger.sol`

*   **Vulnerability/Concern:** Reentrancy in Target Contracts
    *   **Affected Contract(s):** Contracts called by `L2ScrollMessenger.relayMessage`.
    *   **Description/Potential Exploit Scenario:** Similar to L1, if an L2 target contract called via `relayMessage` re-enters `L2ScrollMessenger` or other system contracts before its state is updated, it could lead to exploits.
    *   **Existing Mitigations (if any):**
        *   `L2ScrollMessenger` has its own reentrancy guard (`isL1MessageExecuted` check prevents re-processing the same message, and `xDomainMessageSender` is reset).
        *   Target L2 contracts must be reentrancy-safe.
    *   **Assessed Severity:** Medium.

*   **Vulnerability/Concern:** Authorization and Aliasing Integrity
    *   **Affected Contract(s):** `L2ScrollMessenger`.
    *   **Description/Potential Exploit Scenario:** The primary authorization check for `relayMessage` is `require(AddressAliasHelper.undoL1ToL2Alias(_msgSender()) == counterpart, "Caller is not L1ScrollMessenger");`. If `AddressAliasHelper.undoL1ToL2Alias` has a bug or can be manipulated, a malicious L2 contract might be able to spoof calls as if they originated from `L1ScrollMessenger`.
    *   **Existing Mitigations (if any):**
        *   Correctness and immutability of `AddressAliasHelper` logic and the `counterpart` address are critical.
        *   `AddressAliasHelper` is a core, audited component.
    *   **Assessed Severity:** High (if aliasing could be broken), Low (assuming `AddressAliasHelper` is secure).

*   **Vulnerability/Concern:** Fund Handling Correctness
    *   **Affected Contract(s):** `L2ScrollMessenger`.
    *   **Description/Potential Exploit Scenario:** Correct forwarding of `_value` (ETH) to target L2 contracts is essential. Errors could lead to funds being lost or misdirected during L1-to-L2 message execution.
    *   **Existing Mitigations (if any):**
        *   Standard call mechanisms.
    *   **Assessed Severity:** Medium.

### 4. `ScrollChain.sol`

*   **Vulnerability/Concern:** Access Control Risks (Compromised Roles)
    *   **Affected Contract(s):** `ScrollChain`.
    *   **Description/Potential Exploit Scenario:**
        *   Compromised Sequencer: Can censor txs, submit invalid `skippedL1MessageBitmap` (though this would likely fail proof verification or cause issues during finalization), or go offline.
        *   Compromised Prover: Can withhold proofs or try to submit proofs for invalid batches (should be caught by Verifier).
        *   Compromised Owner: Can add malicious Sequencers/Provers, pause the contract, incorrectly set system parameters, or abuse `revertBatch`.
    *   **Existing Mitigations (if any):**
        *   Role separation. ZK Proofs are the ultimate check on state validity.
        *   Owner should be multi-sig with time-lock.
        *   Monitoring of Sequencer/Prover activity.
    *   **Assessed Severity:** Medium (High for Owner compromise).

*   **Vulnerability/Concern:** Batch/Finalization Integrity
    *   **Affected Contract(s):** `ScrollChain`.
    *   **Description/Potential Exploit Scenario:**
        *   **Sequencer Honesty (pre-proof):** `ScrollChain` relies on Sequencers to correctly form batches from available L2 transactions and L1 messages. Malicious Sequencers can reorder or censor.
        *   **Prover Honesty & Verifier Correctness:** The core security relies on Provers submitting valid proofs for state transitions, and the Verifier contract correctly validating these proofs. A flaw here is catastrophic.
        *   **Public Input Integrity:** If the public inputs provided to the Verifier (e.g., parent state root, batch data hashes, message queue hashes) can be manipulated or are inconsistent with `ScrollChain`'s state, the proof verification might pass for an incorrect transition.
        *   **Batch Versioning Complexity:** Bugs in handling different batch versions (e.g., `commitBatchWithBlobProof` vs. `commitBatches`, or `finalizeBundleWithProof` vs. `finalizeBundlePostEuclidV2`) or errors during the transition period (e.g., Euclid fork) could lead to incorrect state commitments or finalizations. For example, miscalculation of `V1_MESSAGES_FINALIZED_OFFSET` could break message finalization logic.
    *   **Existing Mitigations (if any):**
        *   ZK proofs for state transitions.
        *   Careful construction of public inputs within `ScrollChain`.
        *   Rigorous testing and auditing of versioning logic.
    *   **Assessed Severity:** High.

*   **Vulnerability/Concern:** Revert Logic (`revertBatch`)
    *   **Affected Contract(s):** `ScrollChain`, `L1MessageQueueV1`, `L1MessageQueueV2`.
    *   **Description/Potential Exploit Scenario:** The owner-only `revertBatch` function must ensure full state consistency. If a batch is reverted in `ScrollChain`, the corresponding messages popped from `L1MessageQueueV1` or `L1MessageQueueV2` must also be "un-popped" or reverted correctly. Failure to do so could lead to messages being lost or processed incorrectly.
    *   **Existing Mitigations (if any):**
        *   `revertBatch` calls `messageQueue.revertPopCrossDomainMessage` on both L1 message queues.
        *   Careful sequencing of operations.
    *   **Assessed Severity:** Medium (due to critical nature and owner privilege).

*   **Vulnerability/Concern:** Enforced Batch Mode (`commitAndFinalizeBatch`)
    *   **Affected Contract(s):** `ScrollChain`, `SystemConfig`.
    *   **Description/Potential Exploit Scenario:**
        *   **Entry Conditions:** The security of conditions for entering this mode (e.g., `ENFORCED_BATCH_TIMEOUT` from `SystemConfig`) is important. If too short, it could be triggered prematurely.
        *   **Gas Limits in Revert Loop:** The loop `for (uint256 i = miscData.lastFinalizedBatchIndex + 1; i < batchIndexToRevertFrom; ++i)` could theoretically consume a lot of gas if many unfinalized batches need to be cleared before committing the enforced batch. This might make `commitAndFinalizeBatch` unusable if it hits block gas limits.
        *   **Proof Requirement:** Still requires a valid ZK proof, which is a strong mitigation against arbitrary state injection by the enforcer.
    *   **Existing Mitigations (if any):**
        *   Owner control over enforcer role and `SystemConfig` parameters.
        *   The proof requirement.
    *   **Assessed Severity:** Medium.

*   **Vulnerability/Concern:** Gas DoS Potentials
    *   **Affected Contract(s):** `ScrollChain`.
    *   **Description/Potential Exploit Scenario:**
        *   **Loops:** Functions that loop over data provided by users or derived from chain state (e.g., processing chunks in `commitBatchWithBlobProof`, reverting batches in `commitAndFinalizeBatch`) could be targets for gas DoS if the number of iterations can be maliciously inflated.
        *   **Precompile/Verifier Calls:** If inputs to the blob point evaluation precompile or the `MultipleVersionRollupVerifier.verifyBundleProof` call can be crafted to cause excessive gas consumption without failing, it could stall batch commitment or finalization.
    *   **Existing Mitigations (if any):**
        *   Limits like `maxNumTxInChunk`.
        *   Gas limits on individual transactions.
        *   Verifier contracts are typically optimized for gas.
    *   **Assessed Severity:** Low to Medium.

*   **Vulnerability/Concern:** Interaction with Message Queues
    *   **Affected Contract(s):** `ScrollChain`, `L1MessageQueueV1`, `L1MessageQueueV2`.
    *   **Description/Potential Exploit Scenario:** Ensuring perfect synchronization of message states (popped, finalized, skipped) between `ScrollChain` and the L1 Message Queues across various batch versions and operations (commit, finalize, revert) is complex. Mismatches could lead to messages being processed twice, not at all, or funds associated with messages being lost/stuck.
    *   **Existing Mitigations (if any):**
        *   Dedicated functions for updating message queue states (`popCrossDomainMessage`, `finalizePoppedCrossDomainMessage`, `revertPopCrossDomainMessage`).
        *   Inclusion of message queue hashes/states in ZK proofs for newer versions.
    *   **Assessed Severity:** Medium.

### 5. Message Queues (`L1MessageQueueV1/V2`, `L2MessageQueue` - Partially Inferred)

*   **Vulnerability/Concern:** Internal Logic Bugs
    *   **Affected Contract(s):** `L1MessageQueueV1`, `L1MessageQueueV2`, `L2MessageQueue`.
    *   **Description/Potential Exploit Scenario:** (Partially speculative as full Message Queue code not deeply reviewed)
        *   Bugs in nonce generation/management for messages.
        *   Errors in message storage, retrieval, or state updates (e.g., marking as popped, finalized, skipped).
        *   Flaws in Merkle tree generation for `L2MessageQueue` could allow invalid withdrawal proofs.
        *   Flaws in rolling hash generation for `L1MessageQueueV2` could allow L2 Provers to prove against an incorrect L1 message state.
    *   **Existing Mitigations (if any):**
        *   Thorough testing and audits of these critical components.
    *   **Assessed Severity:** Medium to High.

*   **Vulnerability/Concern:** Message Skipping/Censorship by Sequencers
    *   **Affected Contract(s):** `L1MessageQueueV1`, `L1MessageQueueV2`.
    *   **Description/Potential Exploit Scenario:** Sequencers choose which L1->L2 messages to include in a batch. They could theoretically censor messages or ignore the queue. For `L1MessageQueueV1`, they explicitly provide a `skippedL1MessageBitmap`.
    *   **Existing Mitigations (if any):**
        *   Users can use `L1ScrollMessenger.replayMessage` to try resending a message, potentially with a higher fee/gas for L2 execution.
        *   For `L1MessageQueueV1` messages that are finalized as "skipped" on L2, `L1ScrollMessenger.dropMessage` allows reclaiming associated value.
        *   Economic incentives for Sequencers to process messages.
    *   **Assessed Severity:** Low to Medium (Liveness/Censorship risk).

*   **Vulnerability/Concern:** Data Integrity of Hashes
    *   **Affected Contract(s):** `L1MessageQueueV2`, `L2MessageQueue`.
    *   **Description/Potential Exploit Scenario:** The security of systems relying on `L1MessageQueueV2.getMessageRollingHash()` or `L2MessageQueue`'s Merkle root (`withdrawRoot`) depends on the correct and verifiable computation of these hashes. Any way to manipulate the hash computation or provide a false hash to `ScrollChain` could break message integrity.
    *   **Existing Mitigations (if any):**
        *   Hash computations are standardized and deterministic.
        *   The hashes are included in ZK proofs for newer batch versions.
    *   **Assessed Severity:** High (if exploitable, but generally well-protected).

### 6. `EnforcedTxGateway.sol`

*   **Vulnerability/Concern:** Message Spoofing (Fixed)
    *   **Affected Contract(s):** `EnforcedTxGateway`, `L1ScrollMessenger`, L2 contracts.
    *   **Description/Potential Exploit Scenario:** The original vulnerability allowed `EnforcedTxGateway` to call `L1ScrollMessenger.relayMessageWithProof` (by having a valid, but unrelated, L2->L1 message proof relayed by a user) and then, within the same transaction, call `L1ScrollMessenger.sendMessage`. This resulted in the `sendMessage` call to L2 having `xDomainMessageSender` as `alias(L1ScrollMessenger)`, enabling spoofing.
    *   **Existing Mitigations (if any):**
        *   Fixed by preventing `EnforcedTxGateway` from calling `relayMessageWithProof` if `msg.sender == address(this)`.
    *   **Assessed Severity:** Critical (for the original bug), Fixed.

*   **Vulnerability/Concern:** Nonce Griefing in `sendTransaction` (Signature Version)
    *   **Affected Contract(s):** `EnforcedTxGateway`.
    *   **Description/Potential Exploit Scenario:** In `sendTransaction(address _to, uint256 _value, bytes calldata _data, uint256 _nonce, bytes memory _signature, uint256 _gasLimit)`, the nonce `usedNonces[signer][_nonce]` is marked as used *before* the message is sent to `L1ScrollMessenger` and then to `L1MessageQueueV2`. If the subsequent fee calculation or queuing in `L1ScrollMessenger` or `L1MessageQueueV2` fails (e.g., insufficient fee provided by `EnforcedTxGateway`'s current balance, or queue is full/paused), the transaction might revert, but the nonce on `EnforcedTxGateway` remains consumed. This could allow an attacker to grief a user by repeatedly sending transactions with valid signatures but causing them to fail later, consuming the user's nonces for `EnforcedTxGateway`.
    *   **Existing Mitigations (if any):**
        *   Users would need to sign new messages with new nonces.
        *   The contract is designed for specific, potentially restricted use.
    *   **Assessed Severity:** Low to Medium.

*   **Vulnerability/Concern:** Aliasing Logic Reliance
    *   **Affected Contract(s):** `EnforcedTxGateway`.
    *   **Description/Potential Exploit Scenario:** The `sendTransaction` function (non-signature version) uses `AddressAliasHelper.getL1Address(msg.sender)` to derive the L1 sender. If `msg.sender` is not a valid L2 aliased address, or if `AddressAliasHelper` has issues, this could lead to incorrect sender attribution.
    *   **Existing Mitigations (if any):**
        *   `AddressAliasHelper` is a core, audited component. Assumes `msg.sender` will be an L2 contract with a corresponding L1 alias.
    *   **Assessed Severity:** Low (assuming `AddressAliasHelper` is secure).

### 7. Verifier System (`MultipleVersionRollupVerifier` & Underlying Verifiers - Conceptual)

*   **Vulnerability/Concern:** Admin Control Over Verifier Registration
    *   **Affected Contract(s):** `MultipleVersionRollupVerifier`.
    *   **Description/Potential Exploit Scenario:** The Owner/Admin of `MultipleVersionRollupVerifier` can register new verifier contracts for different batch versions. If a compromised Owner registers a malicious or faulty verifier (e.g., one that always returns true), `ScrollChain` could be tricked into accepting proofs for invalid L2 state transitions.
    *   **Existing Mitigations (if any):**
        *   Owner of `MultipleVersionRollupVerifier` should be highly secure (multi-sig, time-lock).
        *   The `verifier` address in `ScrollChain` is immutable, meaning `ScrollChain` always talks to the same `MultipleVersionRollupVerifier` instance. This is a strong plus.
    *   **Assessed Severity:** Critical (if `MultipleVersionRollupVerifier` Owner is compromised).

*   **Vulnerability/Concern:** Dispatch Integrity
    *   **Affected Contract(s):** `MultipleVersionRollupVerifier`.
    *   **Description/Potential Exploit Scenario:** `MultipleVersionRollupVerifier` must correctly map a `batchVersion` to the appropriate underlying verifier contract. An error in this dispatch logic could cause a proof to be sent to the wrong verifier, potentially leading to incorrect validation (e.g., a proof for an old version being validated by a new verifier that expects a different format, or vice-versa).
    *   **Existing Mitigations (if any):**
        *   Simplicity of dispatch logic (e.g., mapping).
        *   Thorough testing.
    *   **Assessed Severity:** Medium.

## Cross-Contract Interaction Vulnerabilities (Summary):

*   **Vulnerability/Concern:** Privileged L1 Contract Interaction with `L1ScrollMessenger`
    *   **Affected Contract(s):** `L1ScrollMessenger`, L1 contracts with relay/send capabilities, L2 contracts.
    *   **Description/Potential Exploit Scenario:** As seen with `EnforcedTxGateway`, L1 contracts that can call `L1ScrollMessenger.relayMessageWithProof` and subsequently `L1ScrollMessenger.sendMessage` in the same transaction (or through a controlled intermediary) pose a risk. If not properly restricted, they could cause messages to be sent to L2 that appear to originate from `alias(L1ScrollMessenger)`, potentially bypassing L2 contract authorization checks that expect calls from the "system."
    *   **Existing Mitigations (if any):**
        *   `L1ScrollMessenger.blocklist` for the `_to` parameter in `relayMessageWithProof`.
        *   Careful design and review of any new L1 contracts that are given permissions to interact with `L1ScrollMessenger`.
    *   **Assessed Severity:** High.

*   **Vulnerability/Concern:** State Consistency Between `ScrollChain` and `L1MessageQueues`
    *   **Affected Contract(s):** `ScrollChain`, `L1MessageQueueV1`, `L1MessageQueueV2`.
    *   **Description/Potential Exploit Scenario:** When batches are committed, finalized, or reverted, both `ScrollChain` and the relevant `L1MessageQueue` must update their states regarding processed/skipped messages. An inconsistency (e.g., `ScrollChain` reverts a batch, but `L1MessageQueue` does not correctly "un-pop" the messages) could lead to messages being lost, processed twice, or message-related funds being stuck. This is particularly complex during version transitions (e.g., Euclid fork).
    *   **Existing Mitigations (if any):**
        *   Dedicated functions in `ScrollChain` to manage message queue state updates atomically with batch state changes.
        *   Inclusion of message queue state hashes in ZK proofs (for `L1MessageQueueV2`).
    *   **Assessed Severity:** Medium.

*   **Vulnerability/Concern:** Trust Dependencies
    *   **Affected Contract(s):** Entire system.
    *   **Description/Potential Exploit Scenario:**
        *   Messengers trust `ScrollChain`'s state regarding finalized batches and withdrawal roots.
        *   `ScrollChain` trusts the `MultipleVersionRollupVerifier` (and by extension, the active ZK verifier) to correctly validate proofs.
        *   `ScrollChain` trusts `L1MessageQueueV1/V2` to correctly manage message states and hashes.
        *   Gateways trust Messengers to correctly format and relay messages.
        *   A failure or compromise in any of these trusted components can have cascading effects.
    *   **Existing Mitigations (if any):**
        *   Modular design.
        *   Security of individual components through audits, access controls.
        *   Cryptographic commitments (hashes, proofs) linking states.
    *   **Assessed Severity:** High (as it's inherent in the architecture, but mitigated by individual component security).
```
