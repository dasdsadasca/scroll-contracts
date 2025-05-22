```mermaid
flowchart TD
    subgraph User_Interactions [User/System Interactions on L1]
        direction TB
        User_Gateway_L1[User / L1 Gateway] -- "sendMessage()" --> L1SM[L1ScrollMessenger]
        Relayer_L1[Relayer (L1)] -- "relayMessageWithProof()" --> L1SM
        User_L1_Retry[User (L1)] -- "replayMessage()" --> L1SM
        User_L1_Drop[User (L1)] -- "dropMessage()" --> L1SM
    end

    subgraph L1ScrollMessenger_Core [L1ScrollMessenger]
        direction LR
        L1SM
    end

    subgraph L1_Dependencies [L1 Dependencies]
        direction TB
        L1MQV1[L1MessageQueueV1]
        L1MQV2[L1MessageQueueV2]
        SC[ScrollChain]
        FeeVault[FeeVault]
        TargetL1Contract[Target L1 Contract]
        DropCallback[IMessageDropCallback Implementer]
        WTV[WithdrawTrieVerifier]
    end

    subgraph L2_Conceptual_Link [L2 (Conceptual)]
        direction TB
        L2SM_Counterpart[L2ScrollMessenger (Counterpart)]
    end

    %% L1ScrollMessenger interactions
    L1SM -- "sends msg via appendCrossDomainMessage()" --> L1MQV2
    L1SM -- "replays msg via appendCrossDomainMessage()" --> L1MQV2
    L1SM -- "checks isMessageSkipped, isMessageFinalized" --> L1MQV1
    L1SM -- "transfers WETH from" --> L1MQV1
    L1SM -- "calls onDropMessage()" --> DropCallback
    L1SM -- "checks isBatchFinalized, withdrawRoots()" --> SC
    L1SM -- "verifyMerkleProof()" --> WTV
    L1SM -- "deposits fees" --> FeeVault
    L1SM -- "executes call" --> TargetL1Contract
    L1SM -- "conceptually sends message to" -.-> L2SM_Counterpart

    %% Data flow / conceptual links
    L1MQV2 -- "Messages picked up by L2 Sequencer" --> L2SM_Counterpart
    L2SM_Counterpart -- "Sends message (via L2MQ, Sequencer, ScrollChain)" -.-> Relayer_L1


    %% Styling
    classDef user fill:#FFF3CD,stroke:#333,stroke-width:2px;
    classDef messenger fill:#C9DAF8,stroke:#333,stroke-width:2px;
    classDef l1infra fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef l2infra fill:#FADCD9,stroke:#333,stroke-width:2px;
    classDef contract fill:#E8DAEF,stroke:#333,stroke-width:2px;

    class User_Gateway_L1, Relayer_L1, User_L1_Retry, User_L1_Drop user;
    class L1SM messenger;
    class L1MQV1, L1MQV2, SC, FeeVault, WTV l1infra;
    class L2SM_Counterpart l2infra;
    class TargetL1Contract, DropCallback contract;
```
