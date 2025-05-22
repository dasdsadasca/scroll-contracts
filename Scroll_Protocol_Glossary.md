# Scroll Protocol: Glossary of Common Terms

| Term                          | Definition                                                                                                                                                              |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **L1**                        | Layer 1, the base blockchain (e.g., Ethereum) where the main Scroll contracts like `ScrollChain` are deployed, and where L2 state is ultimately secured.                 |
| **L2**                        | Layer 2, the Scroll network where transactions are executed at higher throughput and lower cost before being batched and proven to L1.                                    |
| **Rollup**                    | A Layer 2 scaling solution that processes transactions off-chain (on L2) and then "rolls up" or bundles them, posting summarized data and proofs to L1 for security.       |
| **zkRollup / zkEVM**          | A type of rollup that uses Zero-Knowledge proofs (ZK proofs) to prove the validity of L2 state transitions to L1. A zkEVM specifically aims for EVM compatibility on L2. |
| **Gateway**                   | A smart contract (or set of contracts) responsible for facilitating the transfer of assets (ETH, ERC20s) between L1 and L2. Examples include `L1GatewayRouter`, `L1ETHGateway`, `L2StandardERC20Gateway`. |
| **Messenger**                 | A smart contract that enables cross-domain communication between L1 and L2, relaying messages and sometimes value. Examples: `L1ScrollMessenger`, `L2ScrollMessenger`.      |
| **Message Queue**             | A smart contract that stores and orders cross-domain messages. `L1MessageQueueV1/V2` queues L1->L2 messages; `L2MessageQueue` queues L2->L1 message hashes.            |
| **ScrollChain**               | The core L1 smart contract for Scroll. It receives L2 batch commitments, verifies ZK proofs, finalizes L2 state, and manages interactions with L1 message queues.        |
| **Batch**                     | A collection of L2 transactions (and sometimes L1->L2 messages) bundled together, for which a commitment is submitted to `ScrollChain` on L1.                        |
| **Chunk**                     | A segment or component of a batch, particularly relevant in older batch versions of Scroll. Multiple chunks would form a complete batch.                                 |
| **Sequencer**                 | An off-chain entity responsible for collecting L2 transactions, ordering them, creating batches, and submitting these batch commitments to `ScrollChain` on L1.             |
| **Prover**                    | An off-chain entity responsible for generating ZK proofs for the validity of L2 state transitions within batches. These proofs are submitted to `ScrollChain`.            |
| **Verifier**                  | An L1 smart contract (e.g., `MultipleVersionRollupVerifier` and its underlying specific verifiers) that validates ZK proofs submitted by Provers.                          |
| **ZK Proof**                  | Zero-Knowledge Proof. A cryptographic proof that allows one party (the Prover) to prove to another (the Verifier) that a statement is true, without revealing any information beyond the validity of the statement itself. Used in Scroll to prove L2 state transitions. |
| **State Root**                | A cryptographic commitment (often a Merkle root) representing the overall state of the L2 chain at a specific point in time.                                             |
| **Withdraw Root**             | A Merkle root representing all L2-to-L1 messages (typically withdrawals) included in a specific L2 batch. This root is stored on L1 and used to verify individual withdrawal claims. |
| **Cross-Domain Message**      | A message sent from one layer (e.g., L1) to another (e.g., L2), or vice-versa, facilitated by Messengers and Message Queues.                                          |
| **Enforced Transaction**      | A transaction sent from L1 to L2 through a specialized gateway like `EnforcedTxGateway`, typically used for specific operational purposes or by whitelisted actors.      |
| **Aliasing (Address Aliasing)** | A mechanism (e.g., via `AddressAliasHelper`) to represent an L1 address on L2, or vice-versa. For example, `L1ScrollMessenger` has an aliased address on L2 that is used to verify messages relayed from L1. |
| **`xDomainMessageSender`**    | A function/variable in Messenger contracts that returns the original sender address of a cross-domain message on the source chain, allowing contracts on the destination chain to identify the initiator. |
| **Finalization**              | The process by which L2 batches (and their contained transactions/messages) are confirmed as valid and canonical by the `ScrollChain` contract on L1, typically after successful ZK proof verification. |
| **Blob / Blob Hash (EIP-4844)** | Refers to EIP-4844 data blobs used for cheaper data availability on L1. `ScrollChain` uses blob versioned hashes (`blobVersionedHash`) as commitments to L2 batch data stored in these blobs. |
| **Owner**                     | An address with administrative privileges over a smart contract, capable of performing actions like upgrading the contract, pausing functionality, or setting critical parameters. |
| **Relayer**                   | An off-chain entity that monitors for events or messages on one chain and submits corresponding transactions to another. For example, relaying L2->L1 messages or executing L1->L2 messages on L2. |
```
