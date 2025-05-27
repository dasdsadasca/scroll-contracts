```mermaid
graph TD
    subgraph L1
        User_L1[L1 User]
        L1_LidoG[L1LidoGateway]
        L1_SM[L1ScrollMessenger]
        Admin_L1[Admin/RoleHolder L1]
        
        subgraph L1_LidoG_Abstracts [L1LidoGateway Inherits]
            L1_LidoManager["LidoGatewayManager (Abstract)"]
            L1_LidoTokens["LidoBridgeableTokens (Abstract)"]
            L1_BaseERC20G["L1ERC20Gateway (Base)"]
        end
        L1_LidoG -- Inherits --> L1_LidoManager
        L1_LidoG -- Inherits --> L1_LidoTokens
        L1_LidoG -- Inherits --> L1_BaseERC20G
    end

    subgraph L2
        User_L2[L2 User]
        L2_LidoG[L2LidoGateway]
        L2_SM[L2ScrollMessenger]
        L2_WstETH[L2WstETHToken]
        Admin_L2[Admin/RoleHolder L2]

        subgraph L2_LidoG_Abstracts [L2LidoGateway Inherits]
            L2_LidoManager["LidoGatewayManager (Abstract)"]
            L2_LidoTokens["LidoBridgeableTokens (Abstract)"]
            L2_BaseERC20G["L2ERC20Gateway (Base)"]
        end
        L2_LidoG -- Inherits --> L2_LidoManager
        L2_LidoG -- Inherits --> L2_LidoTokens
        L2_LidoG -- Inherits --> L2_BaseERC20G
    end

    %% Deposit Flow (L1 -> L2)
    User_L1 -- "1. depositERC20(wstETH, amount, gasLimit)" --> L1_LidoG
    L1_LidoG -- "2. Sends L1->L2 message (to L2_LidoG)" --> L1_SM
    L1_SM -- "3. Relays message" --> L2_SM
    L2_SM -- "4. finalizeDepositERC20(...)" --> L2_LidoG
    L2_LidoG -- "5. mint(recipient, amount)" --> L2_WstETH

    %% Withdrawal Flow (L2 -> L1)
    User_L2 -- "1. withdrawERC20(L2wstETH, amount, gasLimit)" --> L2_LidoG
    L2_LidoG -- "2. burn(user, amount)" --> L2_WstETH
    L2_LidoG -- "3. Sends L2->L1 message (to L1_LidoG)" --> L2_SM
    L2_SM -- "4. Relays message" --> L1_SM
    L1_SM -- "5. finalizeWithdrawERC20(...)" --> L1_LidoG
    L1_LidoG -- "6. Transfers wstETH to User_L1" --> User_L1

    %% Admin/Role Holder Interactions
    Admin_L1 -- "Manages Roles/Status (e.g., enableDeposits)" --> L1_LidoG
    Admin_L2 -- "Manages Roles/Status (e.g., enableWithdrawals)" --> L2_LidoG

    classDef user fill:#FFDAB9,stroke:#8B4513,stroke-width:2px;
    classDef gateway fill:#ADD8E6,stroke:#00008B,stroke-width:2px;
    classDef messenger fill:#E6E6FA,stroke:#483D8B,stroke-width:2px;
    classDef token fill:#DFFFE2,stroke:#3BBD72,stroke-width:2px;
    classDef admin fill:#FFFACD,stroke:#BDB76B,stroke-width:2px;
    classDef abstract fill:#ECECEC,stroke:#708090,stroke-width:1px,linestyle:dashed;

    class User_L1, User_L2 user;
    class L1_LidoG, L2_LidoG gateway;
    class L1_SM, L2_SM messenger;
    class L2_WstETH token;
    class Admin_L1, Admin_L2 admin;
    class L1_LidoManager, L1_LidoTokens, L1_BaseERC20G, L2_LidoManager, L2_LidoTokens, L2_BaseERC20G abstract;
```
