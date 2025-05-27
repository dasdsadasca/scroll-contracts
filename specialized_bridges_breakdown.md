# Specialized Bridge Contracts: Detailed Breakdown

This document provides a detailed breakdown of two specialized bridge systems in the Scroll protocol: the Batch Bridge and the Lido Bridge.

## A. Batch Bridge

### Overall Purpose

The Batch Bridge system is designed to optimize the process of depositing multiple ERC20 tokens (and ETH) from Layer 1 to Layer 2. Instead of each user initiating a separate L1->L2 transaction (which can be costly), users deposit their tokens into the `L1BatchBridgeGateway`. A "Keeper" (an off-chain actor) then triggers a function to process a "batch" of these deposits for a specific token. This batching aggregates multiple user deposits into fewer L1->L2 messages, significantly reducing the overall gas cost per deposit.

The `L1BatchBridgeGateway` collects individual deposits, and when a batch is ready (either by reaching a maximum number of transactions, a maximum total amount, or a maximum time delay), a Keeper calls `executeBatchDeposit`. This function sends two messages to L2 via `L1ScrollMessenger`:
1.  One message to the standard L1 ERC20 gateway (or L1 ETH gateway) to bridge the aggregated sum of tokens/ETH to the `L2BatchBridgeGateway`'s address on L2.
2.  A second message to the `L2BatchBridgeGateway` itself, containing the hash of the batch and other metadata, instructing it to finalize the batch deposit.

On L2, the `L2BatchBridgeGateway` receives the aggregated tokens/ETH. After receiving the finalization message and verifying the batch hash, another Keeper (or the same one) can call the `distribute` function on `L2BatchBridgeGateway`, providing the list of individual deposits. The L2 gateway then distributes the tokens/ETH to the respective recipients on L2.

### `BatchBridgeCodec.sol`

*   **Purpose:** A library solely used for encoding and decoding data related to batch bridge operations. It provides helper functions to pack and unpack information about token addresses, batch indices, user addresses, and amounts into `bytes32` nodes, which are then used to construct a hash chain representing the batch.
*   **Key Functions:**
    *   **`encodeInitialNode(address token, uint64 batchIndex)`:** Encodes the L1 token address and the batch index into a `bytes32` value. This serves as the starting point for the batch hash.
    *   **`encodeNode(address sender, uint96 amount)`:** Encodes an individual depositor's L1 address (`sender`) and the `amount` they deposited (after fees) into a `bytes32` value.
    *   **`decodeNode(bytes32 node)`:** Decodes a `bytes32` node back into the recipient's L2 address (`receiver`) and the `amount`.
    *   **`hash(bytes32 a, bytes32 b)`:** Computes `keccak256(abi.encodePacked(a, b))`, used to chain the hashes of individual deposits to form the overall batch hash.

### `L1BatchBridgeGateway.sol`

*   **Purpose:** This L1 contract manages the collection of ETH and ERC20 token deposits from users, organizes them into batches per token, and allows a Keeper to trigger the bridging of these aggregated batches to L2.
*   **Key State Variables:**
    *   **`configs` (mapping `address => BatchConfig`):** Stores batch configuration (fee per tx, min amount, max txs per batch, max delay, L2 gas limit for bridging) for each supported token (address(0) for ETH).
    *   **`batches` (mapping `address => mapping(uint256 => BatchState)`):** Stores the state of each batch for each token, indexed by batch index. `BatchState` includes `amount` (total in batch), `startTime`, `numDeposits`, and `hash` (the chained hash of all deposits in that batch).
    *   **`tokens` (mapping `address => TokenState`):** Stores the overall token state, including `pending` (total amount pending bridging), `currentBatchIndex` (index for new deposits), and `pendingBatchIndex` (next batch to be executed by keeper).
    *   **`feeVault` (`address`):** The address where collected deposit fees are sent.
    *   **`KEEPER_ROLE` (`bytes32`):** Access control role for calling `executeBatchDeposit`.
    *   **`counterpart` (immutable `address`):** Address of `L2BatchBridgeGateway`.
    *   **`router` (immutable `address`):** Address of `L1GatewayRouter`.
    *   **`messenger` (immutable `address`):** Address of `L1ScrollMessenger`.
    *   **`queue` (immutable `address`):** Address of `L1MessageQueueV1` (used for fee estimation).
*   **Key Functions:**
    *   **`depositETH()` / `depositERC20(address token, uint96 amount)`:**
        *   Public functions for users to deposit ETH or ERC20 tokens.
        *   They call the internal `_deposit` function.
        *   `_deposit` checks against `minAmountPerTx`, deducts `feeAmountPerTx`, updates `BatchState` (amount, numDeposits, hash using `BatchBridgeCodec`), and `TokenState` (pending amount). It also calls `_tryFinalizeCurrentBatch`.
    *   **`_tryFinalizeCurrentBatch(address token, BatchConfig memory cachedBatchConfig, TokenState memory cachedTokenState)` (internal):**
        *   Checks if the current batch for a token should be closed based on `maxTxsPerBatch` or `maxDelayPerBatch`. If so, increments `currentBatchIndex` for that token.
    *   **`executeBatchDeposit(address token)`:**
        *   Keeper-only function.
        *   Ensures there's a pending batch to process.
        *   Estimates fees for two L1->L2 messages (one for asset transfer, one for batch finalization data) using `L1MessageQueueV1.estimateCrossDomainMessageFee()`.
        *   Transfers accumulated user fees to `feeVault`.
        *   **Asset Transfer Message:**
            *   For ETH: Calls `L1ScrollMessenger.sendMessage()` to send the total ETH amount in the batch to the `L2BatchBridgeGateway` (counterpart) on L2.
            *   For ERC20s: Approves and calls `depositERC20()` on the standard L1 ERC20 gateway (obtained via `L1GatewayRouter`) to transfer the total token amount to the `L2BatchBridgeGateway` on L2.
        *   **Batch Finalization Message:** Calls `L1ScrollMessenger.sendMessage()` to send a message to `L2BatchBridgeGateway.finalizeBatchDeposit()` with the L1 token address, L2 token address, batch index, and batch hash.
        *   Updates `TokenState` (decrements `pending` amount, increments `pendingBatchIndex`).
        *   Emits `BatchDeposit`.
    *   **`setBatchConfig(address token, BatchConfig calldata newConfig)`:** Admin function to set or update batch parameters for a token.
*   **Interactions:**
    *   **Users:** Call `depositETH()` and `depositERC20()`.
    *   **`L1GatewayRouter`:** Queried by `executeBatchDeposit` to get the specific L1 ERC20 gateway for a token and its L2 counterpart address.
    *   **`L1ScrollMessenger`:** Used by `executeBatchDeposit` to send the two L1->L2 messages.
    *   **`FeeVault`:** Receives deposit fees.
    *   **Keepers:** Call `executeBatchDeposit()`.
    *   **`L1MessageQueueV1`:** Used for estimating L1->L2 message fees.
    *   **`BatchBridgeCodec`:** Used internally in `_deposit` for hashing.

### `L2BatchBridgeGateway.sol`

*   **Purpose:** This L2 contract receives batched deposit information and the aggregated assets from its L1 counterpart. It verifies the integrity of the batch and allows a Keeper to distribute the individual amounts to the final recipients on L2.
*   **Key State Variables:**
    *   **`tokenMapping` (mapping `address => address`):** Maps L2 token addresses to their corresponding L1 token addresses. Populated upon the first `finalizeBatchDeposit` for a new L2 token.
    *   **`batchHashes` (mapping `address => mapping(uint256 => bytes32)`):** Stores the L1-computed batch hash for each L2 token and batch index, used for verification during distribution.
    *   **`failedAmount` (mapping `address => uint256`):** Tracks amounts for each token that failed to be distributed (e.g., if a recipient contract reverts).
    *   **`isDistributed` (mapping `bytes32 => bool`):** Tracks if a batch (identified by its hash) has already been distributed to prevent replays.
    *   **`KEEPER_ROLE` (`bytes32`):** Access control role for calling `distribute`.
    *   **`counterpart` (immutable `address`):** Address of `L1BatchBridgeGateway`.
    *   **`messenger` (immutable `address`):** Address of `L2ScrollMessenger`.
*   **Key Functions:**
    *   **`finalizeBatchDeposit(address l1Token, address l2Token, uint256 batchIndex, bytes32 hash)`:**
        *   Called by `L2ScrollMessenger` when the batch finalization message from `L1BatchBridgeGateway` is relayed.
        *   Requires `msg.sender` to be `messenger` and `xDomainMessageSender` to be `counterpart`.
        *   If `l2Token` mapping to `l1Token` is not set, it sets it. Otherwise, verifies consistency.
        *   Stores the provided `hash` in `batchHashes[l2Token][batchIndex]`.
        *   Emits `FinalizeBatchDeposit`.
        *   The aggregated ETH for the batch is received by this contract via a `receive()` function (if ETH batch) or tokens are transferred to it by the standard L2 ERC20 Gateway when the asset bridging message from L1 is processed.
    *   **`distribute(address l2Token, uint64 batchIndex, bytes32[] memory nodes)`:**
        *   Keeper-only function.
        *   `nodes`: An array of `bytes32` encoded (sender_L1_address, amount_for_recipient) pairs, provided by the keeper off-chain.
        *   It reconstructs the batch hash using `BatchBridgeCodec.encodeInitialNode()` and iteratively hashing the provided `nodes`.
        *   Verifies this reconstructed hash against the stored `batchHashes[l2Token][batchIndex]`.
        *   Checks `!isDistributed` for this hash.
        *   If valid, iterates through `nodes`, decodes each to get recipient and amount using `BatchBridgeCodec.decodeNode()`.
        *   Transfers the amount to each recipient. If a transfer fails (e.g., recipient contract reverts), the amount is added to `failedAmount[l2Token]`.
        *   Marks the batch as distributed by setting `isDistributed[hash] = true`.
        *   Emits `BatchDistribute` and `DistributeFailed` for failed transfers.
    *   **`withdrawFailedAmount(address token, address receiver)`:** Admin function to retrieve tokens that failed to distribute.
*   **Interactions:**
    *   **`L1BatchBridgeGateway` (via `L2ScrollMessenger`):** `L2ScrollMessenger` calls `finalizeBatchDeposit()` on this contract. Receives assets (ETH directly, or ERC20s via standard L2 gateways which get them from `L2ScrollMessenger` which gets them from `L1BatchBridgeGateway` via standard L1 gateways).
    *   **Keepers:** Call `distribute()`.
    *   **L2 Recipients:** Receive tokens/ETH during `distribute()`.
    *   **`BatchBridgeCodec`:** Used in `distribute` for hashing and decoding.

## B. Lido Bridge

### Overall Purpose

The Lido Bridge is a specialized set of contracts designed specifically for bridging Lido's staked ETH tokens, primarily `wstETH` (Wrapped Staked Ether), between L1 and L2. It ensures that the unique properties of Lido tokens (like potential rebasing for stETH, though wstETH is non-rebasing) are handled correctly and provides administrative controls over the bridging process, such as enabling/disabling deposits and withdrawals.

### `LidoBridgeableTokens.sol` (Abstract)

*   **Purpose:** An abstract contract that serves as a base for both `L1LidoGateway` and `L2LidoGateway`. Its main role is to define and enforce that the gateway operates only for a specific, pre-configured pair of L1 and L2 Lido tokens.
*   **State:**
    *   **`l1Token` (immutable `address`):** The address of the Lido token on L1 (e.g., wstETH L1 address).
    *   **`l2Token` (immutable `address`):** The address of the corresponding Lido token on L2 (e.g., L2WstETHToken address).
*   **Modifiers:**
    *   **`onlySupportedL1Token(address _l1Token)`:** Requires `_l1Token` to match the stored `l1Token`.
    *   **`onlySupportedL2Token(address _l2Token)`:** Requires `_l2Token` to match the stored `l2Token`.

### `LidoGatewayManager.sol` (Abstract)

*   **Purpose:** An abstract contract, also inherited by `L1LidoGateway` and `L2LidoGateway`, that provides a role-based access control mechanism for managing the operational status of the bridge (deposits and withdrawals). It allows designated roles to enable or disable these functions.
*   **State:**
    *   **`State` struct (stored in `STATE_SLOT`):**
        *   `isDepositsEnabled` (`bool`): Whether deposits are currently allowed.
        *   `isWithdrawalsEnabled` (`bool`): Whether withdrawals are currently allowed.
        *   `roles` (mapping `bytes32 => EnumerableSetUpgradeable.AddressSet`): Maps role identifiers (e.g., `DEPOSITS_ENABLER_ROLE`) to a set of addresses holding that role.
*   **Key Functions (Role-Protected or Owner-only):**
    *   **`enableDeposits()` / `disableDeposits()`:** Called by addresses with `DEPOSITS_ENABLER_ROLE` / `DEPOSITS_DISABLER_ROLE` respectively.
    *   **`enableWithdrawals()` / `disableWithdrawals()`:** Called by addresses with `WITHDRAWALS_ENABLER_ROLE` / `WITHDRAWALS_DISABLER_ROLE` respectively.
    *   **`grantRole(bytes32 _role, address _account)` / `revokeRole(bytes32 _role, address _account)`:** Owner-only functions to manage role memberships.
    *   **View functions:** `isDepositsEnabled()`, `isWithdrawalsEnabled()`, `hasRole()`, `getRoleMember()`, `getRoleMemberCount()`.
*   **Modifiers:**
    *   `whenDepositsEnabled()`: Reverts if deposits are not enabled.
    *   `whenWithdrawalsEnabled()`: Reverts if withdrawals are not enabled.

### `L1LidoGateway.sol`

*   **Purpose:** The L1 component of the Lido Bridge. It handles deposits of the specific L1 Lido token (e.g., wstETH) from users and the finalization of withdrawals of this token from L2.
*   **Inheritance:** `L1ERC20Gateway` (provides base ERC20 gateway logic), `LidoBridgeableTokens` (defines L1/L2 token pair), `LidoGatewayManager` (provides admin controls).
*   **Key Functions (Overrides and Specific Logic):**
    *   It inherits standard deposit and finalize withdrawal functions from `L1ERC20Gateway`.
    *   **`_deposit(address _token, address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)` (internal override):**
        *   Applies `onlySupportedL1Token(_token)`, `onlyNonZeroAccount(_to)`, and `whenDepositsEnabled` modifiers.
        *   Ensures `_amount > 0`.
        *   Calls `_transferERC20In` (from `L1ERC20Gateway`) to pull tokens.
        *   Reverts if `_data.length != 0` (i.e., `depositAndCall` functionality is disallowed for Lido tokens through this gateway).
        *   Constructs the message for `L2LidoGateway.finalizeDepositERC20()`.
        *   Sends the message via `L1ScrollMessenger`.
    *   **`_beforeFinalizeWithdrawERC20(...)` (internal override):**
        *   Applies `onlySupportedL1Token`, `onlySupportedL2Token`, and `whenWithdrawalsEnabled` modifiers.
        *   Ensures `msg.value == 0`.
    *   **`_beforeDropMessage(...)` (internal override):**
        *   Applies `onlySupportedL1Token` and ensures `msg.value == 0`.
    *   **`getL2ERC20Address(address _l1Token)` (view override):** Returns the `l2Token` address if `_l1Token` is the supported one.
*   **Interactions:**
    *   **Users:** Deposit L1 Lido tokens.
    *   **`L1GatewayRouter`:** Users typically interact via the router, which then calls this gateway if it's registered for the specific Lido L1 token.
    *   **`L1ScrollMessenger`:** Used to send deposit messages to L2 and receive withdrawal finalization messages from L2.
    *   **`L2LidoGateway` (Counterpart):** Exchanges messages for deposit/withdrawal coordination.
    *   **Admins/Role Holders:** Interact with `LidoGatewayManager` functions to enable/disable operations or manage roles.

### `L2LidoGateway.sol`

*   **Purpose:** The L2 component of the Lido Bridge. It handles the finalization of deposits (minting L2 Lido tokens) and initiates withdrawals of L2 Lido tokens to L1.
*   **Inheritance:** `L2ERC20Gateway` (provides base L2 ERC20 gateway logic), `LidoBridgeableTokens`, `LidoGatewayManager`.
*   **Key Functions (Overrides and Specific Logic):**
    *   **`finalizeDepositERC20(address _l1Token, address _l2Token, address _from, address _to, uint256 _amount, bytes calldata _data)` (external override):**
        *   Called by `L2ScrollMessenger` (originating from `L1LidoGateway`).
        *   Applies `onlyCallByCounterpart`, `nonReentrant`, `onlySupportedL1Token`, `onlySupportedL2Token`, and `whenDepositsEnabled` modifiers.
        *   Ensures `msg.value == 0` and `_data.length == 0`.
        *   Calls `IScrollERC20Upgradeable(l2Token).mint(_to, _amount)` to mint the L2 representation of the Lido token (e.g., `L2WstETHToken`).
    *   **`_withdraw(address _l2TokenAddr, address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)` (internal override):**
        *   Called internally by public `withdrawERC20AndCall` (from base `L2ERC20Gateway`).
        *   Applies `nonReentrant`, `onlySupportedL2Token(_l2TokenAddr)`, `onlyNonZeroAccount(_to)`, and `whenWithdrawalsEnabled` modifiers.
        *   Ensures `_amount > 0`.
        *   If called via `L2GatewayRouter`, extracts original sender from `_data`.
        *   Reverts if (remaining) `_data.length != 0` (disallowing `withdrawAndCall`).
        *   Calls `IScrollERC20Upgradeable(l2Token).burn(_from, _amount)` to burn the L2 Lido tokens.
        *   Constructs the message for `L1LidoGateway.finalizeWithdrawERC20()`.
        *   Sends the message via `L2ScrollMessenger`.
    *   **`getL1ERC20Address(address _l2TokenAddr)` / `getL2ERC20Address(address _l1TokenAddr)` (view overrides):** Return counterpart token addresses if the provided token is the supported one.
*   **Interactions:**
    *   **`L1LidoGateway` (via `L2ScrollMessenger`):** `L2ScrollMessenger` calls `finalizeDepositERC20()` on this contract.
    *   **L2 Users:** Initiate withdrawals of L2 Lido tokens (often via `L2GatewayRouter`).
    *   **`L2ScrollMessenger`:** Used to send withdrawal messages to L1.
    *   **`L2WstETHToken` (or other L2 Lido token):** Calls `mint()` during deposit finalization and `burn()` during withdrawal initiation.
    *   **Admins/Role Holders:** Interact with `LidoGatewayManager` functions.

### `L2WstETHToken.sol`

*   **Purpose:** The L2 contract representing Wrapped Staked Ether (wstETH). It is a standard ERC20 token with minting/burning controlled by the `L2LidoGateway`.
*   **Inheritance:** `ScrollStandardERC20` (which itself inherits `ERC20PermitUpgradeable`).
*   **Key Feature (Override):**
    *   **`permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`:** Overrides the standard `ERC20PermitUpgradeable.permit` function. The key modification is the use of `SignatureCheckerUpgradeable.isValidSignatureNow` to validate the signature. This allows the `owner` to be a contract that supports ERC-1271 signature verification, making the permit functionality more flexible for smart contract wallets.
*   **Standard `IScrollERC20Upgradeable` functions:** `mint()`, `burn()`, `gateway`, `counterpart` (set during its own initialization, where `gateway` would be `L2LidoGateway`).

This detailed breakdown covers the architecture and key components of the Batch Bridge and Lido Bridge systems.
