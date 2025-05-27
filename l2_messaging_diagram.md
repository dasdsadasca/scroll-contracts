```mermaid
graph TD
    subgraph L2Environment [Scroll L2 Network]
        L2SM[L2ScrollMessenger]
        L2MQ[L2MessageQueue]

        subgraph L2SM_Internals [L2ScrollMessenger Internals]
            L2SM_sendMessage["sendMessage(to, value, msg, gasLimit)"]
            L2SM_relayMessage["relayMessage(from, to, value, nonce, msg)"]
            L2SM_isL1Executed["isL1MessageExecuted mapping"]
            L2SM_sendTimestamp["messageSendTimestamp mapping"]
            L2SM_counterpart["counterpart (L1ScrollMessenger addr)"]
            L2SM_mqAddr["messageQueue (L2MessageQueue addr)"]
        end

        subgraph L2MQ_Internals [L2MessageQueue Internals]
            L2MQ_appendMessage["appendMessage(messageHash)"]
            L2MQ_initialize["initialize(messengerAddr)"]
            L2MQ_messengerAddr["messenger (L2ScrollMessenger addr)"]
            L2MQ_merkleRoot["messageRoot (Merkle Root)"]
            L2MQ_nextIndex["nextMessageIndex"]
            L2MQ_AppendEvent[AppendMessage Event]
        end
        
        L2SM -- Uses --> L2SM_mqAddr
        L2SM_mqAddr -. Points to .-> L2MQ

    end

    subgraph L2Actors [L2 Actors & Off-Chain Components]
        L2User[L2 User / L2 Gateway]
        L1SM_Aliased[L1ScrollMessenger (Aliased L2 Address)]
        L2Sequencer[L2 Sequencer Node (Conceptual)]
        L2TargetContract[Target L2 Contract]
    end
    
    %% L2 User/Gateway sending L2->L1 message
    L2User -- Calls --> L2SM_sendMessage
    L2SM_sendMessage -- "1. Computes xDomainCalldataHash\n2. Gets nonce from L2MQ_nextIndex" .-> L2SM
    L2SM -- "3. Calls appendMessage(xDomainCalldataHash)" --> L2MQ_appendMessage
    L2MQ_appendMessage -- "4. Updates Merkle Tree & messageRoot" --> L2MQ_merkleRoot
    L2MQ_appendMessage -- "5. Emits AppendMessage" --> L2MQ_AppendEvent
    L2SM_sendMessage -- "6. Records messageSendTimestamp" --> L2SM_sendTimestamp
    L2SM_sendMessage -- "7. Emits SentMessage" --> L2SM

    %% L1ScrollMessenger (aliased) relaying L1->L2 message
    L1SM_Aliased -- "Calls relayMessage(...)" --> L2SM_relayMessage
    L2SM_relayMessage -- "1. Checks !isL1MessageExecuted" --> L2SM_isL1Executed
    L2SM_relayMessage -- "2. Sets xDomainMessageSender" --> L2SM
    L2SM_relayMessage -- "3. Executes message on" --> L2TargetContract
    L2TargetContract -- "4. Returns success/fail" --> L2SM_relayMessage
    L2SM_relayMessage -- "5. Updates isL1MessageExecuted" --> L2SM_isL1Executed
    L2SM_relayMessage -- "6. Emits RelayedMessage or FailedRelayedMessage" --> L2SM

    %% L2MessageQueue interactions
    L2MQ_initialize -- Sets --> L2MQ_messengerAddr
    L2MQ_messengerAddr -. Points to .-> L2SM
    
    %% Sequencer interaction (conceptual)
    L2Sequencer -. Reads .-> L2MQ_merkleRoot


    classDef l2contract fill:#DFFFE2,stroke:#3BBD72,stroke-width:2px;
    classDef l2actor fill:#FFE0B2,stroke:#D95B00,stroke-width:2px;
    classDef l2internal fill:#F0F8FF,stroke:#6495ED,stroke-width:1px;

    class L2SM,L2MQ l2contract;
    class L2User,L1SM_Aliased,L2Sequencer,L2TargetContract l2actor;
    class L2SM_sendMessage,L2SM_relayMessage,L2SM_isL1Executed,L2SM_sendTimestamp,L2SM_counterpart,L2SM_mqAddr l2internal;
    class L2MQ_appendMessage,L2MQ_initialize,L2MQ_messengerAddr,L2MQ_merkleRoot,L2MQ_nextIndex,L2MQ_AppendEvent l2internal;
```
