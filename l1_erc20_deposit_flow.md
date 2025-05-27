```mermaid
sequenceDiagram
    actor User
    participant L1GR as L1GatewayRouter
    participant L1StdERC20G as L1StandardERC20Gateway
    participant L1SM as L1ScrollMessenger
    participant L1MQV2 as L1MessageQueueV2
    participant L2Seq as L2 Sequencer (Conceptual)
    participant L1SM_L2A as L1ScrollMessenger L2 Alias
    participant L2SM as L2ScrollMessenger
    participant L2StdERC20G as L2StandardERC20Gateway
    participant ERC20Factory as ScrollStandardERC20Factory
    participant L2Token as L2 ERC20 Token

    User->>+L1GR: depositERC20(l1Token, amount, gasLimit)
    L1GR->>+L1StdERC20G: depositERC20AndCall(l1Token, user, amount, routerData, gasLimit)
    L1StdERC20G->>-L1GR: requestERC20(user, l1Token, amount)
    Note over User, L1StdERC20G: L1GR transfers L1 ERC20 from User to L1StdERC20G
    L1StdERC20G-->>-User: Tokens Locked
    opt First-time deposit for this token
        L1StdERC20G->>L1StdERC20G: Get L1 token metadata (name, symbol, decimals)
        L1StdERC20G->>L1StdERC20G: Prepare L2 data with metadata flag
    end
    L1StdERC20G->>+L1SM: sendMessage(L2StdERC20G_addr, 0, finalizeMsgData, gasLimit, user)
    L1SM->>+L1MQV2: appendCrossDomainMessage(L2SM_addr, gasLimit, xDomainCalldata)
    L1MQV2-->>-L1SM: Message Queued
    L1SM-->>-L1StdERC20G: Returns
    L1StdERC20G-->>User: Deposit Initiated on L1

    L2Seq->>L1MQV2: Reads message
    L2Seq->>L1SM_L2A: Includes message in L2 block execution

    L1SM_L2A->>+L2SM: relayMessage(L1StdERC20G_aliased, L2StdERC20G_addr, 0, nonce, finalizeMsgData)
    L2SM->>+L2StdERC20G: finalizeDepositERC20(l1Token, l2Token, user_L1_addr, user_L2_addr, amount, l2DataWithMeta)
    opt First-time deposit for this token and L2 token not deployed
        L2StdERC20G->>+ERC20Factory: deployL2Token(L2StdERC20G_addr, l1Token)
        ERC20Factory-->>-L2StdERC20G: l2TokenAddress
        L2StdERC20G->>+L2Token: initialize(name, symbol, decimals, L2StdERC20G_addr, l1Token)
        L2Token-->>-L2StdERC20G: Initialized
    end
    L2StdERC20G->>+L2Token: mint(user_L2_addr, amount)
    L2Token-->>-L2StdERC20G: Minted
    L2StdERC20G-->>-L2SM: Returns
    L2SM-->>-L1SM_L2A: Returns
    Note over User, L2Token: User receives L2 ERC20 tokens
```
