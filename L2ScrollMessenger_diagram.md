```mermaid
flowchart TD
    subgraph User_Interactions_L2 [User/System Interactions on L2]
        direction TB
        User_Gateway_L2[User / L2 Gateway] -- "sendMessage()" --> L2SM[L2ScrollMessenger]
        L1SM_Aliased[L1ScrollMessenger (Aliased on L2 via Sequencer)] -- "relayMessage()" --> L2SM
    end

    subgraph L2ScrollMessenger_Core [L2ScrollMessenger]
        direction LR
        L2SM
    end

    subgraph L2_Dependencies [L2 Dependencies]
        direction TB
        L2MQ[L2MessageQueue]
        TargetL2Contract[Target L2 Contract]
        AAH[AddressAliasHelper]
    end

    subgraph L1_Conceptual_Link [L1 (Conceptual)]
        direction TB
        L1SM_Counterpart[L1ScrollMessenger (Counterpart on L1)]
    end

    %% L2ScrollMessenger interactions
    L2SM -- "sends msg hash via appendMessage()" --> L2MQ
    L2SM -- "uses for caller verification" --> AAH
    L2SM -- "executes call" --> TargetL2Contract
    L2SM -- "conceptually sends message to" -.-> L1SM_Counterpart

    %% Data flow / conceptual links
    L2MQ -- "Message hashes picked up by L1 Relayer (via ScrollChain)" --> L1SM_Counterpart


    %% Styling
    classDef user fill:#FFF3CD,stroke:#333,stroke-width:2px;
    classDef messenger fill:#C9DAF8,stroke:#333,stroke-width:2px;
    classDef l2infra fill:#FADCD9,stroke:#333,stroke-width:2px;
    classDef l1infra fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef contract fill:#E8DAEF,stroke:#333,stroke-width:2px;
    classDef helper fill:#E2E2E2,stroke:#333,stroke-width:1px,linestyle:dashed;


    class User_Gateway_L2, L1SM_Aliased user;
    class L2SM messenger;
    class L2MQ, TargetL2Contract l2infra;
    class L1SM_Counterpart l1infra;
    class AAH helper;
```
