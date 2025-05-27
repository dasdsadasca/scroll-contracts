```mermaid
graph TD
    subgraph UserLayerL2 [User/DApp Interaction on L2]
        UserL2[L2 User/DApp]
    end

    subgraph L2GatewaysAndMessenger [L2 Gateways & Messenger]
        L2ETHG[L2ETHGateway]
        L2ERC20G[L2ERC20Gateway (Standard/Custom)]
        L2SM[L2ScrollMessenger]
        L2GR[L2GatewayRouter]
    end

    %% Withdrawal Flow (Initiated on L2)
    UserL2 -- "1. withdrawETH(amount, gasLimit) / withdrawERC20(token, amount, gasLimit) via L2GR or directly" --> L2GR
    L2GR -- "2a. Routes ETH to: withdrawETHAndCall(...)" --> L2ETHG
    L2GR -- "2b. Routes ERC20 to: withdrawERC20AndCall(...)" --> L2ERC20G
    
    L2ETHG -- "3a. Sends L2->L1 message via: sendMessage(...)" --> L2SM
    L2ERC20G -- "3b. Sends L2->L1 message via: sendMessage(...)" --> L2SM

    %% Deposit Flow (Finalization Part on L2)
    L2SM -- "1. Relays L1->L2 message for deposit, calls: finalizeDepositETH(...)" --> L2ETHG
    L2SM -- "2. Relays L1->L2 message for deposit, calls: finalizeDepositERC20(...)" --> L2ERC20G
    
    L2ETHG -- "3a. Transfers ETH to L2 User/Recipient" --> UserL2
    L2ERC20G -- "3b. Mints/Transfers ERC20 to L2 User/Recipient" --> UserL2

    classDef user fill:#FFE0B2,stroke:#D95B00,stroke-width:2px;
    classDef gateway fill:#DFFFE2,stroke:#3BBD72,stroke-width:2px;
    classDef messenger fill:#E0F2FE,stroke:#0288D1,stroke-width:2px;
    classDef router fill:#FFF9C4,stroke:#FBC02D,stroke-width:2px;

    class UserL2 user;
    class L2ETHG,L2ERC20G gateway;
    class L2SM messenger;
    class L2GR router;
```
