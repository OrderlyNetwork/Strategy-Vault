// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import {ProtocolVault} from "../contracts/ProtocolVault.sol";
import {VaultCrossChainManager} from "../contracts/VaultCrossChainManager.sol";
import {StrategyVaultLedger} from "../contracts/StrategyVaultLedger.sol";
import {VaultType, OperationData} from "../contracts/lib/types/VaultStruct.sol";
import {StrategyVaultCCMessage} from "../contracts/lib/types/CrossChainStruct.sol";
// Mock ERC20 token contract
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Base is TestHelperOz5 {
    using OptionsBuilder for bytes;

    address public owner = address(0x123);
    address public user = address(0x1);
    uint32 public srcEid = 1;
    uint32 public ledgerEid = 2;

    MockERC20 mockToken;
    ProtocolVault protocolVault;
    StrategyVaultLedger svLedger;
    VaultCrossChainManager aVaultCrossChainManager;
    VaultCrossChainManager bVaultCrossChainManager;

    function setUp() public virtual override {
        // Call the base setup function from the TestHelperOz5 contract
        super.setUp();

        vm.deal(user, 100 ether);
        // Deploy the StrategyVaultLedger contract
        address svLedgerImpl = address(new StrategyVaultLedger());
        address svLedgerProxy =
            address(new ERC1967Proxy(svLedgerImpl, abi.encodeWithSelector(StrategyVaultLedger.initialize.selector, "")));
        svLedger = StrategyVaultLedger(svLedgerProxy);

        // Initialize 2 endpoints, using UltraLightNode as the library type
        setUpEndpoints(2, LibraryType.UltraLightNode);
        address[] memory uas = setupOApps(type(VaultCrossChainManager).creationCode, 1, 2);
        // Deploy the VaultCrossChainManager contract
        aVaultCrossChainManager = VaultCrossChainManager(payable(uas[0]));
        bVaultCrossChainManager = VaultCrossChainManager(payable(uas[1]));

        aVaultCrossChainManager.setDstEid(ledgerEid);
        bVaultCrossChainManager.setDstEid(srcEid);
        bVaultCrossChainManager.setLedger(svLedgerProxy);

        svLedger.setCrossChainManagerAddress(address(bVaultCrossChainManager));

        //Deploy the ProtocolVault contract
        address protocolVaultImpl = address(new ProtocolVault());
        address proxy = address(
            new ERC1967Proxy(
                protocolVaultImpl,
                abi.encodeWithSelector(ProtocolVault.initialize.selector, address(aVaultCrossChainManager))
            )
        );
        protocolVault = ProtocolVault(proxy);

        //Deploy the MockERC20 contract and approve
        mockToken = new MockERC20("mockToken", "MTK", 6);
        mockToken.mint(user, 100000e6);

        vm.startPrank(user);
        mockToken.approve(address(protocolVault), 100e6);
    }

    function getEstimateFee() public view returns (uint256) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        (uint256 nativeFee,) = aVaultCrossChainManager.quote(ledgerEid, buildCCMessage(), options, false);
        return nativeFee;
    }

    //build StrategyVaultCCMessage
    function buildCCMessage() public view returns (bytes memory) {
        bytes32 vaultId = keccak256(abi.encodePacked(address(protocolVault)));

        bytes32 accountId = keccak256(abi.encodePacked(user, vaultId));

        // DepositData memory depositData = DepositData({
        //     vaultType: VaultType.PROTOCOL,
        //     amount: 100e6,
        //     depositNonce: 0,
        //     token: address(mockToken),
        //     receiver: user,
        //     strategyProvider: address(0),
        //     vault: address(protocolVault),
        //     vaultId: vaultId,
        //     accountId: accountId,
        //     strategyProviderId: keccak256(abi.encodePacked(address(protocolVault))),
        //     brokerHash: bytes32(0)
        // });

        //bytes memory lzMessage = encodeLzMsg(uint8(PayloadType.DEPOSIT), abi.encode(depositData));
        //return lzMessage;
    }

    function encodeLzMsg(uint8 msgType, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(msgType), payload);
    }

    function decodeLzMsg(bytes calldata message) internal pure returns (uint8 msgType, bytes memory payload) {
        //decode msg type and payload
        uint8 MSG_TYPE_OFFSET = 1;
        msgType = uint8(bytes1(message[:MSG_TYPE_OFFSET]));
        payload = message[MSG_TYPE_OFFSET:];
    }
}
