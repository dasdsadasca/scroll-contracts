```mermaid
graph TD
    subgraph External Actors
        SequencerActor[Sequencer]
        ProverActor[Prover]
        OwnerActor[Owner/Admin]
        PermissionlessActor[Any Actor (Enforced Mode)]
    end

    subgraph ScrollChain Contract
        SC[ScrollChain]

        subgraph State Variables
            SV_committedBatches[committedBatches mapping]
            SV_finalizedStateRoots[finalizedStateRoots mapping]
            SV_withdrawRoots[withdrawRoots mapping]
            SV_miscData[miscData (lastCommitted/FinalizedIndex, flags)]
            SV_isSequencer[isSequencer mapping]
            SV_isProver[isProver mapping]
            SV_maxNumTxInChunk[maxNumTxInChunk]
            SV_initialEuclidBatchIndex[initialEuclidBatchIndex]
        end

        subgraph Key Functions
            FN_importGenesisBatch[importGenesisBatch()]
            FN_commitBatchWithBlobProof[commitBatchWithBlobProof()]
            FN_commitBatches[commitBatches()]
            FN_finalizeBundleWithProof[finalizeBundleWithProof()]
            FN_finalizeBundlePostEuclidV2[finalizeBundlePostEuclidV2()]
            FN_revertBatch[revertBatch()]
            FN_commitAndFinalizeBatch[commitAndFinalizeBatch()]
            FN_addRemoveSequencer[add/removeSequencer()]
            FN_addRemoveProver[add/removeProver()]
            FN_setPause[setPause()]
            FN_disableEnforcedMode[disableEnforcedBatchMode()]
        end

        subgraph Key Events
            EV_CommitBatch[CommitBatch Event]
            EV_FinalizeBatch[FinalizeBatch Event]
            EV_RevertBatch[RevertBatch Event]
            EV_UpdateSequencer[UpdateSequencer Event]
            EV_UpdateProver[UpdateProver Event]
            EV_UpdateEnforcedMode[UpdateEnforcedBatchMode Event]
        end

        SC -- Stores/Updates --> SV_committedBatches
        SC -- Stores/Updates --> SV_finalizedStateRoots
        SC -- Stores/Updates --> SV_withdrawRoots
        SC -- Stores/Updates --> SV_miscData
        SC -- Manages --> SV_isSequencer
        SC -- Manages --> SV_isProver
        SC -- Manages --> SV_maxNumTxInChunk
        SC -- Manages --> SV_initialEuclidBatchIndex

        FN_commitBatchWithBlobProof -- Emits --> EV_CommitBatch
        FN_commitBatches -- Emits --> EV_CommitBatch
        FN_finalizeBundleWithProof -- Emits --> EV_FinalizeBatch
        FN_finalizeBundlePostEuclidV2 -- Emits --> EV_FinalizeBatch
        FN_revertBatch -- Emits --> EV_RevertBatch
        FN_addRemoveSequencer -- Emits --> EV_UpdateSequencer
        FN_addRemoveProver -- Emits --> EV_UpdateProver
        FN_commitAndFinalizeBatch -- May emit --> EV_UpdateEnforcedMode
        FN_commitAndFinalizeBatch -- Emits --> EV_CommitBatch
        FN_commitAndFinalizeBatch -- Emits --> EV_FinalizeBatch
        FN_disableEnforcedMode -- Emits --> EV_UpdateEnforcedMode
        FN_importGenesisBatch -- Emits --> EV_CommitBatch
        FN_importGenesisBatch -- Emits --> EV_FinalizeBatch

    end

    subgraph Dependent Contracts
        MQ1[L1MessageQueueV1]
        MQ2[L1MessageQueueV2]
        Verifier[MultipleVersionRollupVerifier]
        Config[SystemConfig]
        PointEval[PointEvaluationPrecompile]
    end

    %% Actor to ScrollChain Interactions
    SequencerActor -- Calls --> FN_commitBatchWithBlobProof
    SequencerActor -- Calls --> FN_commitBatches
    ProverActor -- Calls --> FN_finalizeBundleWithProof
    ProverActor -- Calls --> FN_finalizeBundlePostEuclidV2
    OwnerActor -- Calls --> FN_importGenesisBatch
    OwnerActor -- Calls --> FN_revertBatch
    OwnerActor -- Calls --> FN_addRemoveSequencer
    OwnerActor -- Calls --> FN_addRemoveProver
    OwnerActor -- Calls --> FN_setPause
    OwnerActor -- Calls --> FN_disableEnforcedMode
    PermissionlessActor -- Calls (if enforced mode) --> FN_commitAndFinalizeBatch

    %% ScrollChain to Dependent Contract Interactions
    SC -- Calls popCrossDomainMessage --> MQ1
    SC -- Calls finalizePoppedCrossDomainMessage --> MQ1
    SC -- Calls getCrossDomainMessage --> MQ1
    
    SC -- Calls finalizePoppedCrossDomainMessage --> MQ2
    SC -- Calls getMessageRollingHash --> MQ2
    SC -- Calls getFirstUnfinalizedMessageEnqueueTime --> MQ2

    SC -- Calls verifyBundleProof --> Verifier

    SC -- Reads enforcedBatchParameters --> Config
    
    SC -- Calls (via assembly) blobhash --> PointEval
    SC -- Calls (via staticcall) for blob proof --> PointEval


    %% Data Flow indication (conceptual)
    FN_commitBatchWithBlobProof -- Batch Data (Chunks, Bitmap, BlobProof) --> SC
    FN_commitBatches -- Batch Data (Blobs implicitly) & Hashes --> SC
    FN_finalizeBundleWithProof -- ZK Proof & Roots --> SC
    FN_finalizeBundlePostEuclidV2 -- ZK Proof & Roots --> SC
    FN_commitAndFinalizeBatch -- Batch Data & ZK Proof --> SC
    
    SC -- Updates BatchHashes --> SV_committedBatches
    SC -- Updates StateRoots --> SV_finalizedStateRoots
    SC -- Updates WithdrawRoots --> SV_withdrawRoots

    classDef externalActor fill:#FFDAB9,stroke:#8B4513,stroke-width:2px;
    classDef scrollChain fill:#ADD8E6,stroke:#00008B,stroke-width:2px;
    classDef dependentContract fill:#E6E6FA,stroke:#483D8B,stroke-width:2px;
    classDef stateVar fill:#FFFACD,stroke:#BDB76B,stroke-width:1px;
    classDef function fill:#F0FFF0,stroke:#2E8B57,stroke-width:1px;
    classDef event fill:#FFF0F5,stroke:#C71585,stroke-width:1px;

    class SequencerActor,ProverActor,OwnerActor,PermissionlessActor externalActor;
    class SC scrollChain;
    class MQ1,MQ2,Verifier,Config,PointEval dependentContract;
    class SV_committedBatches,SV_finalizedStateRoots,SV_withdrawRoots,SV_miscData,SV_isSequencer,SV_isProver,SV_maxNumTxInChunk,SV_initialEuclidBatchIndex stateVar;
    class FN_importGenesisBatch,FN_commitBatchWithBlobProof,FN_commitBatches,FN_finalizeBundleWithProof,FN_finalizeBundlePostEuclidV2,FN_revertBatch,FN_commitAndFinalizeBatch,FN_addRemoveSequencer,FN_addRemoveProver,FN_setPause,FN_disableEnforcedMode function;
    class EV_CommitBatch,EV_FinalizeBatch,EV_RevertBatch,EV_UpdateSequencer,EV_UpdateProver,EV_UpdateEnforcedMode event;
```
