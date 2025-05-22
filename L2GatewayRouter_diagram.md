```mermaid
flowchart TD
    User[User on L2] --> L2GR[L2GatewayRouter]

    subgraph L2GatewayRouter_Interaction
        direction LR
        L2GR -- "withdrawETH()" calls --> L2ETHG[L2ETHGateway]
        L2GR -- "withdrawERC20() / withdrawERC20AndCall()" --> LogicGetGateway{getERC20Gateway}
        LogicGetGateway -- "token specific" --> L2CustomERC20G[L2CustomERC20Gateway]
        LogicGetGateway -- "default" --> L2StdERC20G[L2StandardERC20Gateway (default)]
        L2GR -- "getL1ERC20Address()" calls --> L2StdERC20G

        L2ETHG -- "sends message via" --> L2SM[L2ScrollMessenger]
        L2CustomERC20G -- "sends message via" --> L2SM
        L2StdERC20G -- "sends message via" --> L2SM
    end

    subgraph Owner_Functions[Owner Functions]
        Owner[Contract Owner] -- "setETHGateway()" --> L2GR
        Owner -- "setDefaultERC20Gateway()" --> L2GR
        Owner -- "setERC20Gateway(token, gateway)" --> L2GR
    end

    subgraph Finalize_Revert_Note
        direction TB
        style Finalize_Revert_Note fill:#f8f8f8,stroke:#ccc,stroke-dasharray: 5 5
        RevertNote["finalizeDeposit...() functions revert: \n'should never be called' \n (Finalization is gateway's role)"]
        L2GR --- RevertNote
    end

    %% Styling
    classDef user fill:#FFF3CD,stroke:#333,stroke-width:2px;
    classDef router fill:#C9DAF8,stroke:#333,stroke-width:2px;
    classDef gateway fill:#D4EFDF,stroke:#333,stroke-width:2px;
    classDef messenger fill:#FADCD9,stroke:#333,stroke-width:2px;
    classDef logic fill:#E8DAEF,stroke:#333,stroke-width:1px,linestyle:dashed;

    class User user;
    class L2GR router;
    class L2ETHG, L2CustomERC20G, L2StdERC20G gateway;
    class L2SM messenger;
    class LogicGetGateway logic;
    class Owner owner;
    class RevertNote text;
```
