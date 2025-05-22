```mermaid
flowchart TD
    subgraph OffChain_Actors [Off-Chain Actors]
        direction TB
        Sequencer["Sequencer (Off-chain)"]
        Prover["Prover (Off-chain)"]
    end

    subgraph Owner_Admin [Owner/Admin]
        direction TB
        Owner["Contract Owner/System"]
    end

    subgraph ScrollChain_Core [ScrollChain.sol]
        direction LR
        SC[ScrollChain]
    end

    subgraph L1_Dependencies [L1 Dependencies & Precompiles]
        direction TB
        L1MQV1[L1MessageQueueV1]
        L1MQV2[L1MessageQueueV2]
        Verifier[MultipleVersionRollupVerifier]
        SysConf[SystemConfig]
        PEP[Point Evaluation Precompile]
    end

    %% Interactions with ScrollChain
    Sequencer -- "commitBatchWithBlobProof()" --> SC
    Sequencer -- "commitBatches()" --> SC
    Prover -- "finalizeBundleWithProof()" --> SC
    Prover -- "finalizeBundlePostEuclidV2()" --> SC
    Owner -- "Admin Functions (addSequencer, setPause, revertBatch, etc.)" --> SC
    Owner -- "commitAndFinalizeBatch() (Enforced Mode)" --> SC

    SC -- "Updates Queue (popCrossDomainMessage)" --> L1MQV1
    SC -- "Finalizes Messages (_finalizePoppedL1Messages)" --> L1MQV1
    SC -- "Updates Queue (popCrossDomainMessage)" --> L1MQV2
    SC -- "Finalizes Messages (_finalizePoppedL1Messages)" --> L1MQV2
    SC -- "verifyBundleProof()" --> Verifier
    SC -- "Reads parameters (e.g., enforcedBatchParameters)" --> SysConf
    SC -- "Verifies Blob Proof" --> PEP

    %% Internal State (Conceptual)
    subgraph ScrollChain_State [ScrollChain Internal State]
        direction TB
        CommittedBatches["CommittedBatches (Batch Hashes, Data Hashes)"]
        FinalizedStateRoots["FinalizedStateRoots"]
        WithdrawRoots["WithdrawRoots"]
        LastIndices["LastCommitted/Finalized Indices"]
    end
    SC -.-> CommittedBatches
    SC -.-> FinalizedStateRoots
    SC -.-> WithdrawRoots
    SC -.-> LastIndices


    %% Styling
    classDef actor fill:#FFF3CD,stroke:#333,stroke-width:2px;
    classDef contract fill:#C9DAF8,stroke:#333,stroke-width:2px;
    classDef dependency fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef state fill:#E8DAEF,stroke:#333,stroke-width:1px,linestyle:dashed;

    class Sequencer, Prover, Owner actor;
    class SC contract;
    class L1MQV1, L1MQV2, Verifier, SysConf, PEP dependency;
    class CommittedBatches, FinalizedStateRoots, WithdrawRoots, LastIndices state;
```
