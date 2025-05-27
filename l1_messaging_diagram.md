```mermaid
graph TD
    subgraph ExternalActors [External Actors & L1 Contracts]
        User[User/L1 Gateway]
        ETG[EnforcedTxGateway]
        SC[ScrollChain]
        FV[FeeVault]
        L2CM[L2ScrollMessenger (Counterpart)]
        OriginalSender[Original L1 Sender (IMessageDropCallback)]
        GasOracleV1[IL2GasPriceOracle (for MQV1)]
        SysCfg[SystemConfig (for MQV2)]
    end

    subgraph L1MessagingSystem [L1 Messaging System]
        L1SM[L1ScrollMessenger]
        MQV1[L1MessageQueueV1]
        MQV2[L1MessageQueueV2]
    end

    %% L1ScrollMessenger Interactions
    User -- "sendMessage(to, value, msg, gasLimit)" --> L1SM
    L1SM -- "appendCrossDomainMessage(target, gasLimit, xDomainData)" --> MQV2
    L1SM -- "estimateCrossDomainMessageFee(gasLimit)" --> MQV2
    L1SM -- "nextCrossDomainMessageIndex()" --> MQV2
    L1SM -- Fee Payment --> FV

    User -- "relayMessageWithProof(from, to, value, nonce, msg, proof)" --> L1SM
    L1SM -- "isBatchFinalized(proof.batchIndex)" --> SC
    L1SM -- "withdrawRoots(proof.batchIndex)" --> SC
    L1SM -- Relays L2->L1 Message --> User

    User -- "replayMessage(...newGasLimit)" --> L1SM
    L1SM -- "appendCrossDomainMessage(counterpart, newGasLimit, xDomainData)" --> MQV2
    L1SM -- Fee Payment for Replay --> FV

    User -- "dropMessage(...)" --> L1SM
    L1SM -- "dropCrossDomainMessage(index)" --> MQV1
    L1SM -- "onDropMessage(msg) callback" --> OriginalSender

    %% L1MessageQueueV1 Interactions
    L1SM -- Historically "appendCrossDomainMessage()" --> MQV1
    ETG -- "appendEnforcedTransaction(...)" --> MQV1
    SC -- "popCrossDomainMessage(startIndex, count, skippedBitmap)" --> MQV1
    SC -- "resetPoppedCrossDomainMessage(startIndex)" --> MQV1
    SC -- "finalizePoppedCrossDomainMessage(index)" --> MQV1
    MQV1 -- "estimateCrossDomainMessageFee(gasLimit)" --> GasOracleV1

    %% L1MessageQueueV2 Interactions
    ETG -- "appendEnforcedTransaction(...)" --> MQV2
    SC -- "finalizePoppedCrossDomainMessage(index)" --> MQV2
    SC -- "getMessageRollingHash(index)" --> MQV2
    SC -- "getFirstUnfinalizedMessageEnqueueTime()" --> MQV2
    MQV2 -- "messageQueueParameters()" --> SysCfg
    MQV2 -- Reads L1 basefee --> L1Node[L1 Node (block.basefee)]


    %% Data flow conceptual links
    L1SM -. L1->L2 Message Data .-> MQV2
    MQV2 -. Message Hashes & Rolling Hashes .-> SC
    MQV1 -. Message Hashes & Skipped Info .-> SC
    SC -. L2->L1 Withdraw Roots .-> L1SM
    L2CM -. L2->L1 Message (via L2 state) .-> L1SM


    classDef external fill:#FFDAB9,stroke:#8B4513,stroke-width:2px;
    classDef messenger fill:#ADD8E6,stroke:#00008B,stroke-width:2px;
    classDef queue fill:#E6E6FA,stroke:#483D8B,stroke-width:2px;
    classDef contract fill:#D1E8FF,stroke:#367FBD,stroke-width:2px;

    class User,ETG,FV,L2CM,OriginalSender external;
    class SC,GasOracleV1,SysCfg,L1Node contract;
    class L1SM messenger;
    class MQV1,MQV2 queue;
```
