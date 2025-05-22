# ETH Deposit Flow: Layer 1 to Layer 2 (Scroll)

This document outlines the step-by-step process for a user depositing ETH from Layer 1 (Ethereum Mainnet) to Layer 2 (Scroll Network).

1.  **User Initiates Deposit (L1):**
    *   The User calls `depositETH(amount, l2GasLimit)` or `depositETH(to, amount, l2GasLimit)` on the `L1GatewayRouter` contract.
    *   The User sends ETH along with this transaction (`msg.value` should be equal to `amount`).

2.  **L1GatewayRouter (L1):**
    *   Receives the call and the ETH.
    *   Routes the call to the registered `L1ETHGateway` contract by calling `L1ETHGateway.depositETH{value: amount}(to, amount, l2GasLimit)`. The `to` address is either `msg.sender` (if not specified by user) or the `to` address provided by the user.

3.  **L1ETHGateway (L1):**
    *   Receives the ETH from `L1GatewayRouter`.
    *   **Locks the received ETH within itself.**
    *   Constructs a message payload for L2. This payload is the calldata for the function to be executed on L2, which is `L2ETHGateway.finalizeDepositETH(l1Sender, l2Recipient, amount)`.
        *   `l1Sender`: The original `msg.sender` on L1 (the User).
        *   `l2Recipient`: The address that will receive ETH on L2 (either `msg.sender` from L1 or the `_to` address specified by the User).
        *   `amount`: The amount of ETH deposited.
    *   Calls `L1ScrollMessenger.sendMessage(target, value, message, gasLimit, refundAddress)`:
        *   `target`: The address of the `L2ETHGateway` contract on L2.
        *   `value`: This is **0**. The actual ETH value (`amount`) is locked in `L1ETHGateway`; this parameter in `sendMessage` refers to any *additional* ETH to be sent along with the message itself, which is not the case here. The `amount` to be credited on L2 is part of the `message` payload.
        *   `message`: The encoded calldata for `L2ETHGateway.finalizeDepositETH(...)`.
        *   `gasLimit`: The `l2GasLimit` provided by the User for the L2 transaction.
        *   `refundAddress`: An address to receive gas refunds (typically the User).

4.  **L1ScrollMessenger (L1):**
    *   Receives the `sendMessage` call from `L1ETHGateway`.
    *   Calculates the required cross-domain fee (based on `gasLimit` and current L1 base fee). This fee must be covered by the ETH sent to `L1ScrollMessenger` by `L1ETHGateway` (if `L1ETHGateway` forwards fees) or paid by `L1ETHGateway` itself. (Note: `L1ETHGateway` doesn't send its own ETH to `L1ScrollMessenger` for the `value` parameter, but it must ensure fees are paid for the message. Typically, the `L1ETHGateway` wrapper functions for `sendMessage` will require `msg.value` to cover the fee.)
    *   Encodes the cross-domain message, which includes:
        *   `msg.sender` (which is `L1ETHGateway` in this context)
        *   `target` (`L2ETHGateway` address)
        *   `value` (0 in this case)
        *   A unique `messageNonce` for `L1ETHGateway`
        *   The `message` payload (calldata for `L2ETHGateway.finalizeDepositETH`)
    *   Calls `L1MessageQueueV2.appendCrossDomainMessage(sender, target, value, nonce, message, feePayment)` to queue the encoded message.
    *   Emits a `SentMessage` event with details of the message.

5.  **L1MessageQueueV2 (L1):**
    *   Stores the encoded cross-domain message.
    *   This message is now pending and will be picked up by an L2 Sequencer.

6.  **Sequencer (Off-chain):**
    *   Monitors `L1MessageQueueV2` on L1.
    *   Picks up the pending message (and others) from the queue.
    *   Includes this L1-to-L2 message in a new L2 block/batch that it is constructing.
    *   The Sequencer submits this batch commitment (including a reference to the L1 messages processed) to the `ScrollChain` contract on L1.

7.  **ScrollChain (L1):**
    *   Receives the batch commitment from the Sequencer.
    *   The `ScrollChain` contract, through its interaction with `L1MessageQueueV2` (e.g., via `popCrossDomainMessage` or by verifying `messageRollingHash` during finalization), acknowledges that the L1 message has been included in an L2 batch.
    *   Later, when the batch proof is submitted by a Prover and verified, `ScrollChain.finalizeBundlePostEuclidV2` (or similar) is called. This marks the L2 batch as finalized, and also finalizes the L1 messages within it (e.g., by calling `L1MessageQueueV2.finalizePoppedCrossDomainMessage`). This step confirms the L1 message's processing is part of the canonical L2 history.

8.  **Relayer/Executor on L2 (L2 System - often part of Sequencer/Node infrastructure):**
    *   Once the L1 message is included in an L2 block by the Sequencer, the L2 system processes it.
    *   This involves the aliased `L1ScrollMessenger` address on L2 (a special address that represents the L1 Scroll Messenger) initiating a call to `L2ScrollMessenger.relayMessage`.

9.  **L2ScrollMessenger (L2):**
    *   Receives the `relayMessage` call. The `msg.sender` of this call is the aliased `L1ScrollMessenger` address.
    *   **Verifies Caller:** Uses `AddressAliasHelper.undoL1ToL2Alias(msg.sender)` to ensure the call originates from the legitimate aliased `L1ScrollMessenger`.
    *   **Checks Uniqueness:** Ensures this specific L1 message (identified by its hash) has not been executed before on L2 (prevents replays).
    *   Sets `xDomainMessageSender` to the original L1 sender of the message (which is the `L1ETHGateway`'s address).
    *   Calls `_executeMessage`, which then executes the message on the target L2 contract: `L2ETHGateway.finalizeDepositETH{value: 0}(l1Sender, l2Recipient, amount)`. The `value` passed here is the `value` from the `sendMessage` call (0), not the `amount` from the payload.

10. **L2ETHGateway (L2):**
    *   Receives the `finalizeDepositETH(l1Sender, l2Recipient, amount)` call from `L2ScrollMessenger`.
    *   The `msg.sender` of this call is `L2ScrollMessenger`. The `xDomainMessageSender()` if called on `L2ScrollMessenger` would return `L1ETHGateway`. The actual L1 initiator (`User`) is available as `l1Sender`.
    *   **Mints/credits the `amount` of ETH to the `l2Recipient` address on L2.** This step effectively makes the deposited ETH available to the user on the Scroll network.
    *   Emits an event (e.g., `FinalizeDepositETH`) indicating the successful finalization of the ETH deposit on L2.

This completes the ETH deposit flow from L1 to L2. The user's ETH is locked on L1, and an equivalent amount is made available to them on L2.Okay, I have created the detailed ETH deposit flow description.

Now, I will create the Mermaid sequence diagram for this flow.
