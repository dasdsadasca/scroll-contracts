# L2GatewayRouter.sol: Detailed Explanation

## 1. Purpose and Function

`L2GatewayRouter.sol` is a smart contract deployed on the Layer 2 (L2) Scroll network. It serves as the **primary entry point for users wishing to initiate the withdrawal of ETH and ERC20 tokens from L2 back to Layer 1 (L1 Ethereum mainnet).** Similar to its L1 counterpart (`L1GatewayRouter`), its main goal is to streamline the withdrawal process for users by offering a single, unified interface.

Users interact with `L2GatewayRouter` to withdraw their assets. The router then intelligently **directs these withdrawal requests to the appropriate specific L2 gateway contract:**
*   For **ETH withdrawals**, it forwards the request to a designated `L2ETHGateway.sol` contract.
*   For **ERC20 token withdrawals**, it first checks if a custom L2 gateway is registered for that specific token. If one exists, it uses that custom `ERC20Gateway`. Otherwise, it routes the request to a `defaultERC20Gateway` (typically `L2StandardERC20Gateway.sol`).

In addition to handling withdrawals, `L2GatewayRouter.sol` also provides a utility function for users or other contracts to **query the corresponding L1 token address for a given L2 token address**. This is useful for applications that need to map L2 assets back to their L1 origins.

It's important to note that while the router initiates withdrawals, the actual process involves sending a message from L2 to L1 via the `L2ScrollMessenger`. The funds are then claimable on L1 after the L2 transaction batch containing the withdrawal is finalized on L1. The router itself does not handle the finalization of deposits from L1; that logic resides within the specific L2 gateway contracts.

## 2. Key Functions

Below are the key functions within `L2GatewayRouter.sol` and their descriptions:

*   **`initialize(address _ethGateway, address _defaultERC20Gateway)`**:
    *   An initializer function, likely protected by an `initializer` modifier and called once upon deployment.
    *   It sets up the core addresses for the router's operations on L2:
        *   `_ethGateway`: The address of the `L2ETHGateway` contract responsible for handling ETH withdrawals.
        *   `_defaultERC20Gateway`: The address of the default `L2StandardERC20Gateway` (or a similar contract) that handles ERC20 token withdrawals if no token-specific L2 gateway is registered.

*   **`withdrawETH(uint256 _amount, uint256 _gasLimit)`** and **`withdrawETH(address _to, uint256 _amount, uint256 _gasLimit)`**:
    *   These functions manage ETH withdrawals from L2 to L1.
    *   The first version initiates a withdrawal to the caller's address on L1.
    *   The second version allows specifying a different recipient address (`_to`) on L1.
    *   Both functions call the `withdrawETH` function on the `ethGateway` contract address (set during initialization). They forward the ETH (which is burned or escrowed by the `ethGateway`), the recipient address, and the `_gasLimit` intended for the L1 transaction that will claim the ETH.
    *   The `ethGateway` is responsible for burning/locking the L2 ETH and sending a message to L1 via `L2ScrollMessenger`.

*   **`withdrawERC20(address _token, uint256 _amount, uint256 _gasLimit)`** and **`withdrawERC20(address _token, address _to, uint256 _amount, uint256 _gasLimit)`**:
    *   These functions manage ERC20 token withdrawals from L2 to L1.
    *   `_token` specifies the L2 address of the ERC20 token being withdrawn.
    *   The first version withdraws tokens to the caller's address on L1.
    *   The second version allows specifying a different recipient (`_to`) on L1.
    *   They determine the correct L2 ERC20 gateway by calling `getERC20Gateway(_token)`.
    *   They then invoke the `withdrawERC20` function on the resolved gateway address, passing the token address, recipient, amount, and L1 gas limit.
    *   The chosen L2 ERC20 gateway handles the token burning/locking on L2 and sends a message to L1.

*   **`withdrawERC20AndCall(address _token, address _to, uint256 _amount, bytes memory _data, uint256 _gasLimit)`**:
    *   This function handles ERC20 token withdrawals with an additional arbitrary call to be executed on L1 after the bridged assets are claimed.
    *   `_token`: The L2 ERC20 token address.
    *   `_to`: The L1 recipient address, which will also be the target of the subsequent call on L1.
    *   `_amount`: The amount of tokens to withdraw.
    *   `_data`: The encoded calldata for the function to be executed on the `_to` address on L1.
    *   `_gasLimit`: The gas limit for the L1 transaction (covering both the withdrawal claim and the call).
    *   It resolves the appropriate `ERC20Gateway` using `getERC20Gateway(_token)`.
    *   It then calls `withdrawERC20AndCall` on the resolved gateway. This gateway will handle burning/locking the L2 tokens and instruct the `L2ScrollMessenger` to relay the withdrawal message along with the additional calldata for L1 execution.

*   **`getL1ERC20Address(address _l2Address)`**:
    *   A query function that retrieves the corresponding L1 token address for a given L2 ERC20 token address (`_l2Address`).
    *   It calls `getL1ERC20Address` on the `defaultERC20Gateway`. This implies the default L2 gateway (e.g., `L2StandardERC20Gateway`) holds or can access the mapping between L2 and L1 token addresses.

*   **`getERC20Gateway(address _token)`**:
    *   An internal view function that determines which L2 ERC20 gateway contract should handle a withdrawal for a specific L2 `_token`.
    *   It checks a mapping (`erc20Gateway`) for a token-specific L2 gateway address registered for `_token`.
    *   If found, that address is returned.
    *   Otherwise, it returns the address of the `defaultERC20Gateway`.

*   **Owner-restricted functions:**
    *   **`setETHGateway(address _ethGateway)`**: Allows the contract owner to update the address of the `L2ETHGateway`.
    *   **`setDefaultERC20Gateway(address _defaultERC20Gateway)`**: Allows the contract owner to update the address of the `defaultERC20Gateway`.
    *   **`setERC20Gateway(address _token, address _gateway)`**: Allows the contract owner to register or update a specific `ERC20Gateway` for a particular L2 `_token`. Setting `_gateway` to the zero address can unregister a specific gateway.
    *   These functions are vital for maintaining and upgrading the L2 gateway system.

*   **Functions that `revert("should never be called")`:**
    *   **`finalizeDepositETH(...)`**
    *   **`finalizeDepositERC20(...)`**
    *   **`finalizeDepositERC20AndCall(...)`**
    *   These functions exist in the `IL2GatewayRouter` interface (and possibly an abstract contract it inherits) to cover the full lifecycle of cross-chain asset movement. However, the *router* contract's responsibility is to *initiate* actions (like withdrawals on L2 or routing deposits on L1). The *finalization* of deposits on L2 (i.e., minting tokens or releasing ETH after an L1->L2 message) is handled by the specific L2 gateway contracts (`L2ETHGateway`, `L2StandardERC20Gateway`, etc.), not by the router. Thus, if these finalization functions were ever to be called on the router, it would indicate a misconfiguration or incorrect integration, so they revert.

All withdrawal functions in `L2GatewayRouter` result in the respective L2 gateway contract calling the `L2ScrollMessenger` to send a message to L1, initiating the process for the user to eventually claim their assets on Ethereum mainnet.
