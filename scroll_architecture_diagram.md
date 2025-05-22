```mermaid
flowchart TD
    subgraph L1 [Ethereum Mainnet - Layer 1]
        direction LR
        L1_User[User]
        L1GR[L1GatewayRouter]
        L1ETHG[L1ETHGateway]
        L1ERC20G[L1ERC20Gateway]
        L1SM[L1ScrollMessenger]
        L1MQ[L1MessageQueue(s)]
        SC[ScrollChain]
        Verifier[MultipleVersionRollupVerifier]
        Prover[Off-Chain Prover]

        L1_User -- "Deposits ETH/Tokens" --> L1GR
        L1GR --- L1ETHG
        L1GR --- L1ERC20G
        L1GR -- "Sends Deposit Message" --> L1SM
        L1ETHG -- "Locks ETH, Signals Messenger" --> L1SM
        L1ERC20G -- "Locks Tokens, Signals Messenger" --> L1SM
        L1SM -- "Enqueues L1->L2 Message" --> L1MQ
        SC -- "Reads L1 Messages for L2" --> L1MQ
        SC -- "Verifies Proof" --> Verifier
        Prover -- "Submits ZK Proof" --> SC
        L1SM -- "Relays Message for Execution" --> SC
        L1SM -- "xDomainCall to L2" --> L2_SM_Relay


        subgraph L1_Withdrawal_Claim [Withdrawal Claim on L1]
            direction TB
            L1GR_Claim[L1GatewayRouter]
            L1ETHG_Claim[L1ETHGateway]
            L1ERC20G_Claim[L1ERC20Gateway]
            L1SM_Claim[L1ScrollMessenger]

            L1_User_Claim[User] -- "Claims Assets" --> L1GR_Claim
            L1GR_Claim --- L1ETHG_Claim
            L1GR_Claim --- L1ERC20G_Claim
            L1SM_Claim -- "Executes Withdrawal Message from L2" --> L1GR_Claim
            SC -- "Allows Message Execution Post-Finalization" --> L1SM_Claim
        end
    end

    subgraph L2 [Scroll Network - Layer 2]
        direction LR
        L2_User[User]
        L2GR[L2GatewayRouter]
        L2ETHG[L2ETHGateway]
        L2ERC20G[L2ERC20Gateway]
        L2SM[L2ScrollMessenger]
        L2MQ[L2MessageQueue]
        Sequencer[Off-Chain Sequencer]

        L2_User -- "Initiates Withdrawal" --> L2GR
        L2GR --- L2ETHG
        L2GR --- L2ERC20G
        L2GR -- "Sends Withdrawal Message" --> L2SM
        L2ETHG -- "Burns/Locks L2 ETH, Signals Messenger" --> L2SM
        L2ERC20G -- "Burns/Locks L2 Tokens, Signals Messenger" --> L2SM
        L2SM -- "Enqueues L2->L1 Message" --> L2MQ
        Sequencer -- "Collects Tx, Reads L1 Messages, Creates L2 Block" --> L2_Execution_Environment[L2 Execution Environment]
        L2_Execution_Environment -- "Includes L2->L1 Messages" --> L2MQ
        Sequencer -- "Submits Batch to L1" --> SC
        L2_SM_Relay[L1SM Relayed Message] -- "Triggers Action on L2 (e.g. Mint Tokens)" --> L2GR
    end

    %% Connections between L1 and L2
    L1MQ -- "L1->L2 Messages (via Sequencer inclusion in L2 Block)" --> Sequencer
    L2MQ -- "L2->L1 Messages (included in Batch sent by Sequencer)" --> Sequencer
    SC -- "Finalizes L2 Batches" --> L2_State_Finalized[L2 State Finalized on L1]

    %% Style
    classDef l1Component fill:#D2E0FB,stroke:#333,stroke-width:2px;
    classDef l2Component fill:#FADCD9,stroke:#333,stroke-width:2px;
    classDef offChain fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef user fill:#FFF3CD,stroke:#333,stroke-width:2px;

    class L1_User,L1GR,L1ETHG,L1ERC20G,L1SM,L1MQ,SC,Verifier,L1GR_Claim,L1ETHG_Claim,L1ERC20G_Claim,L1SM_Claim,L1_User_Claim l1Component;
    class L2_User,L2GR,L2ETHG,L2ERC20G,L2SM,L2MQ,L2_SM_Relay,L2_Execution_Environment l2Component;
    class Sequencer,Prover offChain;
    class L1_User,L2_User,L1_User_Claim user;
```
