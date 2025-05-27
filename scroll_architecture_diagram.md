```mermaid
graph TD
    subgraph Layer 1 (Ethereum)
        L1_User[User on L1]
        L1_ScrollChain[IScrollChain]
        L1_L1ScrollMessenger[IL1ScrollMessenger]
        L1_L1MessageQueue[IL1MessageQueue V1/V2]
        L1_GatewayRouter[IL1GatewayRouter]
        L1_ETHGateway[L1ETHGateway]
        L1_ERC20Gateway[L1ERC20Gateway (Standard/Custom)]
        L1_BatchBridgeGateway[L1BatchBridgeGateway]
        L1_LidoGateway[L1LidoGateway]
        L1_RollupVerifier[MultipleVersionRollupVerifier / ZkEvmVerifier]

        L1_User -- Deposits/Withdraws ETH --> L1_ETHGateway
        L1_User -- Deposits/Withdraws ERC20 --> L1_ERC20Gateway
        L1_User -- Deposits ERC20 (Batch) --> L1_BatchBridgeGateway
        L1_User -- Deposits/Withdraws stETH --> L1_LidoGateway

        L1_ETHGateway -- Routes via --> L1_GatewayRouter
        L1_ERC20Gateway -- Routes via --> L1_GatewayRouter
        L1_BatchBridgeGateway -- Routes via --> L1_GatewayRouter
        L1_LidoGateway -- Routes via --> L1_GatewayRouter
        
        L1_GatewayRouter -- Interacts with --> L1_L1ScrollMessenger

        L1_L1ScrollMessenger -- Sends L1->L2 Msg --> L1_L1MessageQueue
        L1_L1ScrollMessenger -- Relays L2->L1 Msg (with proof) --> L1_User/L1_Contract[Target L1 Contract]
        L1_L1MessageQueue -- Consumed by --> L1_ScrollChain

        L1_ScrollChain -- Verifies Proofs via --> L1_RollupVerifier
        L1_ScrollChain -- Manages --> L1_L1MessageQueue
        L1_ScrollChain -- Stores Finalized L2 Batch Info & WithdrawRoots --> L1_L1ScrollMessenger

        Prover[Off-chain Prover] -- Submits Proofs --> L1_ScrollChain
        Sequencer_L1[Off-chain Sequencer] -- Commits Batches --> L1_ScrollChain
    end

    subgraph Layer 2 (Scroll Network)
        L2_User[User on L2]
        L2_L2ScrollMessenger[IL2ScrollMessenger]
        L2_L2MessageQueue[L2MessageQueue (Predeploy)]
        L2_GatewayRouter[IL2GatewayRouter]
        L2_ETHGateway[L2ETHGateway]
        L2_ERC20Gateway[L2ERC20Gateway (Standard/Custom)]
        L2_BatchBridgeGateway[L2BatchBridgeGateway]
        L2_LidoGateway[L2LidoGateway]
        L2_L1GasPriceOracle[L1GasPriceOracle (Predeploy)]
        L2_OtherPredeploys[Other Predeploys (L1BlockContainer, etc.)]

        L2_User -- Interacts with DApps --> L2_SmartContracts[L2 Smart Contracts]
        L2_SmartContracts -- Can initiate L2->L1 Msg --> L2_L2ScrollMessenger
        L2_User -- Deposits/Withdraws (via DApps) --> L2_ETHGateway
        L2_User -- Deposits/Withdraws (via DApps) --> L2_ERC20Gateway

        L2_ETHGateway -- Routes via --> L2_GatewayRouter
        L2_ERC20Gateway -- Routes via --> L2_GatewayRouter
        L2_BatchBridgeGateway -- Routes via --> L2_GatewayRouter
        L2_LidoGateway -- Routes via --> L2_GatewayRouter

        L2_GatewayRouter -- Interacts with --> L2_L2ScrollMessenger
        
        L2_L2ScrollMessenger -- Sends L2->L1 Msg --> L2_L2MessageQueue
        L2_L2ScrollMessenger -- Relays L1->L2 Msg --> L2_SmartContracts/L2_User

        L2_L2MessageQueue -- Generates WithdrawRoot --> Sequencer_L2[L2 Sequencer Node]
        Sequencer_L2 -- Includes WithdrawRoot in Batch --> L1_ScrollChain

        L2_SmartContracts -- Reads L1 Gas Info --> L2_L1GasPriceOracle
    end

    %% Communication Flow Arrows
    L1_L1ScrollMessenger == L1->L2 Msg ==> L2_L2ScrollMessenger
    L2_L2ScrollMessenger == L2->L1 Msg ==> L1_L1ScrollMessenger

    %% Data/Proof Flow
    Sequencer_L1 -- Transaction Data (Batches) --> L1_ScrollChain
    Prover -- Validity Proofs --> L1_ScrollChain

    %% Gateway Counterparts
    L1_ETHGateway <-Bridging-> L2_ETHGateway
    L1_ERC20Gateway <-Bridging-> L2_ERC20Gateway
    L1_BatchBridgeGateway <-Bridging-> L2_BatchBridgeGateway
    L1_LidoGateway <-Bridging-> L2_LidoGateway

    classDef l1Contracts fill:#D1E8FF,stroke:#367FBD,stroke-width:2px;
    classDef l2Contracts fill:#DFFFE2,stroke:#3BBD72,stroke-width:2px;
    classDef offChain fill:#FFF2CC,stroke:#D6B656,stroke-width:2px;
    classDef user fill:#FFE0E0,stroke:#D96666,stroke-width:2px;

    class L1_User,L2_User user;
    class L1_ScrollChain,L1_L1ScrollMessenger,L1_L1MessageQueue,L1_GatewayRouter,L1_ETHGateway,L1_ERC20Gateway,L1_BatchBridgeGateway,L1_LidoGateway,L1_RollupVerifier,L1_Contract l1Contracts;
    class L2_L2ScrollMessenger,L2_L2MessageQueue,L2_GatewayRouter,L2_ETHGateway,L2_ERC20Gateway,L2_BatchBridgeGateway,L2_LidoGateway,L2_L1GasPriceOracle,L2_OtherPredeploys,L2_SmartContracts l2Contracts;
    class Prover,Sequencer_L1,Sequencer_L2 offChain;
```
