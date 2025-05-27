```mermaid
graph TD
    subgraph L1
        User_L1[L1 User]
        L1_BBG[L1BatchBridgeGateway]
        L1_Keeper[L1 Keeper]
        L1_SM[L1ScrollMessenger]
        L1_Std_GW[Standard L1 ERC20/ETH Gateway]
        FeeVault_L1[FeeVault]
        BatchCodec_L1[BatchBridgeCodec Lib]

        User_L1 -- "depositETH() / depositERC20()" --> L1_BBG
        L1_BBG -- "Uses" --> BatchCodec_L1
        L1_BBG -- "Sends fees" --> FeeVault_L1
        L1_Keeper -- "executeBatchDeposit(token)" --> L1_BBG
        L1_BBG -- "1. Asset Bridge Msg (to L2_BBG via Std L2 GW)" --> L1_Std_GW
        L1_Std_GW -- "via L1ScrollMessenger" --> L1_SM
        L1_BBG -- "2. Finalize Batch Msg (to L2_BBG)" --> L1_SM
    end

    subgraph L2
        L2_BBG[L2BatchBridgeGateway]
        L2_Keeper[L2 Keeper]
        L2_SM[L2ScrollMessenger]
        L2_Recipients[L2 Recipients]
        BatchCodec_L2[BatchBridgeCodec Lib]
        L2_Std_GW[Standard L2 ERC20/ETH Gateway]


        L2_BBG -- "Uses" --> BatchCodec_L2
        L2_Keeper -- "distribute(l2Token, batchIndex, nodes)" --> L2_BBG
        L2_BBG -- "Transfers tokens/ETH" --> L2_Recipients
    end
    
    %% L1 to L2 Flow
    L1_SM -- "Relays Asset Bridge Msg" --> L2_SM
    L2_SM -- "Delivers to Std L2 Gateway" --> L2_Std_GW
    L2_Std_GW -- "Transfers assets to" --> L2_BBG

    L1_SM -- "Relays Finalize Batch Msg" --> L2_SM
    L2_SM -- "finalizeBatchDeposit(l1Token, l2Token, batchIndex, hash)" --> L2_BBG


    classDef user fill:#FFDAB9,stroke:#8B4513,stroke-width:2px;
    classDef gateway fill:#ADD8E6,stroke:#00008B,stroke-width:2px;
    classDef messenger fill:#E6E6FA,stroke:#483D8B,stroke-width:2px;
    classDef keeper fill:#D2B48C,stroke:#8B4513,stroke-width:2px;
    classDef lib fill:#FAFAD2,stroke:#BDB76B,stroke-width:1px;
    classDef recipient fill:#90EE90,stroke:#2E8B57,stroke-width:2px;

    class User_L1 user;
    class L1_Keeper, L2_Keeper keeper;
    class L1_BBG, L2_BBG, L1_Std_GW, L2_Std_GW, FeeVault_L1 gateway;
    class L1_SM, L2_SM messenger;
    class BatchCodec_L1, BatchCodec_L2 lib;
    class L2_Recipients recipient;
```
