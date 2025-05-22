# ERC20 Deposit Flow: Layer 1 to Layer 2 (Scroll)

This document outlines the step-by-step process for a user depositing ERC20 tokens from Layer 1 (Ethereum Mainnet) to Layer 2 (Scroll Network).

1.  **User Pre-approval (L1):**
    *   Before initiating the deposit, the User must approve the chosen `L1ERC20Gateway` (either `L1StandardERC20Gateway` or a specific custom L1 ERC20 gateway if applicable for the token) to spend their ERC20 tokens. This is done by calling the `approve(spender, amount)` function on the L1 ERC20 token contract, where `spender` is the address of the relevant `L1ERC20Gateway`.

2.  **User Initiates Deposit (L1):**
    *   The User calls `depositERC20(l1TokenAddress, amount, l2GasLimit)` or `depositERC20(l1TokenAddress, to, amount, l2GasLimit)` on the `L1GatewayRouter` contract.
    *   The `l1TokenAddress` is the address of the ERC20 token contract on L1.

3.  **L1GatewayRouter (L1):**
    *   Receives the call.
    *   Calls `getERC20Gateway(l1TokenAddress)` internally to determine the appropriate L1 ERC20 gateway for the specified L1 token. This will return the address of a registered custom gateway for `l1TokenAddress` or the address of the `defaultERC20Gateway` (typically `L1StandardERC20Gateway`). Let's call this `ChosenL1ERC20Gateway`.
    *   Routes the call to `ChosenL1ERC20Gateway.depositERC20(l1TokenAddress, to, amount, l2GasLimit)`. The `to` address is either `msg.sender` or the `to` address provided by the user.

4.  **ChosenL1ERC20Gateway (e.g., `L1StandardERC20Gateway`) (L1):**
    *   Receives the call from `L1GatewayRouter`.
    *   **Transfers Tokens:** Calls `IERC20(l1TokenAddress).transferFrom(userAddress, address(this), amount)`. This pulls the specified `amount` of the ERC20 token from the User's L1 address to the `ChosenL1ERC20Gateway` contract, effectively locking the tokens on L1. This step requires the prior approval from step 1.
    *   Constructs a message payload for L2. For `L1StandardERC20Gateway`, this payload is typically the calldata for `L2StandardERC20Gateway.finalizeDepositERC20(l1TokenAddress, l2TokenAddress, l1Sender, l2Recipient, amount, dataForL2Call)`.
        *   `l1TokenAddress`: The address of the token on L1.
        *   `l2TokenAddress`: The address of the corresponding token on L2. For standard tokens, `L1StandardERC20Gateway` might determine this by calling `getL2ERC20Address(l1TokenAddress)` or it might be passed from the router if known. The L2 gateway will handle deploying a new L2 token if one doesn't exist.
        *   `l1Sender`: The original `msg.sender` on L1 (the User).
        *   `l2Recipient`: The address that will receive tokens on L2.
        *   `amount`: The amount of ERC20 tokens deposited.
        *   `dataForL2Call`: If `depositERC20AndCall` was used, this contains the additional calldata. Otherwise, it's empty.
    *   Calls `L1ScrollMessenger.sendMessage(target, value, message, gasLimit, refundAddress)`:
        *   `target`: The address of the corresponding `L2ERC20Gateway` (e.g., `L2StandardERC20Gateway`) contract on L2.
        *   `value`: **0**. The ERC20 tokens are locked; no ETH is being sent with the message itself via this parameter.
        *   `message`: The encoded calldata for `L2ERC20Gateway.finalizeDepositERC20(...)`.
        *   `gasLimit`: The `l2GasLimit` provided by the User.
        *   `refundAddress`: An address for gas refunds.

5.  **L1ScrollMessenger (L1):**
    *   (Same as ETH deposit flow) Receives the `sendMessage` call.
    *   Calculates the required cross-domain fee. The `ChosenL1ERC20Gateway` must ensure this fee is paid to `L1ScrollMessenger` (e.g., by requiring `msg.value` in its own payable `depositERC20` wrapper).
    *   Encodes the cross-domain message (sender is `ChosenL1ERC20Gateway`).
    *   Calls `L1MessageQueueV2.appendCrossDomainMessage(...)` to queue the message.
    *   Emits a `SentMessage` event.

6.  **L1MessageQueueV2 (L1):**
    *   (Same as ETH deposit flow) Stores the encoded cross-domain message for Sequencer pickup.

7.  **Sequencer (Off-chain):**
    *   (Same as ETH deposit flow) Monitors `L1MessageQueueV2`, picks up the message, includes it in an L2 batch, and submits the batch commitment to `ScrollChain` on L1.

8.  **ScrollChain (L1):**
    *   (Same as ETH deposit flow) Receives batch commitment. Later, upon proof verification, the L1 message is considered finalized as part of the canonical L2 history.

9.  **Relayer/Executor on L2 (L2 System):**
    *   (Same as ETH deposit flow) Once the L1 message is included in an L2 block, the aliased `L1ScrollMessenger` on L2 initiates a call to `L2ScrollMessenger.relayMessage`.

10. **L2ScrollMessenger (L2):**
    *   (Same as ETH deposit flow) Receives `relayMessage`.
    *   Verifies the caller (aliased `L1ScrollMessenger`).
    *   Checks for message uniqueness.
    *   Sets `xDomainMessageSender` to `ChosenL1ERC20Gateway`'s L1 address.
    *   Calls `_executeMessage`, which executes the message on the target L2 contract: `L2ERC20Gateway.finalizeDepositERC20(...)`.

11. **L2ERC20Gateway (e.g., `L2StandardERC20Gateway`) (L2):**
    *   Receives the `finalizeDepositERC20(l1TokenAddress, l2TokenAddress_from_L1, l1Sender, l2Recipient, amount, dataForL2Call)` call from `L2ScrollMessenger`.
    *   **Determine/Deploy L2 Token:**
        *   It checks if a corresponding L2 token for `l1TokenAddress` already exists (e.g., by looking up `l1TokenToL2Token[l1TokenAddress]`).
        *   If it doesn't exist (and it's `L2StandardERC20Gateway`), it may deploy a new "Scroll Standard" L2 ERC20 token contract (a mintable/burnable ERC20). It would then store the mapping: `l1TokenToL2Token[l1TokenAddress] = newL2TokenAddress` and `l2TokenToL1Token[newL2TokenAddress] = l1TokenAddress`. The `l2TokenAddress_from_L1` might be `address(0)` if the L1 gateway expects L2 to deploy.
        *   For custom gateways, the L2 token is usually pre-determined and pre-deployed.
    *   **Mints L2 Tokens:** Calls `mint(l2Recipient, amount)` on the determined L2 ERC20 token contract. This creates new L2 tokens and assigns them to the user.
    *   If `dataForL2Call` is not empty (from an `depositERC20AndCall`), it then makes a call to `l2Recipient` with the `dataForL2Call`.
    *   Emits an event (e.g., `FinalizeDepositERC20`) indicating the successful finalization of the ERC20 deposit on L2.

This completes the ERC20 deposit flow. The user's L1 ERC20 tokens are locked in the L1 gateway, and an equivalent amount of corresponding L2 tokens (either newly deployed standard wrapped tokens or pre-existing custom tokens) are minted to them on L2.Okay, I have created the detailed ERC20 deposit flow description.

Now, I will create the Mermaid sequence diagram for this flow.
