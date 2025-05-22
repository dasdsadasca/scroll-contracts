```mermaid
flowchart TD
    User[User] --> L1GR[L1GatewayRouter]

    subgraph L1GatewayRouter_Interaction
        direction LR
        L1GR -- "depositETH()" calls --> L1ETHG[L1ETHGateway]
        L1GR -- "depositERC20() / depositERC20AndCall()" --> LogicGetGateway{getERC20Gateway}
        LogicGetGateway -- "token specific" --> L1CustomERC20G[L1CustomERC20Gateway]
        LogicGetGateway -- "default" --> L1StdERC20G[L1StandardERC20Gateway (default)]
        L1GR -- "getL2ERC20Address()" calls --> L1StdERC20G

        L1ETHG -- "sends message via" --> L1SM[L1ScrollMessenger]
        L1CustomERC20G -- "sends message via" --> L1SM
        L1StdERC20G -- "sends message via" --> L1SM
    end

    subgraph Owner_Functions[Owner Functions]
        Owner[Contract Owner] -- "setETHGateway()" --> L1GR
        Owner -- "setDefaultERC20Gateway()" --> L1GR
        Owner -- "setERC20Gateway(token, gateway)" --> L1GR
    end

    %% Styling
    classDef user fill:#FFF3CD,stroke:#333,stroke-width:2px;
    classDef router fill:#C9DAF8,stroke:#333,stroke-width:2px;
    classDef gateway fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef messenger fill:#FADCD9,stroke:#333,stroke-width:2px;
    classDef logic fill:#E8DAEF,stroke:#333,stroke-width:1px,linestyle:dashed;

    class User user;
    class L1GR router;
    class L1ETHG, L1CustomERC20G, L1StdERC20G gateway;
    class L1SM messenger;
    class LogicGetGateway logic;
    class Owner owner;
```
