# Gateway Routers and L1/L2 Gateway Interaction Patterns: Detailed Breakdown

This document provides a detailed breakdown of the `L1GatewayRouter.sol`, `L2GatewayRouter.sol`, and the general interaction patterns for L1 and L2 asset gateways in the Scroll protocol.

## 1. L1GatewayRouter.sol

### Purpose

`L1GatewayRouter.sol` serves as the primary user-facing entry point on Layer 1 for depositing ETH and ERC20 tokens into the Scroll L2 network. Its main function is to simplify the deposit process by routing user requests to the appropriate specific L1 gateway contract (e.g., `L1ETHGateway`, `L1StandardERC20Gateway`, or a custom ERC20 gateway) based on the asset being deposited. This decouples the user from needing to know the address of each specific gateway.

### Key State Variables

*   **`ethGateway` (`address`):** The address of the dedicated `L1ETHGateway` contract.
*   **`defaultERC20Gateway` (`address`):** The address of the default L1 ERC20 gateway, typically `L1StandardERC20Gateway`, used for ERC20 tokens that don't have a specific gateway assigned.
*   **`ERC20Gateway` (mapping `address => address`):** A mapping that allows specific ERC20 token addresses to be routed to designated L1 ERC20 gateway contracts (e.g., `L1CustomERC20Gateway`, `L1USDCGateway`).
*   **`gatewayInContext` (`address`):** A state variable used during ERC20 deposits. When a specific L1 ERC20 gateway needs to pull tokens from the user (who initiated the call through the router), the router sets `gatewayInContext` to the address of that specific gateway. The specific gateway then calls `requestERC20` on the router, which verifies that the caller is indeed the `gatewayInContext`.

### Key Functions

*   **`depositETH(uint256 _amount, uint256 _gasLimit)` / `depositETH(address _to, uint256 _amount, uint256 _gasLimit)`:**
    *   User-callable functions to deposit ETH. `_to` specifies the L2 recipient (defaults to `msg.sender`).
    *   These functions simply delegate the call to the `ethGateway` by calling its `depositETHAndCall()` method, passing along parameters and `msg.value`.
    *   The actual `msg.sender` (original user) is encoded in the `_data` argument passed to the `L1ETHGateway` to ensure the L2 message correctly attributes the deposit.

*   **`depositETHAndCall(address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)`:**
    *   A more general ETH deposit function allowing arbitrary data to be passed for L2 execution.
    *   It requires `gatewayInContext == address(0)` (via `onlyNotInContext` modifier) to prevent reentrancy during context-sensitive operations like `requestERC20`.
    *   It encodes the original `msg.sender` along with the provided `_data` and calls the `ethGateway`.

*   **`depositERC20(address _token, uint256 _amount, uint256 _gasLimit)` / `depositERC20(address _token, address _to, uint256 _amount, uint256 _gasLimit)`:**
    *   User-callable functions to deposit ERC20 tokens.
    *   These route to `depositERC20AndCall`.

*   **`depositERC20AndCall(address _token, address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)`:**
    *   The core ERC20 deposit routing logic.
    *   It first determines the appropriate L1 ERC20 gateway using `getERC20Gateway(_token)`.
    *   It sets `gatewayInContext` to the address of the selected specific gateway.
    *   It then calls `depositERC20AndCall()` on the selected specific gateway, passing along parameters. The original `msg.sender` is encoded in `_data` for the specific gateway to use.
    *   After the specific gateway returns, it clears `gatewayInContext`.
    *   Protected by `onlyNotInContext` modifier.

*   **`getERC20Gateway(address _token)` (public view):**
    *   Returns the specific L1 ERC20 gateway registered for `_token` in the `ERC20Gateway` mapping.
    *   If no specific gateway is found, it returns the `defaultERC20Gateway`.

*   **`requestERC20(address _sender, address _token, uint256 _amount)` (external returns `uint256`):**
    *   This function is *called by a specific L1 ERC20 gateway* (e.g., `L1StandardERC20Gateway`) during its deposit process.
    *   It's protected by the `onlyInContext` modifier, meaning `msg.sender` must be the `gatewayInContext` (the specific gateway that the router just called).
    *   It performs the `safeTransferFrom` of `_amount` of `_token` from `_sender` (the original user who called the router) to the `msg.sender` (the specific L1 ERC20 gateway).
    *   Returns the actual amount transferred (to handle fee-on-transfer tokens).

*   **Owner Functions:**
    *   `setETHGateway(address _newEthGateway)`: Updates the `ethGateway` address.
    *   `setDefaultERC20Gateway(address _newDefaultERC20Gateway)`: Updates the `defaultERC20Gateway` address.
    *   `setERC20Gateway(address[] memory _tokens, address[] memory _gateways)`: Updates the `ERC20Gateway` mapping for specific tokens.

*   **`finalizeWithdrawERC20(...)` / `finalizeWithdrawETH(...)`:**
    *   These functions are part of the `IL1ETHGateway` and `IL1ERC20Gateway` interfaces that `L1GatewayRouter` implements. However, in `L1GatewayRouter`, they are implemented to `revert("should never be called")`. This is because withdrawals are handled directly by the specific L1 gateways, not routed through the router. The router's role is primarily for deposits.

### Interactions

*   **Users:** Call `depositETH()`, `depositERC20()`, etc., to initiate asset bridging to L2.
*   **Specific L1 Gateways (e.g., `L1ETHGateway`, `L1StandardERC20Gateway`):**
    *   The router calls `deposit<Asset>AndCall()` on the appropriate specific L1 gateway.
    *   Specific L1 ERC20 gateways call `router.requestERC20()` to pull tokens from the user.
*   **Implicitly with `L1ScrollMessenger`:** The specific L1 gateways, after receiving the routed call and assets, will then interact with `L1ScrollMessenger` to send the L1->L2 message.

## 2. L2GatewayRouter.sol

### Purpose and Role

`L2GatewayRouter.sol` on Layer 2 mirrors the `L1GatewayRouter` in structure and is the primary user-facing entry point on L2 for withdrawing assets back to L1. It routes ETH and ERC20 withdrawal requests to the appropriate specific L2 gateway contract.

### Key State Variables

*   **`ethGateway` (`address`):** The address of the dedicated `L2ETHGateway` contract.
*   **`defaultERC20Gateway` (`address`):** The address of the default L2 ERC20 gateway (e.g., `L2StandardERC20Gateway`).
*   **`ERC20Gateway` (mapping `address => address`):** A mapping for specific L2 ERC20 tokens to their designated L2 ERC20 gateway contracts.
*   **(No `gatewayInContext` equivalent needed for withdrawals typically, as L2 tokens are usually burned by/sent directly to the specific L2 gateway called by the router.)**

### Key Functions

*   **`withdrawETH(uint256 _amount, uint256 _gasLimit)` / `withdrawETH(address _to, uint256 _amount, uint256 _gasLimit)`:**
    *   User-callable functions on L2 to withdraw ETH to L1. `_to` specifies the L1 recipient.
    *   Delegates to `ethGateway.withdrawETHAndCall()`. The original L2 `msg.sender` is encoded in the `_data` argument.

*   **`withdrawETHAndCall(address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)`:**
    *   Core ETH withdrawal routing. Encodes original `msg.sender` and calls the `ethGateway`.

*   **`withdrawERC20(address _token, uint256 _amount, uint256 _gasLimit)` / `withdrawERC20(address _token, address _to, uint256 _amount, uint256 _gasLimit)`:**
    *   User-callable functions on L2 to withdraw ERC20 tokens to L1.
    *   Delegates to `withdrawERC20AndCall`.

*   **`withdrawERC20AndCall(address _token, address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)`:**
    *   Core ERC20 withdrawal routing. Determines the specific L2 gateway using `getERC20Gateway(_token)`.
    *   Encodes original `msg.sender` and calls `withdrawERC20AndCall()` on the selected specific L2 gateway.

*   **`getERC20Gateway(address _token)` (public view):**
    *   Returns the specific L2 ERC20 gateway for `_token` or the `defaultERC20Gateway`.

*   **Owner Functions:**
    *   `setETHGateway()`, `setDefaultERC20Gateway()`, `setERC20Gateway()`: Similar to L1 router for managing gateway addresses.

*   **`finalizeDepositETH(...)` / `finalizeDepositERC20(...)`:**
    *   Implemented to revert, as L2 router handles withdrawals. Deposits are finalized by specific L2 gateways.

### Interactions

*   **L2 Users/DApps:** Call `withdrawETH()`, `withdrawERC20()`, etc., to initiate asset bridging from L2 to L1.
*   **Specific L2 Gateways (e.g., `L2ETHGateway`, `L2StandardERC20Gateway`):**
    *   The router calls `withdraw<Asset>AndCall()` on the appropriate specific L2 gateway.
*   **Implicitly with `L2ScrollMessenger`:** The specific L2 gateways, after receiving the routed call and processing the L2 side of the withdrawal (e.g., burning tokens), will interact with `L2ScrollMessenger` to send the L2->L1 message.

## 3. General L1 Gateway Pattern (e.g., `L1ETHGateway.sol`, abstract `L1ERC20Gateway.sol`)

These contracts are specialized for handling a particular asset type (ETH, standard ERC20s, specific custom ERC20s) on L1 during the bridging process. They inherit from `ScrollGatewayBase`.

### Purpose

*   **Asset Handling on L1:** Securely hold/lock assets being deposited from L1 to L2. Release/transfer assets to users when finalizing withdrawals from L2.
*   **Message Formatting:** Construct the appropriate message payload for the L2 counterpart gateway.
*   **Communication Initiation (Deposits):** Send messages to their L2 counterpart via `L1ScrollMessenger` to inform L2 about a deposit.
*   **Communication Finalization (Withdrawals):** Receive messages from their L2 counterpart via `L1ScrollMessenger` to finalize a withdrawal.

### Common Functions

*   **`deposit<Asset>(...)` / `deposit<Asset>AndCall(...)` (e.g., `depositETHAndCall`, `depositERC20AndCall`):**
    *   Usually called by `L1GatewayRouter`.
    *   Receive asset from the user (ETH directly, ERC20s via `router.requestERC20()` or direct `transferFrom`).
    *   Lock the asset within the gateway contract.
    *   Construct a message for the L2 gateway (e.g., `IL2ETHGateway.finalizeDepositETH.selector` or `IL2ERC20Gateway.finalizeDepositERC20.selector`) including details like L1 sender, L2 recipient, amount, and any auxiliary data.
    *   Call `L1ScrollMessenger.sendMessage()` with the L2 counterpart address, ETH value (if any, for gas on L2 or if bridging ETH itself), the constructed message, and gas limit.
    *   Emit a `Deposit<Asset>` event.

*   **`finalizeWithdraw<Asset>(...)` (e.g., `finalizeWithdrawETH`, `finalizeWithdrawERC20`):**
    *   Called by `L1ScrollMessenger` when a corresponding L2->L1 message (initiated by the L2 gateway) is relayed.
    *   Protected by `onlyCallByCounterpart` modifier (ensures `msg.sender` is `L1ScrollMessenger` and `xDomainMessageSender` is the L2 counterpart gateway).
    *   Unlock/transfer the asset to the L1 recipient.
    *   If `_data` is provided, may perform a callback to the recipient (`_doCallback`).
    *   Emit a `FinalizeWithdraw<Asset>` event.

*   **`onDropMessage(bytes calldata _message)` (for `IMessageDropCallback`):**
    *   Called by `L1ScrollMessenger` if a deposit message sent by this gateway was dropped.
    *   Decodes `_message` to identify the original L1 recipient and amount.
    *   Transfers the locked assets back to the original L1 recipient.
    *   Emits a `Refund<Asset>` event.

### Interaction with `L1ScrollMessenger`

*   **Deposits:** Gateways call `L1ScrollMessenger.sendMessage(counterpart, value, message, gasLimit, refundAddress)` to initiate the L1->L2 transfer.
*   **Withdrawals:** `L1ScrollMessenger` calls `gateway.finalizeWithdraw<Asset>(...)` to complete the L2->L1 transfer.
*   **Dropped Messages:** `L1ScrollMessenger` calls `gateway.onDropMessage(...)`.

### Interaction with `L1GatewayRouter`

*   **ERC20 Deposits:** L1 ERC20 gateways (like `L1StandardERC20Gateway`) are called by `L1GatewayRouter`. They then call back `L1GatewayRouter.requestERC20()` to get the tokens transferred from the user to themselves.

### Interaction with L2 Counterpart

*   The message sent via `L1ScrollMessenger` during a deposit is ultimately destined for the `finalizeDeposit<Asset>` function on the L2 counterpart gateway.
*   The call to `finalizeWithdraw<Asset>` on the L1 gateway is triggered by a message initiated by the `withdraw<Asset>` function on the L2 counterpart gateway.

## 4. General L2 Gateway Pattern (e.g., `L2ETHGateway.sol`, abstract `L2ERC20Gateway.sol`)

These contracts are the L2 counterparts to the L1 gateways, specialized for handling assets on L2. They also inherit from `ScrollGatewayBase`.

### Purpose

*   **Asset Handling on L2:** Mint/release assets on L2 when deposits from L1 are finalized. Burn/lock assets on L2 when users initiate withdrawals to L1.
*   **Message Formatting:** Construct the appropriate message payload for the L1 counterpart gateway.
*   **Communication Initiation (Withdrawals):** Send messages to their L1 counterpart via `L2ScrollMessenger` to inform L1 about a withdrawal.
*   **Communication Finalization (Deposits):** Receive messages from their L1 counterpart via `L2ScrollMessenger` to finalize a deposit.

### Common Functions

*   **`finalizeDeposit<Asset>(...)` (e.g., `finalizeDepositETH`, `finalizeDepositERC20`):**
    *   Called by `L2ScrollMessenger` when an L1->L2 message (initiated by the L1 gateway) is relayed to L2.
    *   Protected by `onlyCallByCounterpart`.
    *   Mint new L2 tokens (for ERC20s like "Scroll-wrapped ETH" or standard bridged ERC20s) or transfer ETH received by `L2ScrollMessenger` (which then forwards to `L2ETHGateway` which then forwards to user).
    *   If `_data` is provided, may perform a callback to the recipient (`_doCallback`).
    *   Emit a `FinalizeDeposit<Asset>` event.

*   **`withdraw<Asset>(...)` / `withdraw<Asset>AndCall(...)` (e.g., `withdrawETHAndCall`, `withdrawERC20AndCall`):**
    *   Usually called by `L2GatewayRouter` (or directly by users/DApps).
    *   Burn L2 tokens or take ETH from the user.
    *   Construct a message for the L1 gateway (e.g., `IL1ETHGateway.finalizeWithdrawETH.selector` or `IL1ERC20Gateway.finalizeWithdrawERC20.selector`) including details like L2 sender, L1 recipient, amount, and any auxiliary data.
    *   Call `L2ScrollMessenger.sendMessage()` with the L1 counterpart address, ETH value (if any, for gas on L1 or if bridging ETH itself), the constructed message, and gas limit.
    *   Emit a `Withdraw<Asset>` event.

### Interaction with `L2ScrollMessenger`

*   **Withdrawals:** Gateways call `L2ScrollMessenger.sendMessage(counterpart, value, message, gasLimit)` to initiate the L2->L1 transfer.
*   **Deposits:** `L2ScrollMessenger` calls `gateway.finalizeDeposit<Asset>(...)` to complete the L1->L2 transfer.

### Interaction with L1 Counterpart

*   The message sent via `L2ScrollMessenger` during a withdrawal is ultimately destined for the `finalizeWithdraw<Asset>` function on the L1 counterpart gateway.
*   The call to `finalizeDeposit<Asset>` on the L2 gateway is triggered by a message initiated by the `deposit<Asset>` function on the L1 counterpart gateway.

This structure creates a symmetric deposit/withdrawal flow, with routers simplifying user interaction and specific gateways handling asset-specific logic, all orchestrated by the respective L1/L2 ScrollMessengers.
