// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VaultAdapter} from "../contracts/VaultAdapter.sol";
import {VaultDepositFE} from "../contracts/interfaces/IDexVault.sol";
import {AdapterDeposit, RoleType} from "../contracts/lib/types/VaultStruct.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract VaultAdapterTest is Base {
    address public adapterOwner = address(0x123);
    address public adapterOperator = address(0x456);
    address public receiver = address(0x789);

    VaultAdapter vaultAdapterImpl;
    VaultAdapter vaultAdapter;

    uint256 recordId = 1;
    bytes32 tokenHash = USDC_HASH;

    function setUp() public override {
        super.setUp();

        // Deploy VaultAdapter implementation
        vaultAdapterImpl = new VaultAdapter();

        // Deploy proxy with implementation
        address proxy = address(
            new ERC1967Proxy(
                address(vaultAdapterImpl),
                abi.encodeWithSelector(
                    VaultAdapter.initialize.selector,
                    adapterOperator,
                    address(mockDexVault),
                    engine,
                    address(mockToken),
                    adapterOwner
                )
            )
        );

        vaultAdapter = VaultAdapter(payable(proxy));
        // Deposit ETH to adapter
        vm.deal(address(vaultAdapter), 5 ether);
        // Mint tokens to adapter
        mockToken.mint(address(vaultAdapter), 1000e6);
    }

    /*=========================================================================================
    *                                     DEPLOYMENT TESTS
    *=========================================================================================*/

    function testInitialize() public view {
        // Test initialization was successful
        assertEq(vaultAdapter.operator(), adapterOperator);
        assertEq(vaultAdapter.dexVault(), address(mockDexVault));
        assertEq(vaultAdapter.engine(), engine);
        assertEq(vaultAdapter.owner(), adapterOwner);

        // Check USDC token hash was mapped correctly
        assertEq(vaultAdapter.tokenHashToToken(USDC_HASH), address(mockToken));

        // Check Orderly broker is allowed
        assertTrue(vaultAdapter.isAllowedBroker(ORDERLY_BROKER));
    }

    /*=========================================================================================
    *                                    PERMISSION TESTS
    *=========================================================================================*/

    function testOnlyOperatorCanDeposit() public {
        // Create deposit params
        AdapterDeposit memory deposit =
            _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, recordId);
        bytes memory signature = _signDeposit(deposit);

        // Operator can call depositTo
        vm.prank(adapterOperator);
        vaultAdapter.depositTo(deposit, signature);

        // Non-operator cannot call depositTo
        vm.prank(adapterOwner);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Unauthorized()"))));
        vaultAdapter.depositTo(deposit, signature);

        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Unauthorized()"))));
        vaultAdapter.depositTo(deposit, signature);
    }

    function testOnlyOwnerCanSetConfig() public {
        // Owner can set operator
        vm.prank(adapterOwner);
        vaultAdapter.setOperator(address(0xdef));
        assertEq(vaultAdapter.operator(), address(0xdef));

        // Non-owner cannot set operator
        vm.prank(adapterOperator);
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), adapterOperator)
        );
        vaultAdapter.setOperator(address(0x111));

        // Owner can set dexVault
        vm.prank(adapterOwner);
        vaultAdapter.setDexVault(address(0x222));
        assertEq(vaultAdapter.dexVault(), address(0x222));

        // Owner can set engine
        vm.prank(adapterOwner);
        vaultAdapter.setEngine(address(0x333));
        assertEq(vaultAdapter.engine(), address(0x333));

        // Owner can set broker status
        bytes32 newBrokerHash = keccak256("new_broker");
        vm.prank(adapterOwner);
        vaultAdapter.setAllowedBroker(newBrokerHash, true);
        assertTrue(vaultAdapter.isAllowedBroker(newBrokerHash));

        // Owner can set token hash mapping
        bytes32 newTokenHash = keccak256("new_token");
        address newToken = address(0x444);
        vm.prank(adapterOwner);
        vaultAdapter.setAllowedTokenHashToToken(newTokenHash, newToken);
        assertEq(vaultAdapter.tokenHashToToken(newTokenHash), newToken);
    }

    function testWithdrawNativeToken() public {
        // Send native tokens to the contract
        vm.deal(address(vaultAdapter), 1 ether);

        address payable recipient = payable(address(0xdef));
        uint256 balanceBefore = recipient.balance;

        // Owner can withdraw native tokens
        vm.prank(adapterOwner);
        vaultAdapter.withdrawNativeToken(recipient, 0.5 ether);

        assertEq(recipient.balance - balanceBefore, 0.5 ether);
        assertEq(address(vaultAdapter).balance, 0.5 ether);

        // Non-owner cannot withdraw native tokens
        vm.prank(adapterOperator);
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), adapterOperator)
        );
        vaultAdapter.withdrawNativeToken(recipient, 0.5 ether);
    }

    /*=========================================================================================
    *                                   DEPOSIT FUNCTIONALITY TESTS
    *=========================================================================================*/

    function testDepositTo() public {
        // Create deposit params for LP
        AdapterDeposit memory depositLP = _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, 1);
        bytes memory signatureLP = _signDeposit(depositLP);

        // Perform LP deposit
        vm.prank(adapterOperator);
        vaultAdapter.depositTo(depositLP, signatureLP);

        // Check record has been marked as handled
        assertTrue(vaultAdapter.isRecordHandled(1));
        assertEq(mockDexVault.amount(), 100e6);

        // Create deposit params for SP
        AdapterDeposit memory depositSP = _createDeposit(RoleType.SP, receiver, 200e6, ORDERLY_BROKER, USDC_HASH, 2);
        bytes memory signatureSP = _signDeposit(depositSP);

        // Perform SP deposit
        vm.prank(adapterOperator);
        vaultAdapter.depositTo(depositSP, signatureSP);

        // Check record has been marked as handled
        assertTrue(vaultAdapter.isRecordHandled(2));
        assertEq(mockDexVault.amount(), 300e6);
        assertEq(mockToken.allowance(address(vaultAdapter), address(mockDexVault)), 0);
    }

    function testDepositNative() public {
        // Create deposit params for LP with native token
        AdapterDeposit memory depositLP =
            _createDeposit(RoleType.LP, receiver, 1 ether, ORDERLY_BROKER, NATIVE_HASH, 100);
        bytes memory signatureLP = _signDeposit(depositLP);

        // Prepare operator with native token
        
        uint256 balanceBefore = address(mockDexVault).balance;

        // Perform native deposit
        vm.prank(adapterOperator);
        vaultAdapter.depositNative(depositLP, signatureLP);

        // Check record has been marked as handled
        assertTrue(vaultAdapter.isRecordHandled(100));
        // Check native token balance
        assertEq(address(mockDexVault).balance, balanceBefore + 1 ether);

        // Create deposit params for SP with native token
        AdapterDeposit memory depositSP =
            _createDeposit(RoleType.SP, receiver, 0.5 ether, ORDERLY_BROKER, NATIVE_HASH, 101);
        bytes memory signatureSP = _signDeposit(depositSP);

        // Perform SP native deposit
        vm.prank(adapterOperator);
        vaultAdapter.depositNative(depositSP, signatureSP);

        // Check record has been marked as handled
        assertTrue(vaultAdapter.isRecordHandled(101));
        // Check native token balance
        assertEq(address(mockDexVault).balance, balanceBefore + 1.5 ether);
    }

    function testRevertDepositNativeNotOperator() public {
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 1 ether, ORDERLY_BROKER, NATIVE_HASH, 102);
        bytes memory signature = _signDeposit(deposit);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Unauthorized()"))));
        vaultAdapter.depositNative(deposit, signature);
    }

    function testRevertDepositNativeDuplicateRecord() public {
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 1 ether, ORDERLY_BROKER, NATIVE_HASH, 104);
        bytes memory signature = _signDeposit(deposit);

        
        vm.startPrank(adapterOperator);

        vaultAdapter.depositNative(deposit, signature);

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("RecordAlreadyHandled(uint256)")), 104));
        vaultAdapter.depositNative(deposit, signature);

        vm.stopPrank();
    }

    function testRevertDepositNativeInvalidBroker() public {
        bytes32 invalidBrokerHash = keccak256("invalid_broker");
        AdapterDeposit memory deposit =
            _createDeposit(RoleType.LP, receiver, 1 ether, invalidBrokerHash, NATIVE_HASH, 105);
        bytes memory signature = _signDeposit(deposit);

        vm.deal(adapterOperator, 1 ether);
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("BrokerNotAllowed()"))));
        vaultAdapter.depositNative(deposit, signature);
    }

    function testRevertDepositNativeInvalidSignature() public {
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 1 ether, ORDERLY_BROKER, NATIVE_HASH, 107);

        // Create invalid signature
        (, uint256 randomKey) = makeAddrAndKey("random");
        bytes32 messageHash = keccak256(abi.encode(deposit, block.chainid));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.deal(adapterOperator, 1 ether);
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidSigner()"))));
        vaultAdapter.depositNative(deposit, invalidSignature);
    }

    function testRevertDepositToInvalidTokenHash() public {
        // Create deposit with invalid token hash
        bytes32 invalidTokenHash = keccak256("invalid_token");
        AdapterDeposit memory deposit =
            _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, invalidTokenHash, 3);
        bytes memory signature = _signDeposit(deposit);

        // Should revert with InvalidTokenHash
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidTokenHash()"))));
        vaultAdapter.depositTo(deposit, signature);
    }

    function testRevertDepositToDuplicateRecord() public {
        // Create deposit
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, 4);
        bytes memory signature = _signDeposit(deposit);

        // First deposit succeeds
        vm.prank(adapterOperator);
        vaultAdapter.depositTo(deposit, signature);

        // Second deposit with same recordId should fail
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("RecordAlreadyHandled(uint256)")), 4));
        vaultAdapter.depositTo(deposit, signature);
    }

    function testRevertDepositToInvalidBroker() public {
        // Create deposit with invalid broker hash
        bytes32 invalidBrokerHash = keccak256("invalid_broker");
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 100e6, invalidBrokerHash, USDC_HASH, 6);
        bytes memory signature = _signDeposit(deposit);

        // Should fail with BrokerNotAllowed
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("BrokerNotAllowed()"))));
        vaultAdapter.depositTo(deposit, signature);
    }

    function testRevertDepositToInvalidSignature() public {
        // Create deposit
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, 7);

        // Create invalid signature (signed by wrong key)
        (, uint256 randomKey) = makeAddrAndKey("random");
        bytes32 messageHash = keccak256(abi.encode(deposit, block.chainid));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Should fail with InvalidSigner
        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidSigner()"))));
        vaultAdapter.depositTo(deposit, invalidSignature);
    }

    /*=========================================================================================
    *                                  CONFIG UPDATE TESTS
    *=========================================================================================*/

    function testSetOperator() public {
        address newOperator = address(0xdef);

        vm.prank(adapterOwner);
        vaultAdapter.setOperator(newOperator);

        assertEq(vaultAdapter.operator(), newOperator);

        // Create deposit
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, 8);
        bytes memory signature = _signDeposit(deposit);

        // New operator can call depositTo
        vm.prank(newOperator);
        vaultAdapter.depositTo(deposit, signature);

        // Old operator can no longer call depositTo
        AdapterDeposit memory deposit2 = _createDeposit(RoleType.LP, receiver, 100e6, ORDERLY_BROKER, USDC_HASH, 9);
        bytes memory signature2 = _signDeposit(deposit2);

        vm.prank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Unauthorized()"))));
        vaultAdapter.depositTo(deposit2, signature2);
    }

    function testSetDexVault() public {
        address newDexVault = address(0x123);

        vm.prank(adapterOwner);
        vaultAdapter.setDexVault(newDexVault);

        assertEq(vaultAdapter.dexVault(), newDexVault);
    }

    function testSetEngine() public {
        address newEngine = address(0x333);

        vm.prank(adapterOwner);
        vaultAdapter.setEngine(newEngine);

        assertEq(vaultAdapter.engine(), newEngine);
    }

    function testSetTokenHashToToken() public {
        bytes32 newTokenHash = keccak256("new_token");
        address newToken = address(0x444);

        vm.prank(adapterOwner);
        vaultAdapter.setAllowedTokenHashToToken(newTokenHash, newToken);

        assertEq(vaultAdapter.tokenHashToToken(newTokenHash), newToken);
    }

    function testSetAllowedBroker() public {
        bytes32 newBrokerHash = keccak256("new_broker");

        vm.prank(adapterOwner);
        vaultAdapter.setAllowedBroker(newBrokerHash, true);

        assertTrue(vaultAdapter.isAllowedBroker(newBrokerHash));

        // Create deposit with the new broker
        AdapterDeposit memory deposit = _createDeposit(RoleType.LP, receiver, 100e6, newBrokerHash, USDC_HASH, 11);
        bytes memory signature = _signDeposit(deposit);

        // Deposit should succeed with the new broker
        vm.startPrank(adapterOperator);
        vaultAdapter.depositTo(deposit, signature);
        vm.stopPrank();

        // Disable the broker
        vm.prank(adapterOwner);
        vaultAdapter.setAllowedBroker(newBrokerHash, false);

        assertFalse(vaultAdapter.isAllowedBroker(newBrokerHash));

        // Create another deposit with the now-disallowed broker
        AdapterDeposit memory deposit2 = _createDeposit(RoleType.LP, receiver, 100e6, newBrokerHash, USDC_HASH, 12);
        bytes memory signature2 = _signDeposit(deposit2);

        // Deposit should fail with BrokerNotAllowed
        vm.startPrank(adapterOperator);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("BrokerNotAllowed()"))));
        vaultAdapter.depositTo(deposit2, signature2);
        vm.stopPrank();
    }

    /*=========================================================================================
    *                                  HELPER FUNCTIONS
    *=========================================================================================*/

    function _createDeposit(
        RoleType roleType,
        address _receiver,
        uint128 amount,
        bytes32 brokerHash,
        bytes32 _tokenHash,
        uint256 _recordId
    ) internal pure returns (AdapterDeposit memory) {
        return AdapterDeposit({
            roleType: roleType,
            receiver: _receiver,
            amount: amount,
            brokerHash: brokerHash,
            tokenHash: _tokenHash,
            recordId: _recordId
        });
    }

    function _signDeposit(AdapterDeposit memory deposit) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(deposit, block.chainid));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        return abi.encodePacked(r, s, v);
    }
}
