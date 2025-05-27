# User Transaction Flows: Detailed Breakdown

This document details two typical user transaction flows in the Scroll protocol: depositing a standard ERC20 token from Layer 1 to Layer 2, and withdrawing ETH from Layer 2 to Layer 1.

## Flow 1: L1 Standard ERC20 Deposit to L2

This flow describes how a user deposits an ERC20 token from Ethereum (L1) to Scroll (L2) using the standard gateway mechanism.

1.  **User Initiates Deposit on L1:**
    *   The user calls `depositERC20(l1TokenAddress, amount, l2GasLimit)` or `depositERC20(l1TokenAddress, l2RecipientAddress, amount, l2GasLimit)` on the `L1GatewayRouter` contract.
    *   The user must have approved the `L1GatewayRouter` to spend at least `amount` of their `l1TokenAddress` tokens.
    *   `msg.value` is also sent to cover the L1->L2 relay fee.

2.  **`L1GatewayRouter` Identifies `L1StandardERC20Gateway`:**
    *   The `L1GatewayRouter` calls its internal `getERC20Gateway(l1TokenAddress)` function. Assuming no custom gateway is registered for this token, this returns the address of the `L1StandardERC20Gateway`.
    *   The `L1GatewayRouter` then calls `depositERC20AndCall(l1TokenAddress, l2RecipientAddress, amount, routerData, l2GasLimit)` on the identified `L1StandardERC20Gateway`.
    *   `routerData` is `abi.encode(originalUserAddress, originalDataFromUser)`. The original user address is crucial for the `L1StandardERC20Gateway` to request tokens.

3.  **`L1StandardERC20Gateway` Requests Token Transfer:**
    *   The `L1StandardERC20Gateway`'s `_deposit()` internal function is called.
    *   It calls `_transferERC20In()`. Since the immediate `msg.sender` is the `L1GatewayRouter`, this function calls `IL1GatewayRouter(router).requestERC20(originalUserAddress, l1TokenAddress, amount)`.
    *   The `L1GatewayRouter.requestERC20()` function verifies that the caller (`L1StandardERC20Gateway`) is the `gatewayInContext` (which was set by the router before calling the gateway).
    *   `L1GatewayRouter` then executes `IERC20Upgradeable(l1TokenAddress).safeTransferFrom(originalUserAddress, L1StandardERC20GatewayAddress, amount)`, moving the tokens from the user to the `L1StandardERC20Gateway`.

4.  **`L1StandardERC20Gateway` Locks Tokens and Sends Message:**
    *   The tokens are now held (locked) by `L1StandardERC20Gateway`.
    *   The gateway determines the L2 token address using `getL2ERC20Address(l1TokenAddress)`. This function calculates the deterministic address based on the `L2StandardERC20Gateway`'s `l2TokenFactory` and `l2TokenImplementation`.
    *   **First-time deposit check:**
        *   If `tokenMapping[l1TokenAddress]` is `address(0)` (meaning this L1 token is being bridged for the first time via this standard gateway), the gateway prepares metadata.
        *   It fetches `name()`, `symbol()`, and `decimals()` from the `l1TokenAddress` contract.
        *   The `l2Data` for the `L2StandardERC20Gateway.finalizeDepositERC20()` call is encoded as `abi.encode(true, abi.encode(originalDataFromUser, abi.encode(name, symbol, decimals)))`. The `true` flag indicates metadata is present.
    *   **Subsequent deposits:**
        *   If `tokenMapping[l1TokenAddress]` is already set, `l2Data` is `abi.encode(false, originalDataFromUser)`.
    *   A message is constructed for `L2StandardERC20Gateway.finalizeDepositERC20()` containing `l1TokenAddress`, the calculated `l2TokenAddress`, `originalUserAddress` (as `_from`), `l2RecipientAddress` (as `_to`), `amount`, and the prepared `l2Data`.
    *   `L1StandardERC20Gateway` calls `L1ScrollMessenger.sendMessage{value: msg.value}(counterpartL2Gateway, 0, message, l2GasLimit, originalUserAddress)`.
    *   `L1ScrollMessenger` appends this message to `L1MessageQueueV2`.
    *   `L1StandardERC20Gateway` emits `DepositERC20`.

5.  **L2 Sequencer Picks Up the Message:**
    *   An L2 Sequencer observes `L1MessageQueueV2` on L1.
    *   It includes the user's L1->L2 message (now identified by its hash and nonce from `L1MessageQueueV2`) in an L2 block.

6.  **`L1ScrollMessenger`'s L2 Alias Calls `L2ScrollMessenger.relayMessage()`:**
    *   As part of processing the L2 block, the L2 execution environment effectively calls `L2ScrollMessenger.relayMessage()` from the L2 aliased address of `L1ScrollMessenger`.
    *   The parameters passed include the original L1 sender (`L1StandardERC20Gateway` aliased), the L2 target (`L2StandardERC20Gateway`), value (0), the message nonce, and the message payload (the `finalizeDepositERC20` calldata).

7.  **`L2ScrollMessenger` Executes Message on `L2StandardERC20Gateway`:**
    *   `L2ScrollMessenger.relayMessage()` verifies the caller is the aliased `L1ScrollMessenger` and that the message hasn't been executed before.
    *   It then calls `L2StandardERC20Gateway.finalizeDepositERC20{value: 0}(l1TokenAddress, l2TokenAddress, originalUserAddress, l2RecipientAddress, amount, l2Data)`.

8.  **`L2StandardERC20Gateway` Deploys/Mints L2 Tokens:**
    *   `L2StandardERC20Gateway.finalizeDepositERC20()` is executed.
    *   It decodes `l2Data` to check the `hasMetadata` flag.
    *   **First-time deposit:**
        *   If `hasMetadata` is true and the `l2TokenAddress` contract does not exist yet (`!l2TokenAddress.isContract()`), it means this is the first deposit for this token.
        *   `L2StandardERC20Gateway` calls `IScrollStandardERC20Factory(tokenFactory).deployL2Token(address(this), l1TokenAddress)` to deploy the L2 ERC20 token contract using `Clones.cloneDeterministic`.
        *   It then calls `initialize(name, symbol, decimals, address(this) [as gateway], l1TokenAddress)` on the newly deployed `l2TokenAddress`.
        *   The `tokenMapping[l2TokenAddress] = l1TokenAddress` is set in `L2StandardERC20Gateway`.
    *   **All deposits (first-time or subsequent):**
        *   `L2StandardERC20Gateway` calls `IScrollERC20Upgradeable(l2TokenAddress).mint(l2RecipientAddress, amount)`.
    *   If `callData` (extracted from `l2Data`) is present, it may perform a callback via `_doCallback`.
    *   Emits `FinalizeDepositERC20`. The user on L2 now has the bridged tokens.

## Flow 2: L2 ETH Withdrawal to L1

This flow describes how a user withdraws ETH from Scroll (L2) back to Ethereum (L1).

1.  **User Initiates Withdrawal on L2:**
    *   The user calls `withdrawETH(l1RecipientAddress, amount, l1GasLimit)` on the `L2GatewayRouter` contract (or directly on `L2ETHGateway`).
    *   The `msg.value` sent with this call must be equal to `amount` (the ETH to be withdrawn).

2.  **`L2GatewayRouter` Identifies `L2ETHGateway`:**
    *   `L2GatewayRouter` routes the call to `L2ETHGateway.withdrawETHAndCall(l1RecipientAddress, amount, routerData, l1GasLimit)`.
    *   `routerData` contains the original L2 user's address.

3.  **`L2ETHGateway` Takes ETH and Sends Message:**
    *   `L2ETHGateway._withdraw()` is executed.
    *   The ETH (`amount`) is taken from the user (as it was sent as `msg.value` to the gateway).
    *   A message is constructed for `L1ETHGateway.finalizeWithdrawETH()` containing the original L2 user's address (as `_from`), `l1RecipientAddress` (as `_to`), `amount`, and any auxiliary data.
    *   `L2ETHGateway` calls `L2ScrollMessenger.sendMessage{value: amount}(l1ETHGatewayAddress, amount, message, l1GasLimit)`. The `amount` is passed as `msg.value` to `L2ScrollMessenger` which should then hold this ETH.

4.  **`L2MessageQueue` Includes Message Hash:**
    *   `L2ScrollMessenger.sendMessage()` computes the cross-domain calldata hash.
    *   It calls `L2MessageQueue.appendMessage(hash)`, which adds the hash to its Merkle tree and updates the `messageRoot`.
    *   `L2ScrollMessenger` emits `SentMessage`.

5.  **L2 Batch Finalized on L1:**
    *   The L2 Sequencer includes the transaction (and thus the `L2MessageQueue` update) in an L2 batch.
    *   This batch is processed by L2 Provers who generate a validity proof.
    *   The Sequencer submits the batch data (including the new `messageRoot` from `L2MessageQueue` as the `withdrawRoot`) to `ScrollChain` on L1.
    *   The Prover submits the proof to `ScrollChain`.
    *   `ScrollChain` verifies the proof and finalizes the batch, storing the `withdrawRoot` in its `withdrawRoots` mapping.

6.  **User/Relayer Provides Proof to `L1ScrollMessenger`:**
    *   The user (or a relayer service) monitors `ScrollChain` for the finalization of the batch containing their withdrawal.
    *   Once finalized, they construct an `L2MessageProof` containing the `batchIndex` and a Merkle proof demonstrating that their message hash is part of the finalized `withdrawRoot` for that batch.
    *   They call `L1ScrollMessenger.relayMessageWithProof(l2UserAddress, l1ETHGatewayAddress, amount, l2MessageNonce, l1GatewayFinalizeCallData, proof)`.

7.  **`L1ScrollMessenger` Verifies Proof and Calls `L1ETHGateway`:**
    *   `L1ScrollMessenger.relayMessageWithProof()` checks that the message hasn't been executed before.
    *   It calls `IScrollChain(rollup).isBatchFinalized(proof.batchIndex)` and `IScrollChain(rollup).withdrawRoots(proof.batchIndex)`.
    *   It uses `WithdrawTrieVerifier.verifyMerkleProof()` to validate the provided Merkle proof against the stored `withdrawRoot`.
    *   If valid, it sets `xDomainMessageSender = l2UserAddress` (original L2 sender) and calls `L1ETHGateway.finalizeWithdrawETH{value: amount}(l2UserAddress, l1RecipientAddress, amount, auxiliaryData)`. The `amount` is forwarded as `msg.value`.

8.  **`L1ETHGateway` Transfers ETH to User on L1:**
    *   `L1ETHGateway.finalizeWithdrawETH()` is executed.
    *   It verifies `msg.sender` is `L1ScrollMessenger` and `xDomainMessageSender` is its L2 counterpart (`L2ETHGateway`), via the `onlyCallByCounterpart` modifier.
    *   It requires `msg.value == amount`.
    *   It transfers the `amount` of ETH to the `l1RecipientAddress`: `l1RecipientAddress.call{value: amount}("")`.
    *   If auxiliary data was present, it might perform a callback via `_doCallback`.
    *   Emits `FinalizeWithdrawETH`. The user on L1 now has their withdrawn ETH.

These flows illustrate the intricate coordination between L1 and L2 contracts, messengers, and sequencers/provers to ensure secure and reliable asset bridging and message passing.
