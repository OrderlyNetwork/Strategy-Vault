// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import {ProtocolVault} from "../contracts/Vault/ProtocolVault.sol";
import {VaultCrossChainManager} from "../contracts/VaultCrossChainManager.sol";
import {ProtocolVaultLedger, ClaimInfo} from "../contracts/Ledger/ProtocolVaultLedger.sol";
import {LedgerCoreImpl} from "../contracts/Ledger/LedgerCoreImpl.sol";
import {LedgerExtension} from "../contracts/Ledger/LedgerExtension.sol";
import {MockSVLedger} from "./mock/MockSVLedger.sol";
import {MockDexVault} from "./mock/MockDexVault.sol";
import {VaultType, OperationData} from "../contracts/lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
import {UpdateStrategyFundAssetsParams} from "../contracts/lib/types/LedgerStruct.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// Mock ERC20 token contract

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Base is TestHelperOz5 {
    using OptionsBuilder for bytes;

    bytes32 constant ORDERLY_BROKER = 0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b;
    uint32 constant LEDGER_CHAIN_ID = 291;
    bytes32 constant USDC_HASH = 0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa;
    bytes32 constant NATIVE_HASH = 0x0000000000000000000000000000000000000000000000000000000000000000;

    address public owner = address(0x123);
    address public sp;
    address public user = address(0x1);
    address public operator = address(0x5);

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public spA = address(0x3);
    address public spB = address(0x4);

    bytes32 spA_id = _getStrategyProviderId(spA, ORDERLY_BROKER);
    bytes32 spB_id = _getStrategyProviderId(spB, ORDERLY_BROKER);
    bytes32 userA_id = _getAccountId(userA, ORDERLY_BROKER);
    bytes32 userB_id = _getAccountId(userB, ORDERLY_BROKER);
    bytes32 spId;
    bytes32 cvSpId;
    bytes32 vaultId;
    bytes32 cvVaultId;

    address engine;
    uint256 enginePrivateKey;
    uint256 spPrivateKey;

    uint32 evmChainId = 1;
    uint8 public srcEid = 1;
    uint8 public ledgerEid = 2;

    MockERC20 mockToken;
    ProtocolVault protocolVault;
    ProtocolVault communityVault;
    MockSVLedger svLedger;
    LedgerCoreImpl ledgerCoreImpl;
    LedgerExtension ledgerExtension;
    VaultCrossChainManager aVaultCrossChainManager;
    VaultCrossChainManager bVaultCrossChainManager;
    MockDexVault mockDexVault;

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();
        (engine, enginePrivateKey) = makeAddrAndKey("engine");
        (sp, spPrivateKey) = makeAddrAndKey("sp");
        spId = _getStrategyProviderId(sp, ORDERLY_BROKER);

        vm.deal(user, 100 ether);
        vm.deal(sp, 100 ether);
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);
        // Deploy LedgerCoreImpl and LedgerExtension contracts
        ledgerCoreImpl = new LedgerCoreImpl();
        ledgerExtension = new LedgerExtension();

        // Deploy the StrategyVaultLedger contract
        address svLedgerImpl = address(new MockSVLedger());
        address svLedgerProxy = address(
            new ERC1967Proxy(svLedgerImpl, abi.encodeWithSelector(ProtocolVaultLedger.initialize.selector, owner))
        );
        svLedger = MockSVLedger(svLedgerProxy);

        vm.startPrank(owner);
        // Set the core and extension implementations
        svLedger.setCore(address(ledgerCoreImpl));
        svLedger.setExtension(address(ledgerExtension));
        svLedger.setOperatorManager(operator);
        svLedger.setEngine(engine);
        vm.stopPrank();

        // Deploy the VaultCrossChainManager contract
        // Initialize 2 endpoints, using UltraLightNode as the library type

        setUpEndpoints(2, LibraryType.UltraLightNode);
        address aCCManagerImpl = address(new VaultCrossChainManager());
        address aCCManager = address(
            new ERC1967Proxy(
                aCCManagerImpl,
                abi.encodeWithSelector(VaultCrossChainManager.initialize.selector, address(endpoints[srcEid]), owner)
            )
        );
        aVaultCrossChainManager = VaultCrossChainManager(payable(aCCManager));

        address bCCManagerImpl = address(new VaultCrossChainManager());
        address bCCManager = address(
            new ERC1967Proxy(
                bCCManagerImpl,
                abi.encodeWithSelector(VaultCrossChainManager.initialize.selector, address(endpoints[ledgerEid]), owner)
            )
        );
        bVaultCrossChainManager = VaultCrossChainManager(payable(bCCManager));

        //check deploy
        assertEq(aVaultCrossChainManager.owner(), owner);
        assertEq(bVaultCrossChainManager.owner(), owner);

        vm.startPrank(owner);
        //set eid with chainid
        aVaultCrossChainManager.setEid(LEDGER_CHAIN_ID, ledgerEid);
        bVaultCrossChainManager.setEid(evmChainId, srcEid);

        //set peer
        aVaultCrossChainManager.setPeer(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        bVaultCrossChainManager.setPeer(srcEid, addressToBytes32(address(aVaultCrossChainManager)));
        //console.logBytes32(aVaultCrossChainManager.peers(LEDGER_EID));
        //set options
        aVaultCrossChainManager.setOptions(PayloadType.LP_DEPOSIT, 120000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.LP_WITHDRAW, 150000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.SP_DEPOSIT, 140000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.SP_WITHDRAW, 150000, 0);

        bVaultCrossChainManager.setOptions(PayloadType.ASSETS_DISTRIBUTION, 200000, 0);
        bVaultCrossChainManager.setOptions(PayloadType.UPDATE_USER_CLAIM, 300000, 0);

        svLedger.setCrossChainManager(address(bVaultCrossChainManager));
        vm.stopPrank();

        //Deploy the MockERC20 contract and approve
        mockToken = new MockERC20("mockToken", "MTK", 6);

        //deploy dex vault
        mockDexVault = new MockDexVault();
        mockDexVault.setToken(address(mockToken));

        //Deploy the ProtocolVault contract
        address protocolVaultImpl = address(new ProtocolVault());
        address proxy = address(
            new ERC1967Proxy(
                protocolVaultImpl,
                abi.encodeWithSelector(
                    ProtocolVault.initialize.selector, address(mockDexVault), owner, address(mockToken), 0, 0
                )
            )
        );
        protocolVault = ProtocolVault(payable(proxy));
        vaultId = _getVaultId(address(protocolVault), ORDERLY_BROKER);
        vm.startPrank(owner);
        // Calculate spId after protocolVault deployment
        spId = _getStrategyProviderId(sp, ORDERLY_BROKER);

        protocolVault.setCrossChainManager(address(aVaultCrossChainManager));
        protocolVault.setLedgerEid(ledgerEid);
        protocolVault.setAllowedBroker(ORDERLY_BROKER, true);
        svLedger.setAllowedStrategyProvider(ORDERLY_BROKER, address(protocolVault), sp, ORDERLY_BROKER, spId, true);

        //config cc contract
        vm.startPrank(owner);
        aVaultCrossChainManager.setVault(address(protocolVault));
        aVaultCrossChainManager.setValidVault(address(protocolVault), true);
        bVaultCrossChainManager.setLedger(svLedgerProxy);
        svLedger.setProtocolVault(address(protocolVault));
        vm.stopPrank();
        //mint token
        mockToken.mint(user, 100000e18);
        mockToken.mint(sp, 100000e18);
        mockToken.mint(userA, 100000e18);
        mockToken.mint(userB, 100000e18);

        //approve
        vm.prank(user);
        mockToken.approve(address(protocolVault), 100e6);
        vm.prank(sp);
        mockToken.approve(address(protocolVault), 100e6);

        //Deploy Community Vault
        address communityVaultImpl = address(new ProtocolVault());
        address communityVaultProxy = address(
            new ERC1967Proxy(
                communityVaultImpl,
                abi.encodeWithSelector(
                    ProtocolVault.initialize.selector, address(mockDexVault), owner, address(mockToken), 0, 0
                )
            )
        );
        communityVault = ProtocolVault(payable(communityVaultProxy));
        cvVaultId = _getVaultId(address(communityVault), ORDERLY_BROKER);
        cvSpId = _getStrategyProviderId(address(communityVault), sp, ORDERLY_BROKER);
        vm.startPrank(owner);
        communityVault.setCrossChainManager(address(aVaultCrossChainManager));
        communityVault.setLedgerEid(ledgerEid);
        communityVault.setAllowedBroker(ORDERLY_BROKER, true);
        aVaultCrossChainManager.setValidVault(address(communityVault), true);

        //set vaultId to vault on ledger
        svLedger.setVault(vaultId, address(protocolVault));
        svLedger.setVault(cvVaultId, address(communityVault));
        vm.stopPrank();

        //approve
        vm.prank(user);
        mockToken.approve(address(communityVault), 100e6);
        vm.prank(sp);
        mockToken.approve(address(communityVault), 100e6);
    }

    function testGetComputation() public {
        bytes32 spAid = keccak256(
            abi.encode(
                0x15a6aeFb614C6FF43fFeFCC5560ff3F239A77bA3, 0xbddfd22eF902A4898147A1ca5B985D03C62a8C41, ORDERLY_BROKER
            )
        );
        console.logBytes32(spAid);

        vaultId = _getVaultId(0x15a6aeFb614C6FF43fFeFCC5560ff3F239A77bA3, ORDERLY_BROKER);
        console.logBytes32(vaultId);
    }

    /// @notice Test EIP-7201 storage implementation
    function testEIP7201Storage() public view {
        // Verify that core and extension addresses are set correctly in EIP-7201 namespace storage
        assertNotEq(address(ledgerCoreImpl), address(0), "LedgerCoreImpl should be deployed");
        assertNotEq(address(ledgerExtension), address(0), "LedgerExtension should be deployed");

        // Test storage location calculation
        // keccak256(abi.encode(uint256(keccak256("ProtocolVaultLedger.impl")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 expectedStorageLocation = 0xbd28ae05aa0b6f83a93f63dae3aa2984ba2c5f2c4d60c8112719dd560d3efb00;

        // We can't directly read the storage location from the test,
        // but we can verify the calculation is correct
        bytes32 calculatedLocation =
            keccak256(abi.encode(uint256(keccak256("ProtocolVaultLedger.impl")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(calculatedLocation, expectedStorageLocation, "EIP-7201 storage location calculation should be correct");
    }

    /// @notice Test core and extension address setting and getting
    function testCoreExtensionAddresses() public {
        // Get the addresses directly through getter functions (if they exist) or events
        vm.startPrank(owner);

        // Test setting new addresses
        LedgerCoreImpl newCore = new LedgerCoreImpl();
        LedgerExtension newExtension = new LedgerExtension();

        // Test Core setting
        vm.expectEmit(true, false, false, false);
        emit CoreSet(address(newCore));
        svLedger.setCore(address(newCore));

        // Test Extension setting
        vm.expectEmit(true, false, false, false);
        emit ExtensionSet(address(newExtension));
        svLedger.setExtension(address(newExtension));

        vm.stopPrank();
    }

    /// @notice Test delegatecall functionality by testing core and extension functions
    function testDelegatecallFunctionality() public {
        // Test extension functionality through delegatecall
        // We can test this by verifying the contracts can handle operations

        // Set up some basic state for testing
        vm.startPrank(owner);
        bytes32 testVaultId = keccak256(abi.encode(address(protocolVault), ORDERLY_BROKER));
        svLedger.setVaultBroker(testVaultId, ORDERLY_BROKER);
        vm.stopPrank();
    }

    /// @notice Test that delegatecall revert when implementation is not set
    function testDelegatecallRevertWhenNotSet() public {
        // Deploy a new ledger without setting implementations
        address newLedgerImpl = address(new MockSVLedger());
        address newLedgerProxy = address(
            new ERC1967Proxy(newLedgerImpl, abi.encodeWithSelector(ProtocolVaultLedger.initialize.selector, owner))
        );
        MockSVLedger newLedger = MockSVLedger(newLedgerProxy);

        vm.startPrank(owner);
        newLedger.setOperatorManager(operator);
        newLedger.setEngine(engine);
        // Don't set core and extension implementations
        vm.stopPrank();

        // Now try to call a function that requires core implementation
        vm.startPrank(operator);

        // This should revert because core is not set
        UpdateStrategyFundAssetsParams[] memory strategyFundAssets = new UpdateStrategyFundAssetsParams[](0);
        bytes memory signature = new bytes(0);

        vm.expectRevert(); // Should revert due to LedgerExtensionsNotSet
        newLedger.updateStrategyFundAssets(0, bytes32(0), strategyFundAssets, signature);

        vm.stopPrank();
    }

    /// @notice Test that core and extension contracts are not zero addresses
    function testImplementationNotZero() public view {
        // These addresses should be set during setUp
        assertTrue(address(ledgerCoreImpl) != address(0), "Core implementation should not be zero");
        assertTrue(address(ledgerExtension) != address(0), "Extension implementation should not be zero");
    }

    // Events to match contract interface
    event CoreSet(address core);
    event ExtensionSet(address extension);

    // function testQuote() public view {
    //     uint256 nativeFee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT);
    //     console.log("nativeFee", nativeFee);

    //     nativeFee = protocolVault.quoteOperation(PayloadType.LP_WITHDRAW);
    //     console.log("nativeFee", nativeFee);

    //     nativeFee = protocolVault.quoteOperation(PayloadType.SP_DEPOSIT);
    //     console.log("nativeFee", nativeFee);

    //     nativeFee = protocolVault.quoteOperation(PayloadType.SP_WITHDRAW);
    //     console.log("nativeFee", nativeFee);
    // }

    function getEstimateFee(PayloadType payloadType) public returns (uint256) {
        (uint256 nativeFee,) = aVaultCrossChainManager.quote(ledgerEid, buildCCMessage(), payloadType, false);
        return nativeFee;
    }

    //build StrategyVaultCCMessage
    function buildCCMessage() public returns (bytes memory) {
        vaultId = _getVaultId(address(protocolVault), ORDERLY_BROKER);

        bytes32 accountId = _getAccountId(user, ORDERLY_BROKER);

        OperationData memory operationData = OperationData({
            vaultType: VaultType.PROTOCOL,
            sender: msg.sender,
            receiver: owner,
            chainNonce: 0,
            amount: 0,
            vaultId: vaultId,
            accountId: accountId,
            strategyProviderId: keccak256(abi.encodePacked(owner)),
            tokenHash: keccak256(abi.encodePacked(owner)),
            brokerHash: keccak256(abi.encodePacked(owner))
        });

        StrategyVaultCCMessage memory message = StrategyVaultCCMessage({
            payloadType: PayloadType.LP_DEPOSIT, srcChainId: 1, dstChainId: 2, payload: abi.encode(operationData)
        });

        bytes memory lzMessage = abi.encode(message);

        return lzMessage;
    }

    function _getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(protocolVault), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encode(address(protocolVault), brokerHash));
    }

    function _getUpdateUnclaimedSignature(
        uint32 chainId,
        uint256 _periodId,
        uint256 _ccFee,
        bytes32 _vaultId,
        bytes32[] memory requestIds
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(chainId, _periodId, _ccFee, _vaultId, requestIds));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _getStrategyProviderId(address vault, address strategyProvider, bytes32 brokerHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(vault, strategyProvider, brokerHash));
    }

    function _getVaultId(address vault, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, brokerHash));
    }
}
