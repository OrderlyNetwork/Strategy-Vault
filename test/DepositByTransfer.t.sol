// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Base, MockERC20} from "./Base.sol";
import {DepositFactory} from "../contracts/DepositProxy/DepositFactory.sol";
import {DepositBeaconImpl} from "../contracts/DepositProxy/DepositBeaconImpl.sol";
import {IDepositFactory} from "../contracts/interfaces/IDepositFactory.sol";
import {IDepositProxyImplementation} from "../contracts/interfaces/IDepositProxyImplementation.sol";
import {IProtocolVault} from "../contracts/interfaces/IProtocolVault.sol";
import {DepositParams} from "../contracts/lib/types/VaultStruct.sol";
import {PayloadType} from "../contracts/lib/types/CrossChainStruct.sol";
import {AccountToken} from "../contracts/lib/types/LedgerStruct.sol";
import {IDexVault, VaultDepositFE} from "../contracts/interfaces/IDexVault.sol";

contract DepositByTransferTest is Base {
    DepositFactory public depositFactory;
    DepositBeaconImpl public depositBeaconImpl;

    bytes32 public testAccountId;
    bytes32 public testAccountIdB;

    uint256 internal nextDepositId = 1;

    function setUp() public override {
        super.setUp();

        testAccountId = keccak256(abi.encode(userA, ORDERLY_BROKER));
        testAccountIdB = keccak256(abi.encode(userB, ORDERLY_BROKER));

        DepositFactory factoryImpl = new DepositFactory();
        bytes memory initData =
            abi.encodeCall(DepositFactory.initialize, (address(mockDexVault), operator, owner));
        address factoryProxy = address(new ERC1967Proxy(address(factoryImpl), initData));
        depositFactory = DepositFactory(factoryProxy);

        depositBeaconImpl = new DepositBeaconImpl(factoryProxy);

        vm.startPrank(owner);
        depositFactory.setImplementation(address(depositBeaconImpl));
        depositFactory.registerVault(vaultId, address(protocolVault));
        depositFactory.setSupportedToken(address(mockToken), true);
        depositFactory.setTokenHash(keccak256(abi.encodePacked("USDC")), address(mockToken));
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────

    function _nextDepositId() internal returns (uint256 id) {
        id = nextDepositId++;
    }

    function _defaultVaultParams(address receiver, uint256 amount) internal view returns (DepositParams memory) {
        return DepositParams({
            payloadType: PayloadType.LP_DEPOSIT,
            receiver: receiver,
            token: address(mockToken),
            amount: amount,
            brokerHash: ORDERLY_BROKER
        });
    }

    function _defaultDexData(address receiver, uint128 amount) internal view returns (VaultDepositFE memory) {
        bytes32 accountId = keccak256(abi.encode(receiver, ORDERLY_BROKER));
        return VaultDepositFE({
            accountId: accountId,
            brokerHash: ORDERLY_BROKER,
            tokenHash: keccak256(abi.encodePacked("USDC")),
            tokenAmount: amount
        });
    }

    /// @dev Fund proxy, deal ETH to operator, prank as operator, call deployAndDepositToVault
    function _depositToVault(address receiver, uint256 amount) internal returns (address proxy) {
        bytes32 accountId = keccak256(abi.encode(receiver, ORDERLY_BROKER));
        address predicted = depositFactory.getDepositAddress(accountId, address(protocolVault));
        mockToken.mint(predicted, amount);

        DepositParams memory params = _defaultVaultParams(receiver, amount);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, receiver, amount);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        proxy = depositFactory.deployAndDepositToVault{value: fee}(_nextDepositId(), vaultId, params);
    }

    /// @dev Fund proxy, deal ETH to operator, prank as operator, call deployAndDepositToDex
    function _depositToDex(address receiver, uint128 amount) internal returns (address proxy) {
        bytes32 accountId = keccak256(abi.encode(receiver, ORDERLY_BROKER));
        address predicted = depositFactory.getDepositAddress(accountId, address(mockDexVault));
        mockToken.mint(predicted, amount);

        VaultDepositFE memory data = _defaultDexData(receiver, amount);
        vm.deal(operator, 1 ether);

        vm.prank(operator);
        proxy = depositFactory.deployAndDepositToDex{value: 0}(_nextDepositId(), receiver, data);
    }

    // ──────────────────────────────────────────────────
    // 8.1  Address & Deployment
    // ──────────────────────────────────────────────────

    function testGetDepositAddressDeterministic() public view {
        address a1 = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        address a2 = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        assertEq(a1, a2);
    }

    function testGetDepositAddressDifferentSalts() public view {
        address a = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        address b = depositFactory.getDepositAddress(testAccountIdB, address(protocolVault));
        address c = depositFactory.getDepositAddress(testAccountId, address(mockDexVault));
        assertTrue(a != b, "Different accountId should produce different address");
        assertTrue(a != c, "Different vaultAddress should produce different address");
    }

    function testDeployedProxyMatchesPredictedAddress() public {
        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        address proxy = _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        assertEq(proxy, predicted);
    }

    function testIsDeployedBeforeAndAfter() public {
        assertFalse(depositFactory.isDeployed(testAccountId, address(protocolVault)));
        _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        assertTrue(depositFactory.isDeployed(testAccountId, address(protocolVault)));
    }

    // ──────────────────────────────────────────────────
    // 8.2  deployAndDepositToVault
    // ──────────────────────────────────────────────────

    function testDeployAndDepositToVaultSuccess() public {
        uint256 amount = 100e6;
        address proxy = _depositToVault(userA, amount);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        bytes32 accountId = _getAccountId(userA, ORDERLY_BROKER);
        AccountToken memory at = svLedger.getAccountToken(vaultId, accountId);
        assertEq(at.unAllocatedAssets, amount);
        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
        assertEq(IERC20(mockToken).balanceOf(proxy), 0);
    }

    function testDeployAndDepositToVaultSecondDeposit() public {
        uint256 first = 100e6;
        uint256 second = 200e6;
        address proxy1 = _depositToVault(userA, first);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        address proxy2 = _depositToVault(userA, second);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        assertEq(proxy1, proxy2, "Should reuse the same proxy");
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), first + second);
        assertEq(protocolVault.chainNonce(), 2);
    }

    function testRevertDeployAndDepositToVaultNotOperator() public {
        DepositParams memory params = _defaultVaultParams(userA, 100e6);

        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.UnauthorizedCaller.selector, userB));
        depositFactory.deployAndDepositToVault(99, vaultId, params);
    }

    function testRevertDeployAndDepositToVaultDuplicateDepositId() public {
        _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Use the same depositId (nextDepositId - 1 was used in _depositToVault)
        uint256 usedId = nextDepositId - 1;
        DepositParams memory params = _defaultVaultParams(userA, 50e6);
        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(predicted, 50e6);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, 50e6);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.DepositAlreadyProcessed.selector, usedId));
        depositFactory.deployAndDepositToVault{value: fee}(usedId, vaultId, params);
    }

    function testRevertDeployAndDepositToVaultTokenNotSupported() public {
        DepositParams memory params = _defaultVaultParams(userA, 100e6);
        MockERC20 unsupported = new MockERC20("X", "X", 6);
        params.token = address(unsupported);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.TokenNotSupported.selector, address(unsupported)));
        depositFactory.deployAndDepositToVault(_nextDepositId(), vaultId, params);
    }

    function testRevertDeployAndDepositToVaultVaultNotRegistered() public {
        DepositParams memory params = _defaultVaultParams(userA, 100e6);
        bytes32 fakeVaultId = keccak256("FAKE");

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.VaultNotRegistered.selector, fakeVaultId));
        depositFactory.deployAndDepositToVault(_nextDepositId(), fakeVaultId, params);
    }

    function testRevertDeployAndDepositToVaultInsufficientBalance() public {
        DepositParams memory params = _defaultVaultParams(userA, 100e6);
        // Don't fund the proxy
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, 100e6);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.InsufficientBalance.selector, 100e6, 0));
        depositFactory.deployAndDepositToVault{value: fee}(_nextDepositId(), vaultId, params);
    }

    function testRevertDeployAndDepositToVaultImplementationNotConfigured() public {
        // Deploy a fresh factory without setImplementation
        DepositFactory freshImpl = new DepositFactory();
        bytes memory initData =
            abi.encodeCall(DepositFactory.initialize, (address(mockDexVault), operator, owner));
        DepositFactory fresh = DepositFactory(address(new ERC1967Proxy(address(freshImpl), initData)));
        vm.startPrank(owner);
        fresh.registerVault(vaultId, address(protocolVault));
        fresh.setSupportedToken(address(mockToken), true);
        vm.stopPrank();

        DepositParams memory params = _defaultVaultParams(userA, 100e6);

        vm.prank(operator);
        vm.expectRevert(IDepositFactory.ImplementationNotConfigured.selector);
        fresh.deployAndDepositToVault(_nextDepositId(), vaultId, params);
    }

    function testRevertDeployAndDepositToVaultWrongReceiverTargetsEmptyProxy() public {
        // Fund proxy for userA
        address proxyA = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(proxyA, 100e6);

        // Operator tries with userB's receiver but funds are in userA's proxy
        DepositParams memory params = _defaultVaultParams(userB, 100e6);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userB, 100e6);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.InsufficientBalance.selector, 100e6, 0));
        depositFactory.deployAndDepositToVault{value: fee}(_nextDepositId(), vaultId, params);
    }

    // ──────────────────────────────────────────────────
    // 8.3  deployAndDepositToDex
    // ──────────────────────────────────────────────────

    function testDeployAndDepositToDexSuccess() public {
        uint128 amount = 50e6;
        address proxy = _depositToDex(userA, amount);

        bytes32 accountId = keccak256(abi.encode(userA, ORDERLY_BROKER));
        assertTrue(depositFactory.isDeployed(accountId, address(mockDexVault)));
        assertEq(IERC20(mockToken).balanceOf(proxy), 0);
        assertEq(IERC20(mockToken).balanceOf(address(mockDexVault)), amount);
    }

    function testRevertDeployAndDepositToDexNotOperator() public {
        VaultDepositFE memory data = _defaultDexData(userA, 50e6);

        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.UnauthorizedCaller.selector, userB));
        depositFactory.deployAndDepositToDex(99, userA, data);
    }

    function testRevertDeployAndDepositToDexDuplicateDepositId() public {
        _depositToDex(userA, 50e6);
        uint256 usedId = nextDepositId - 1;

        bytes32 accountId = keccak256(abi.encode(userA, ORDERLY_BROKER));
        address predicted = depositFactory.getDepositAddress(accountId, address(mockDexVault));
        mockToken.mint(predicted, 50e6);

        VaultDepositFE memory data = _defaultDexData(userA, 50e6);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.DepositAlreadyProcessed.selector, usedId));
        depositFactory.deployAndDepositToDex(usedId, userA, data);
    }

    function testRevertDeployAndDepositToDexInvalidAccountId() public {
        VaultDepositFE memory data = _defaultDexData(userA, 50e6);
        data.accountId = bytes32(uint256(1)); // tamper

        bytes32 accountId = keccak256(abi.encode(userA, ORDERLY_BROKER));
        address predicted = depositFactory.getDepositAddress(accountId, address(mockDexVault));
        mockToken.mint(predicted, 50e6);

        vm.prank(operator);
        vm.expectRevert(IDepositFactory.InvalidAccountId.selector);
        depositFactory.deployAndDepositToDex(_nextDepositId(), userA, data);
    }

    function testRevertDeployAndDepositToDexTokenHashNotRegistered() public {
        VaultDepositFE memory data = _defaultDexData(userA, 50e6);
        data.tokenHash = keccak256("UNKNOWN");

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.TokenNotSupported.selector, address(0)));
        depositFactory.deployAndDepositToDex(_nextDepositId(), userA, data);
    }

    function testRevertDeployAndDepositToDexInsufficientBalance() public {
        VaultDepositFE memory data = _defaultDexData(userA, 50e6);
        // Don't fund proxy

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.InsufficientBalance.selector, 50e6, 0));
        depositFactory.deployAndDepositToDex(_nextDepositId(), userA, data);
    }

    // ──────────────────────────────────────────────────
    // 8.4  Admin / Access Control
    // ──────────────────────────────────────────────────

    function testSetImplementationOnlyOwner() public {
        DepositBeaconImpl newImpl = new DepositBeaconImpl(address(depositFactory));
        vm.prank(owner);
        depositFactory.setImplementation(address(newImpl));
        assertEq(depositFactory.implementation(), address(newImpl));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.setImplementation(address(newImpl));
    }

    function testRegisterVaultOnlyOwner() public {
        bytes32 newVid = keccak256("NEW_VAULT");
        vm.prank(owner);
        depositFactory.registerVault(newVid, address(1));
        assertEq(depositFactory.vaults(newVid), address(1));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.registerVault(newVid, address(2));
    }

    function testUnregisterVaultOnlyOwner() public {
        vm.prank(owner);
        depositFactory.unregisterVault(vaultId);
        assertEq(depositFactory.vaults(vaultId), address(0));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.unregisterVault(vaultId);
    }

    function testSetSupportedTokenOnlyOwner() public {
        address token2 = address(0xBEEF);
        vm.prank(owner);
        depositFactory.setSupportedToken(token2, true);
        assertTrue(depositFactory.supportedTokens(token2));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.setSupportedToken(token2, false);
    }

    function testSetTokenHashOnlyOwner() public {
        bytes32 hash = keccak256("ETH");
        vm.prank(owner);
        depositFactory.setTokenHash(hash, address(0xBEEF));
        assertEq(depositFactory.tokenHashToAddress(hash), address(0xBEEF));

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.setTokenHash(hash, address(0xDEAD));
    }

    function testSetOperatorOnlyOwner() public {
        address newOp = address(0xABCD);
        vm.prank(owner);
        depositFactory.setOperator(newOp);
        assertEq(depositFactory.operator(), newOp);

        // Old operator can no longer call
        DepositParams memory params = _defaultVaultParams(userA, 1e6);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.UnauthorizedCaller.selector, operator));
        depositFactory.deployAndDepositToVault(_nextDepositId(), vaultId, params);
    }

    function testEmergencyWithdrawOnlyOwner() public {
        // Deploy a proxy by depositing first
        _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Send more tokens to the proxy
        address proxy = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(proxy, 50e6);

        address recipient = address(0xCAFE);
        vm.prank(owner);
        depositFactory.emergencyWithdraw(testAccountId, address(protocolVault), address(mockToken), recipient, 50e6);
        assertEq(IERC20(mockToken).balanceOf(recipient), 50e6);

        // Non-owner cannot call
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        depositFactory.emergencyWithdraw(testAccountId, address(protocolVault), address(mockToken), recipient, 0);
    }

    function testRevertEmergencyWithdrawProxyNotDeployed() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDepositFactory.DepositFailed.selector, "Proxy not deployed"));
        depositFactory.emergencyWithdraw(testAccountId, address(protocolVault), address(mockToken), owner, 1);
    }

    // ──────────────────────────────────────────────────
    // 8.5  DepositBeaconImpl — onlyFactory
    // ──────────────────────────────────────────────────

    function testRevertDepositToVaultOnlyFactory() public {
        DepositParams memory params = _defaultVaultParams(userA, 1e6);
        vm.prank(userA);
        vm.expectRevert(IDepositProxyImplementation.OnlyFactory.selector);
        depositBeaconImpl.depositToVault(address(protocolVault), params);
    }

    function testRevertDepositToDexOnlyFactory() public {
        VaultDepositFE memory data = _defaultDexData(userA, 1e6);
        vm.prank(userA);
        vm.expectRevert(IDepositProxyImplementation.OnlyFactory.selector);
        depositBeaconImpl.depositToDex(address(mockDexVault), userA, address(mockToken), data);
    }

    function testRevertWithdrawOnlyFactory() public {
        vm.prank(userA);
        vm.expectRevert(IDepositProxyImplementation.OnlyFactory.selector);
        depositBeaconImpl.withdraw(address(mockToken), userA, 1);
    }

    // ──────────────────────────────────────────────────
    // 8.6  Beacon Upgrade
    // ──────────────────────────────────────────────────

    function testSetImplementationUpgradesAllProxies() public {
        uint256 amount = 100e6;
        address proxy = _depositToVault(userA, amount);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // V2: deducts 1 from amount
        DepositBeaconImplV2 v2 = new DepositBeaconImplV2(address(depositFactory));
        vm.prank(owner);
        depositFactory.setImplementation(address(v2));

        // Second deposit on same proxy now uses V2 logic
        mockToken.mint(proxy, amount);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);
        vm.deal(operator, fee + 1 ether);
        vm.prank(operator);
        depositFactory.deployAndDepositToVault{value: fee}(_nextDepositId(), vaultId, _defaultVaultParams(userA, amount));
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // V2 deposits amount-1 and leaves 1 in proxy
        assertEq(IERC20(mockToken).balanceOf(proxy), 1);
    }

    function testSetImplementationRollback() public {
        DepositBeaconImplV2 v2 = new DepositBeaconImplV2(address(depositFactory));
        vm.prank(owner);
        depositFactory.setImplementation(address(v2));
        // Rollback
        vm.prank(owner);
        depositFactory.setImplementation(address(depositBeaconImpl));
        assertEq(depositFactory.implementation(), address(depositBeaconImpl));

        // Normal deposit works fully (no -1 deduction)
        address proxy = _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        assertEq(IERC20(mockToken).balanceOf(proxy), 0);
    }

    // ──────────────────────────────────────────────────
    // 8.7  Events
    // ──────────────────────────────────────────────────

    function testDeployAndDepositToVaultEmitsDepositToVault() public {
        uint256 depositId = _nextDepositId();
        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(predicted, 100e6);
        DepositParams memory params = _defaultVaultParams(userA, 100e6);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, 100e6);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        vm.expectEmit(false, false, false, true, address(depositFactory));
        emit IDepositFactory.DepositToVault(depositId);
        depositFactory.deployAndDepositToVault{value: fee}(depositId, vaultId, params);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
    }

    function testDeployAndDepositToDexEmitsDepositToDex() public {
        uint256 depositId = _nextDepositId();
        bytes32 accountId = keccak256(abi.encode(userA, ORDERLY_BROKER));
        address predicted = depositFactory.getDepositAddress(accountId, address(mockDexVault));
        mockToken.mint(predicted, 50e6);
        VaultDepositFE memory data = _defaultDexData(userA, 50e6);

        vm.prank(operator);
        vm.expectEmit(false, false, false, true, address(depositFactory));
        emit IDepositFactory.DepositToDex(depositId);
        depositFactory.deployAndDepositToDex(depositId, userA, data);
    }

    function testFirstDeployEmitsProxyDeployed() public {
        uint256 depositId = _nextDepositId();
        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(predicted, 100e6);
        DepositParams memory params = _defaultVaultParams(userA, 100e6);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, 100e6);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        vm.expectEmit(false, false, false, true, address(depositFactory));
        emit IDepositFactory.ProxyDeployed(testAccountId, address(protocolVault), predicted);
        depositFactory.deployAndDepositToVault{value: fee}(depositId, vaultId, params);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
    }

    function testEmergencyWithdrawEmitsEvent() public {
        _depositToVault(userA, 100e6);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));
        address proxy = depositFactory.getDepositAddress(testAccountId, address(protocolVault));
        mockToken.mint(proxy, 10e6);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(depositFactory));
        emit IDepositFactory.EmergencyWithdrawal(testAccountId, address(protocolVault), address(mockToken), owner, 10e6);
        depositFactory.emergencyWithdraw(testAccountId, address(protocolVault), address(mockToken), owner, 10e6);
    }

    // ──────────────────────────────────────────────────
    // 8.8  Integration & Multi-Transfer
    // ──────────────────────────────────────────────────

    function testMultipleDepositsSameProxyDifferentDepositIds() public {
        uint256 a1 = 100e6;
        uint256 a2 = 200e6;

        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));

        // Transfer #1
        mockToken.mint(predicted, a1);
        DepositParams memory p1 = _defaultVaultParams(userA, a1);
        uint256 fee1 = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, a1);
        vm.deal(operator, fee1 + 1 ether);
        vm.prank(operator);
        depositFactory.deployAndDepositToVault{value: fee1}(_nextDepositId(), vaultId, p1);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        // Transfer #2
        mockToken.mint(predicted, a2);
        DepositParams memory p2 = _defaultVaultParams(userA, a2);
        uint256 fee2 = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, a2);
        vm.deal(operator, fee2 + 1 ether);
        vm.prank(operator);
        depositFactory.deployAndDepositToVault{value: fee2}(_nextDepositId(), vaultId, p2);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), a1 + a2);
        assertEq(IERC20(mockToken).balanceOf(predicted), 0);
        assertEq(protocolVault.chainNonce(), 2);
    }

    function testDeployAndDepositToVaultFullFlow() public {
        uint256 amount = 100e6;
        address predicted = depositFactory.getDepositAddress(testAccountId, address(protocolVault));

        mockToken.mint(predicted, amount);
        DepositParams memory params = _defaultVaultParams(userA, amount);
        uint256 fee = protocolVault.quoteOperation(PayloadType.LP_DEPOSIT, userA, amount);
        vm.deal(operator, fee + 1 ether);

        vm.prank(operator);
        address proxy = depositFactory.deployAndDepositToVault{value: fee}(_nextDepositId(), vaultId, params);
        verifyPackets(ledgerEid, addressToBytes32(address(bVaultCrossChainManager)));

        assertEq(proxy, predicted);
        assertTrue(depositFactory.isDeployed(testAccountId, address(protocolVault)));

        bytes32 accountId = _getAccountId(userA, ORDERLY_BROKER);
        AccountToken memory at = svLedger.getAccountToken(vaultId, accountId);
        assertEq(at.unAllocatedAssets, amount);
        assertEq(protocolVault.chainNonce(), 1);
        assertEq(IERC20(mockToken).balanceOf(address(protocolVault)), amount);
        assertEq(IERC20(mockToken).balanceOf(proxy), 0);
    }
}

// ──────────────────────────────────────────────────
// Mock V2 implementation for beacon upgrade tests
// ──────────────────────────────────────────────────

contract DepositBeaconImplV2 {
    address public immutable FACTORY;

    constructor(address _factory) {
        FACTORY = _factory;
    }

    modifier onlyFactory() {
        if (msg.sender != FACTORY) revert IDepositProxyImplementation.OnlyFactory();
        _;
    }

    /// @dev V2 deliberately deposits amount-1 to demonstrate upgrade behaviour
    function depositToVault(address vault, DepositParams memory params) external payable onlyFactory {
        uint256 upgradedAmount = params.amount - 1;
        params.amount = upgradedAmount;
        IERC20(params.token).approve(vault, upgradedAmount);
        IProtocolVault(vault).deposit{value: msg.value}(params);
    }
}
