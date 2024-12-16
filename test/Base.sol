// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import {ProtocolVault} from "../contracts/ProtocolVault.sol";
import {VaultCrossChainManager} from "../contracts/VaultCrossChainManager.sol";
import {StrategyVaultLedger} from "../contracts/StrategyVaultLedger.sol";
import {MockSVLedger} from "./MockSVLedger.sol";
import {VaultType, OperationData} from "../contracts/lib/types/VaultStruct.sol";
import {PayloadType, StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";

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

    address public owner = address(0x123);
    address public sp = address(0x2);
    address public user = address(0x1);
    address public operator = address(0x5);

    address engine;
    uint256 enginePrivateKey;

    uint32 evmChainId = 1;
    uint8 public srcEid = 1;
    uint8 public ledgerEid = 2;

    MockERC20 mockToken;
    ProtocolVault protocolVault;
    MockSVLedger svLedger;
    VaultCrossChainManager aVaultCrossChainManager;
    VaultCrossChainManager bVaultCrossChainManager;

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();
        (engine, enginePrivateKey) = makeAddrAndKey("engine");

        vm.deal(user, 100 ether);
        vm.deal(sp, 100 ether);
        // Deploy the StrategyVaultLedger contract
        address svLedgerImpl = address(new MockSVLedger());
        address svLedgerProxy = address(
            new ERC1967Proxy(svLedgerImpl, abi.encodeWithSelector(StrategyVaultLedger.initialize.selector, owner))
        );
        svLedger = MockSVLedger(svLedgerProxy);
        vm.prank(owner);
        svLedger.setOperatorManager(operator);
        vm.prank(owner);
        svLedger.setEngine(engine);

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
        aVaultCrossChainManager.setPeer(ledgerEid,addressToBytes32(address(bVaultCrossChainManager)));
        bVaultCrossChainManager.setPeer(srcEid,addressToBytes32(address(aVaultCrossChainManager)));
        //console.logBytes32(aVaultCrossChainManager.peers(LEDGER_EID));
        //set options
        aVaultCrossChainManager.setOptions(PayloadType.LP_DEPOSIT, 120000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.LP_WITHDRAW, 150000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.SP_DEPOSIT, 150000, 0);
        aVaultCrossChainManager.setOptions(PayloadType.SP_WITHDRAW, 150000, 0);

        bVaultCrossChainManager.setOptions(PayloadType.ASSETS_DISTRIBUTION, 120000, 0);
        bVaultCrossChainManager.setOptions(PayloadType.UPDATE_USER_CLAIM, 120000, 0);

        svLedger.setCrossChainManagerAddress(address(bVaultCrossChainManager));
        vm.stopPrank();

        //Deploy the MockERC20 contract and approve
        mockToken = new MockERC20("mockToken", "MTK", 6);

        //Deploy the ProtocolVault contract
        address protocolVaultImpl = address(new ProtocolVault());
        address proxy = address(
            new ERC1967Proxy(
                protocolVaultImpl,
                abi.encodeWithSelector(
                    ProtocolVault.initialize.selector, address(aVaultCrossChainManager), owner, address(mockToken), 0, 0
                )
            )
        );
        protocolVault = ProtocolVault(proxy);

        vm.prank(owner);
        bytes32 spId = _getStrategyProviderId(sp, ORDERLY_BROKER);
        svLedger.setAllowedStrategyProvider(ORDERLY_BROKER, address(protocolVault), sp, ORDERLY_BROKER, spId, true);

        //config cc contract
        vm.startPrank(owner);
        aVaultCrossChainManager.setVault(address(protocolVault));
        bVaultCrossChainManager.setLedger(svLedgerProxy);
        vm.stopPrank();
        //mint token
        mockToken.mint(user, 100000e6);
        mockToken.mint(sp, 100000e6);

        //approve
        vm.prank(user);
        mockToken.approve(address(protocolVault), 100e6);
        vm.prank(sp);
        mockToken.approve(address(protocolVault), 100e6);
    }

    function getEstimateFee(PayloadType payloadType) public view returns (uint256) {
        (uint256 nativeFee,) = aVaultCrossChainManager.quote(ledgerEid, buildCCMessage(), payloadType, false);
        return nativeFee;
    }

    //build StrategyVaultCCMessage
    function buildCCMessage() public view returns (bytes memory) {
        bytes32 vaultId = keccak256(abi.encodePacked(address(protocolVault)));

        bytes32 accountId = keccak256(abi.encodePacked(user, vaultId));

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
            payloadType: PayloadType.LP_DEPOSIT,
            srcChainId: 1,
            dstChainId: 2,
            payload: abi.encode(operationData)
        });

        bytes memory lzMessage = abi.encode(message);

        return lzMessage;
    }

    function _getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, brokerHash));
    }

    function _getStrategyProviderId(address strategyProvider, bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(protocolVault), strategyProvider, brokerHash));
    }

    function _getVaultId(bytes32 brokerHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(protocolVault), brokerHash));
    }
}
