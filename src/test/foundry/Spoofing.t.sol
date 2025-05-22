// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Interfaces and contracts for the PoC
import {IL1ScrollMessenger, IL1MessageQueueV2, IScrollChain, L2MessageProof} from "./L1ScrollMessengerInterfaces.sol";
import {FeeVault} from "./FeeVault.sol";
import {L2TargetContract} from "./L2TargetContract.sol";
import {DelegateAttackContract} from "./DelegateAttackContract.sol";

// Actual L1ScrollMessenger contract from the main codebase
import {L1ScrollMessenger} from "../../L1/L1ScrollMessenger.sol";
// Import ScrollMessengerBase to understand storage layout if needed for vm.store
// For now, DelegateAttackContract inherits it, so direct slot manipulation might not be needed.
import {ScrollMessengerBase} from "../../libraries/ScrollMessengerBase.sol";
import {ScrollConstants} from "../../libraries/constants/ScrollConstants.sol";


// Mock Contracts
contract MockL1MessageQueue is IL1MessageQueueV2 {
    struct AppendedMessage {
        address target;
        uint256 gasLimit;
        bytes message;
        uint256 value; // L1ScrollMessenger sends value to L1MessageQueue
    }
    AppendedMessage[] public appendedMessages;
    uint256 public nextMessageIndex;
    mapping(uint256 => uint256) public crossDomainMessageFee;

    function appendCrossDomainMessage(
        address target,
        uint256 gasLimit,
        bytes memory message
    ) external payable { // Made payable to match L1ScrollMessenger's call
        appendedMessages.push(AppendedMessage({
            target: target,
            gasLimit: gasLimit,
            message: message,
            value: msg.value // Capture the value sent by L1ScrollMessenger
        }));
        nextMessageIndex++;
    }

    function nextCrossDomainMessageIndex() external view returns (uint256) {
        return nextMessageIndex;
    }

    function estimateCrossDomainMessageFee(uint256 gasLimit)
        external
        view
        returns (uint256)
    {
        return crossDomainMessageFee[gasLimit]; // Allow setting mock fees
    }

    // Helper to get a specific message
    function getAppendedMessage(uint256 index) external view returns (AppendedMessage memory) {
        return appendedMessages[index];
    }
}

contract MockScrollChain is IScrollChain {
    mapping(uint256 => bool) public finalizedBatches;
    mapping(uint256 => bytes32) public withdrawRootsMap;

    function isBatchFinalized(uint256 batchIndex) external view returns (bool) {
        return finalizedBatches[batchIndex];
    }

    function withdrawRoots(uint256 batchIndex) external view returns (bytes32) {
        return withdrawRootsMap[batchIndex];
    }

    // Admin functions to set mock values
    function setBatchFinalized(uint256 batchIndex, bool status) external {
        finalizedBatches[batchIndex] = status;
    }

    function setWithdrawRoot(uint256 batchIndex, bytes32 root) external {
        withdrawRootsMap[batchIndex] = root;
    }
}


contract SpoofingTest is Test {
    // Actors
    address attackerEOA;
    L1ScrollMessenger l1ScrollMessengerContract; // Actual contract
    L2TargetContract l2TargetContract;
    DelegateAttackContract delegateAttackContract;
    FeeVault feeVault;
    MockL1MessageQueue mockL1MessageQueue;
    MockScrollChain mockScrollChain;

    // L2 counterpart address for L1ScrollMessenger initialization (dummy)
    address constant L2_COUNTERPART_ADDRESS = address(0x2222222222222222222222222222222222222222);
    // L1 Gateway Router address (dummy, required by L1ScrollMessenger constructor)
    address constant L1_GATEWAY_ROUTER_ADDRESS = address(0x3333333333333333333333333333333333333333);
     // L1 Alias of L2 Scroll Messenger (dummy, required by L1ScrollMessenger constructor)
    address constant L1_ALIAS_L2_SCROLL_MESSENGER = address(0x4444444444444444444444444444444444444444);


    function setUp() public {
        attackerEOA = vm.addr(1);
        vm.label(attackerEOA, "AttackerEOA");

        // 1. Deploy FeeVault
        feeVault = new FeeVault();
        vm.label(address(feeVault), "FeeVault");

        // 2. Deploy MockL1MessageQueue
        mockL1MessageQueue = new MockL1MessageQueue();
        vm.label(address(mockL1MessageQueue), "MockL1MessageQueue");

        // 3. Deploy MockScrollChain
        mockScrollChain = new MockScrollChain();
        vm.label(address(mockScrollChain), "MockScrollChain");
        // Initialize some default mock values
        mockScrollChain.setBatchFinalized(0, true); // Assume batch 0 is always finalized for simplicity
        mockScrollChain.setWithdrawRoot(0, bytes32(uint256(12345)));


        // 4. Deploy actual L1ScrollMessenger
        // Constructor: constructor(address _gatewayRouter, address _messageQueue, address _scrollChain, address _counterpart, address _feeVault, address _l1AliasOfL2ScrollMessenger)
        l1ScrollMessengerContract = new L1ScrollMessenger(
            L1_GATEWAY_ROUTER_ADDRESS, // _gatewayRouter (dummy)
            address(mockL1MessageQueue), // _messageQueue
            address(mockScrollChain),    // _scrollChain
            L2_COUNTERPART_ADDRESS,      // _counterpart (dummy L2 messenger)
            address(feeVault),           // _feeVault
            L1_ALIAS_L2_SCROLL_MESSENGER // _l1AliasOfL2ScrollMessenger (dummy)
        );
        vm.label(address(l1ScrollMessengerContract), "L1ScrollMessenger (Actual)");

        // 5. Deploy DelegateAttackContract
        // Constructor: constructor(address _counterpart, address _feeVault)
        // It needs to use the *same* counterpart and feeVault as the L1ScrollMessenger expects to find in its own storage
        // when sendMessage is delegatecalled.
        delegateAttackContract = new DelegateAttackContract(
            L2_COUNTERPART_ADDRESS, // This should match L1ScrollMessenger's counterpart
            address(feeVault)       // This should match L1ScrollMessenger's feeVault
        );
        vm.label(address(delegateAttackContract), "DelegateAttackContract");

        // 6. Deploy L2TargetContract
        // Constructor: constructor(address _l1ScrollMessengerAddress)
        // For the purpose of the PoC, on L2, the "authentic" L1ScrollMessenger address is address(l1ScrollMessengerContract)
        l2TargetContract = new L2TargetContract(address(l1ScrollMessengerContract));
        vm.label(address(l2TargetContract), "L2TargetContract");

        // Initial funding for attacker
        vm.deal(attackerEOA, 10 ether);
    }

    function testExploit_L1ScrollMessenger_Spoof() public {
        vm.startPrank(attackerEOA);

        // --- Setup & Initial state checks ---
        console.log("Initial L2TargetContract owner:", l2TargetContract.owner());
        assertEq(l2TargetContract.owner(), address(this), "Initial owner should be test contract (deployer)");
        assertEq(l1ScrollMessengerContract.counterpart(), L2_COUNTERPART_ADDRESS, "L1SM counterpart mismatch");
        assertEq(l1ScrollMessengerContract.feeVault(), address(feeVault), "L1SM feeVault mismatch");

        // Check DelegateAttackContract's storage (it inherited ScrollMessengerBase)
        // These values are crucial for the delegatecall to L1ScrollMessenger.sendMessage to work as intended
        assertEq(delegateAttackContract.counterpart(), L2_COUNTERPART_ADDRESS, "DelegateAC counterpart mismatch");
        assertEq(delegateAttackContract.feeVault(), address(feeVault), "DelegateAC feeVault mismatch");
        // Paused should be false, _status should be _NOT_ENTERED (1) by default from initializers
        assertEq(delegateAttackContract.paused(), false, "DelegateAC should not be paused");
        // Check reentrancy status using a public view function if available, or assume it's _NOT_ENTERED (1)
        // For ScrollMessengerBase, xDomainMessageSender is used as a reentrancy guard, init to DEFAULT_XDOMAIN_MESSAGE_SENDER
        assertEq(delegateAttackContract.xDomainMessageSender(), ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER, "DelegateAC xDomainMessageSender incorrect initial state");


        // --- 1. Attacker prepares the L2->L1 message to trigger the attack ---
        // This message, when relayed to L1, will call `triggerDelegateCallAttack` on `delegateAttackContract`.
        uint256 l2ToL1_messageNonce = 123; // Dummy nonce for this specific L2->L1 message

        // The _messageL2 for `sendMessage` will be `L2TargetContract.privilegedAction(address(l1ScrollMessengerContract))`
        // This is what L2TargetContract expects as the sender for it to succeed.
        bytes memory calldataForL2TargetPrivilegedAction = abi.encodeWithSelector(
            L2TargetContract.privilegedAction.selector,
            address(l1ScrollMessengerContract) // Crucially, we tell privilegedAction that L1ScrollMessenger is the sender
        );

        // Calldata for DelegateAttackContract.triggerDelegateCallAttack
        // function triggerDelegateCallAttack(
        //     address _l1ScrollMessenger, -> address(l1ScrollMessengerContract)
        //     address _targetL2,          -> address(l2TargetContract)
        //     uint256 _valueL2,           -> 0
        //     bytes memory _messageL2,    -> calldataForL2TargetPrivilegedAction
        //     uint256 _gasLimitL2,        -> 100_000
        //     address _refundAddress      -> attackerEOA (can be anything for PoC)
        // )
        bytes memory l2ToL1_calldataForDelegateAttack = abi.encodeWithSelector(
            DelegateAttackContract.triggerDelegateCallAttack.selector,
            address(l1ScrollMessengerContract),         // The actual L1ScrollMessenger we are making a delegatecall TO
            address(l2TargetContract),                  // The ultimate target on L2
            0,                                          // Value for the L2 call (sendMessage's `value` param)
            calldataForL2TargetPrivilegedAction,        // The message for the L2 call
            100_000,                                    // Gas limit for the L2 call
            attackerEOA                                 // Refund address for sendMessage
        );

        // --- 2. Simulate L1 Relayer executing `relayMessageWithProof` on L1ScrollMessenger ---
        // This `relayMessageWithProof` call will execute the `l2ToL1_calldataForDelegateAttack`
        // on `delegateAttackContract`.
        L2MessageProof memory proof;
        proof.batchIndex = 0; // Using the batchIndex we set as finalized in setUp
        proof.l2OracleRoot = bytes32(uint256(1)); // Dummy non-zero root
        proof.merkleProof = abi.encodePacked(bytes32(uint256(2))); // Dummy non-empty proof

        // The fee for relayMessageWithProof. This needs to cover the cost of appendCrossDomainMessage.
        // Let's ask L1ScrollMessenger what fee it expects for the *inner* L2 gas limit.
        uint256 estimatedFee = l1ScrollMessengerContract.estimateCrossDomainMessageFee(100_000);
        console.log("Estimated fee for L1ScrollMessenger.sendMessage:", estimatedFee);

        // AttackerEOA (or any relayer) calls L1ScrollMessenger.relayMessageWithProof
        // The `_from` is attackerEOA (who initiated the L2->L1 message)
        // The `_to` is delegateAttackContract (target of the L2->L1 message)
        // The `_message` is l2ToL1_calldataForDelegateAttack
        console.log("Simulating L1 Relayer executing relayMessageWithProof (EXPECTING REVERT)...");
        
        // --- EXPECT REVERT DUE TO MITIGATION ---
        // The delegatecall from DelegateAttackContract to L1ScrollMessenger.sendMessage
        // should now trigger the `require(address(this) == SELF, "L1SM: sender spoof via delegatecall")`.
        bytes memory expectedRevertMessage = bytes("L1SM: sender spoof via delegatecall");
        vm.expectRevert(expectedRevertMessage);

        l1ScrollMessengerContract.relayMessageWithProof{value: estimatedFee}(
            attackerEOA,                        // _from (original sender on L2)
            address(delegateAttackContract),    // _to (target contract on L1, our attack contract)
            0,                                  // _value (value with the L2->L1 message itself)
            l2ToL1_messageNonce,                // _nonce (nonce of the L2->L1 message)
            l2ToL1_calldataForDelegateAttack,   // _message (calldata for delegateAttackContract.triggerDelegateCallAttack)
            proof                               // _proof (dummy proof for L2->L1 message)
        );
        console.log("Attack attempt finished (reverted as expected).");

        // --- 3. Verify no spoofed message was queued ---
        // The message queue should be empty as the appendCrossDomainMessage call within L1ScrollMessenger._sendMessage
        // should not have been reached due to the revert.
        assertEq(mockL1MessageQueue.nextCrossDomainMessageIndex(), 0, "Message queue should be empty after reverted attack");

        // --- 4. Verify L2 State Unchanged ---
        // The owner of L2TargetContract should still be the original deployer (this test contract)
        console.log("L2TargetContract owner AFTER reverted attack:", l2TargetContract.owner());
        assertEq(l2TargetContract.owner(), address(this), "L2TargetContract owner should NOT have changed");
        
        // lastXDomainSender should be address(0) or its initial value, not l1ScrollMessengerContract
        console.log("L2TargetContract lastXDomainSender AFTER reverted attack:", l2TargetContract.lastXDomainSender());
        assertEq(l2TargetContract.lastXDomainSender(), address(0), "L2TargetContract lastXDomainSender should be address(0)");


        // --- Old assertions (should not pass anymore) ---
        // console.log("Verifying message queued in MockL1MessageQueue...");
        // assertEq(mockL1MessageQueue.nextCrossDomainMessageIndex(), 1, "Should be one message in queue");
        // MockL1MessageQueue.AppendedMessage memory queuedMsg = mockL1MessageQueue.getAppendedMessage(0);
        // (address xDomain_from, address xDomain_to, uint256 xDomain_value, uint256 xDomain_nonce, bytes memory xDomain_innerMessage) = 
        //     abi.decode(queuedMsg.message, (address, address, uint256, uint256, bytes));
        // assertEq(xDomain_from, address(l1ScrollMessengerContract), "Spoofed sender (_from) should be L1ScrollMessenger address");
        // assertEq(xDomain_to, address(l2TargetContract), "Queued message target should be L2TargetContract");
        // assertEq(xDomain_value, 0, "Queued message value should be 0");
        // assertEq(xDomain_nonce, 0, "Queued message nonce should be L1ScrollMessenger's first nonce");
        // assertEq(xDomain_innerMessage, calldataForL2TargetPrivilegedAction, "Inner message mismatch");
        // console.log("Simulating L2 Relayer executing the message on L2TargetContract...");
        // console.log("L2TargetContract owner BEFORE privilegedAction:", l2TargetContract.owner());
        // console.log("L2TargetContract lastXDomainSender BEFORE privilegedAction:", l2TargetContract.lastXDomainSender());
        // vm.prank(address(0xdeadbeef00000000000000000000000000000000)); 
        // l2TargetContract.privilegedAction(xDomain_from); 
        // console.log("L2TargetContract owner AFTER privilegedAction:", l2TargetContract.owner());
        // console.log("L2TargetContract lastXDomainSender AFTER privilegedAction:", l2TargetContract.lastXDomainSender());
        // assertEq(l2TargetContract.owner(), attackerEOA, "Attacker EOA should now own L2TargetContract");
        // assertEq(l2TargetContract.lastXDomainSender(), address(l1ScrollMessengerContract), "L2TargetContract should see L1ScrollMessenger as the xDomain sender");

        vm.stopPrank();
        console.log("Mitigation test successful: Exploit prevented!");
    }
}
