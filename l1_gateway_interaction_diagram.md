```mermaid
graph TD
    subgraph UserLayer [User Interaction]
        User[User]
    end

    subgraph L1RouterAndGateways [L1 Router & Specific Gateways]
        L1GR[L1GatewayRouter]
        L1ETHG[L1ETHGateway]
        L1ERC20G[L1ERC20Gateway (Standard/Custom)]
        L1SM[L1ScrollMessenger]
    end

    %% Deposit Flow
    User -- "1. depositETH(amount, gasLimit) / depositERC20(token, amount, gasLimit)" --> L1GR

    L1GR -- "2a. Routes ETH to: depositETHAndCall(...)" --> L1ETHG
    L1GR -- "2b. Routes ERC20 to: depositERC20AndCall(...)" --> L1ERC20G
    
    L1ERC20G -- "3. If ERC20, calls back: requestERC20(user, token, amount)" --> L1GR
    L1GR -- "4. Transfers token from User to L1ERC20G" --> L1ERC20G
    
    L1ETHG -- "5a. Sends L1->L2 message via: sendMessage(...)" --> L1SM
    L1ERC20G -- "5b. Sends L1->L2 message via: sendMessage(...)" --> L1SM

    %% Withdrawal Flow (Finalization Part on L1)
    L1SM -- "1. Relays L2->L1 message for withdrawal, calls: finalizeWithdrawETH(...)" --> L1ETHG
    L1SM -- "2. Relays L2->L1 message for withdrawal, calls: finalizeWithdrawERC20(...)" --> L1ERC20G
    
    L1ETHG -- "3a. Transfers ETH to User" --> User
    L1ERC20G -- "3b. Transfers ERC20 to User" --> User

    classDef user fill:#FFDAB9,stroke:#8B4513,stroke-width:2px;
    classDef router fill:#ADD8E6,stroke:#00008B,stroke-width:2px;
    classDef gateway fill:#E6E6FA,stroke:#483D8B,stroke-width:2px;
    classDef messenger fill:#D1E8FF,stroke:#367FBD,stroke-width:2px;

    class User user;
    class L1GR router;
    class L1ETHG,L1ERC20G gateway;
    class L1SM messenger;
```
