// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "../Base.sol";
import {console} from "forge-std/console.sol";
import {
    DexRequest,
    DexRequestData,
    ChainType,
    PayloadType,
    AccountToken,
    StrategyFundToken
} from "../../contracts/lib/types/LedgerStruct.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {VaultUtils} from "../../contracts/lib/utils/VaultUtils.sol";

contract DexIntegrationTest is Base {
    // Events that need to be declared for testing
    event DexRequestsHandled(DexRequest dexRequest);
    event DexWithdrawNotEnough(uint256 requestId);

    // Setup
    address lp;
    uint256 lpPrivateKey;

    bytes32 lpId;

    // Add missing constants and variables
    uint256 constant assetDecimal = 1e6;
    uint256 constant shareDecimal = 1e6;
    bytes32 vaultId;

    // User addresses and private keys for testing
    uint256 userAPrivateKey;
    uint256 userBPrivateKey;

    function setUp() public override {
        super.setUp();
        // Setup
        (lp, lpPrivateKey) = makeAddrAndKey("lp");
        lpId = _getAccountId(lp, ORDERLY_BROKER);
        (sp, spPrivateKey) = makeAddrAndKey("sp");
        spId = _getAccountId(sp, ORDERLY_BROKER);

        // Generate private keys for userA and userB
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        (userB, userBPrivateKey) = makeAddrAndKey("userB");

        // Update user IDs based on new addresses
        userA_id = _getAccountId(userA, ORDERLY_BROKER);
        userB_id = _getAccountId(userB, ORDERLY_BROKER);

        // Set vaultId
        vaultId = keccak256(abi.encode(protocolVault, ORDERLY_BROKER));

        // Deal ETH and mint tokens for new addresses
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);
        mockToken.mint(userA, 100000e18);
        mockToken.mint(userB, 100000e18);
    }

    function testHandleDexRequestsLPDeposit() public {
        uint256 amount = 1000e6;
        uint256 requestId = 1;

        // Create DexRequestData using helper function
        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);

        // Create DexRequest array using helper function
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);

        // Generate engine signature
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify result using helper function
        _assertLPDepositResult(lpId, requestId, amount);
    }

    function testHandleDexRequestsLPWithdraw() public {
        uint256 amount = 500e6;
        uint256 initialShares = 1000e6;
        uint256 requestId = 2;

        // First, set up account with some pending shares
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = lpId;
        svLedger.setAccountPendingShares(accountIds, initialShares);

        // Create DexRequestData using helper function
        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_WITHDRAW, requestId, lp, amount);

        // Create DexRequest array using helper function
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);

        // Generate engine signature
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify result using helper function
        _assertLPWithdrawResult(lpId, requestId, amount, initialShares);
    }

    function testHandleDexRequestsLPWithdrawInsufficientBalance() public {
        uint256 withdrawAmount = 1000e6;
        uint256 availableShares = 500e6; // Less than withdraw amount
        uint256 requestId = 4;

        // Set up account with insufficient pending shares
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = lpId;
        svLedger.setAccountPendingShares(accountIds, availableShares);

        // Create DexRequestData using helper function
        DexRequestData memory dexRequestData =
            _createDexRequestData(PayloadType.LP_WITHDRAW, requestId, lp, withdrawAmount);

        // Create DexRequest array using helper function
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);

        // Generate engine signature
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Execute - should handle the request but not freeze any shares due to insufficient balance
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify result using helper function - withdrawal should fail
        _assertLPWithdrawResult(lpId, requestId, 0, availableShares);
    }

    function testHandleDexRequestsSPDeposit() public {
        // Setup
        uint256 amount = 2000e6;
        uint256 requestId = 3;

        // Create DexRequestData using helper function
        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.SP_DEPOSIT, requestId, sp, amount);

        // Create DexRequest array using helper function
        DexRequest[] memory dexRequests = _createDexRequestArray(spId, sp, spPrivateKey, dexRequestData);

        // Generate engine signature
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify result using helper function
        _assertSPDepositResult(spId, requestId, amount);
    }

    /// @notice Test handleDexRequests - both requests succeed
    function testHandleDexRequestsBothSuccess() public {
        // Set up two users: one LP deposit, one LP withdraw
        uint256 depositAmount = 1000 * assetDecimal;
        uint256 withdrawAmount = 500 * assetDecimal;
        uint256 initialShares = 800 * shareDecimal;
        {
            // Set sufficient pending shares for userB for withdrawal
            bytes32[] memory accountIds = new bytes32[](1);
            accountIds[0] = userB_id;
            svLedger.setAccountPendingShares(accountIds, initialShares);
        }
        // Create two DexRequests
        DexRequest[] memory dexRequests = new DexRequest[](2);

        // First request: userA LP deposit
        DexRequestData memory depositData = DexRequestData({
            payloadType: PayloadType.LP_DEPOSIT,
            dexRequestId: 1,
            receiver: bytes32(uint256(uint160(userA))),
            amount: depositAmount,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v1, bytes32 r1, bytes32 s1) = _generateUserSignatureComponents(userA, userAPrivateKey, depositData);
        dexRequests[0] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userA_id,
            dexRequestData: depositData,
            r: r1,
            s: s1,
            v: v1
        });

        // Second request: userB LP withdraw
        DexRequestData memory withdrawData = DexRequestData({
            payloadType: PayloadType.LP_WITHDRAW,
            dexRequestId: 2,
            receiver: bytes32(uint256(uint160(userB))),
            amount: withdrawAmount,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v2, bytes32 r2, bytes32 s2) = _generateUserSignatureComponents(userB, userBPrivateKey, withdrawData);
        dexRequests[1] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userB_id,
            dexRequestData: withdrawData,
            r: r2,
            s: s2,
            v: v2
        });

        // Generate engine signature
        bytes memory signature = _getDexRequestSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, signature);

        // Verify results
        // UserA should have deposit assets
        (, uint256 userAUnAllocatedAssets,,) = svLedger.accountTokenInfo(userA_id, USDC_HASH);
        assertEq(userAUnAllocatedAssets, depositAmount);

        // UserB should have frozen shares
        (,, uint256 userBFrozenShares,) = svLedger.accountTokenInfo(userB_id, USDC_HASH);
        assertEq(userBFrozenShares, withdrawAmount);

        // Both requests should be marked as handled
        assertTrue(svLedger.isDexRequestHandled(1));
        assertTrue(svLedger.isDexRequestHandled(2));
    }

    /// @notice Test handleDexRequests - both requests fail due to insufficient shares
    function testHandleDexRequestsBothFail() public {
        uint256 withdrawAmount1 = 1000 * assetDecimal;
        uint256 withdrawAmount2 = 800 * assetDecimal;
        uint256 insufficientShares = 200 * shareDecimal; // Insufficient to support any withdrawal

        // Set insufficient shares for both users
        bytes32[] memory accountIds = new bytes32[](2);
        accountIds[0] = userA_id;
        accountIds[1] = userB_id;
        svLedger.setAccountPendingShares(accountIds, insufficientShares);

        // Create two DexRequests, both LP withdrawals
        DexRequest[] memory dexRequests = new DexRequest[](2);

        // First request: userA LP withdraw
        DexRequestData memory withdrawData1 = DexRequestData({
            payloadType: PayloadType.LP_WITHDRAW,
            dexRequestId: 3,
            receiver: bytes32(uint256(uint160(userA))),
            amount: withdrawAmount1,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v3, bytes32 r3, bytes32 s3) = _generateUserSignatureComponents(userA, userAPrivateKey, withdrawData1);
        dexRequests[0] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userA_id,
            dexRequestData: withdrawData1,
            r: r3,
            s: s3,
            v: v3
        });

        // Second request: userB LP withdraw
        DexRequestData memory withdrawData2 = DexRequestData({
            payloadType: PayloadType.LP_WITHDRAW,
            dexRequestId: 4,
            receiver: bytes32(uint256(uint160(userB))),
            amount: withdrawAmount2,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v4, bytes32 r4, bytes32 s4) = _generateUserSignatureComponents(userB, userBPrivateKey, withdrawData2);
        dexRequests[1] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userB_id,
            dexRequestData: withdrawData2,
            r: r4,
            s: s4,
            v: v4
        });

        // Generate engine signature
        bytes memory signature = _getDexRequestSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, signature);

        // Verify results - both should fail, shares unchanged
        (,, uint256 userAFrozenShares,) = svLedger.accountTokenInfo(userA_id, USDC_HASH);
        (,, uint256 userBFrozenShares,) = svLedger.accountTokenInfo(userB_id, USDC_HASH);
        assertEq(userAFrozenShares, 0); // No frozen shares because withdrawal failed
        assertEq(userBFrozenShares, 0); // No frozen shares because withdrawal failed

        // Both requests should be marked as handled
        assertTrue(svLedger.isDexRequestHandled(3));
        assertTrue(svLedger.isDexRequestHandled(4));
    }

    /// @notice Test handleDexRequests - one succeeds, one fails
    function testHandleDexRequestsOneSuccessOneFail() public {
        uint256 depositAmount = 1000 * assetDecimal;
        uint256 withdrawAmount = 800 * assetDecimal;
        uint256 insufficientShares = 200 * shareDecimal; // Insufficient to support withdrawal
        {
            // Set insufficient shares for userB for withdrawal failure
            bytes32[] memory accountIds = new bytes32[](1);
            accountIds[0] = userB_id;
            svLedger.setAccountPendingShares(accountIds, insufficientShares);
        }
        // Create two DexRequests
        DexRequest[] memory dexRequests = new DexRequest[](2);

        // First request: userA LP deposit (should succeed)
        DexRequestData memory depositData = DexRequestData({
            payloadType: PayloadType.LP_DEPOSIT,
            dexRequestId: 5,
            receiver: bytes32(uint256(uint160(userA))),
            amount: depositAmount,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v5, bytes32 r5, bytes32 s5) = _generateUserSignatureComponents(userA, userAPrivateKey, depositData);
        dexRequests[0] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userA_id,
            dexRequestData: depositData,
            r: r5,
            s: s5,
            v: v5
        });

        // Second request: userB LP withdraw (should fail)
        DexRequestData memory withdrawData = DexRequestData({
            payloadType: PayloadType.LP_WITHDRAW,
            dexRequestId: 6,
            receiver: bytes32(uint256(uint160(userB))),
            amount: withdrawAmount,
            vaultId: vaultId,
            token: "USDC",
            dexBrokerId: "orderly"
        });

        (uint8 v6, bytes32 r6, bytes32 s6) = _generateUserSignatureComponents(userB, userBPrivateKey, withdrawData);
        dexRequests[1] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: userB_id,
            dexRequestData: withdrawData,
            r: r6,
            s: s6,
            v: v6
        });

        // Generate engine signature
        bytes memory signature = _getDexRequestSignature(dexRequests);

        // Execute
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, signature);

        // Verify results
        // UserA deposit should succeed
        (, uint256 userAUnAllocatedAssets,,) = svLedger.accountTokenInfo(userA_id, USDC_HASH);
        assertEq(userAUnAllocatedAssets, depositAmount);

        // UserB withdrawal should fail, no frozen shares
        (,, uint256 userBFrozenShares,) = svLedger.accountTokenInfo(userB_id, USDC_HASH);
        assertEq(userBFrozenShares, 0);

        // Both requests should be marked as handled
        assertTrue(svLedger.isDexRequestHandled(5));
        assertTrue(svLedger.isDexRequestHandled(6));
    }

    /// @notice Generate signature components (r, s, v) for user signature
    /// @param receiver The receiver address
    /// @param privateKey The private key for signing
    /// @param data The DexRequestData to sign
    /// @return v The recovery ID (0 or 1)
    /// @return r The r component of the signature
    /// @return s The s component of the signature
    function _generateUserSignatureComponents(address receiver, uint256 privateKey, DexRequestData memory data)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // Create EIP-712 domain hash
        bytes32 eip712DomainHash = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Orderly")),
                keccak256(bytes("1")),
                block.chainid,
                address(svLedger)
            )
        );

        // Create struct hash - use correct TypeHash
        bytes32 hashStruct = keccak256(
            abi.encode(
                keccak256(
                    "DexRequest(uint8 payloadType,uint256 nonce,address receiver,uint256 amount,bytes32 vaultId,string token,string dexBrokerId)"
                ),
                data.payloadType,
                data.dexRequestId,
                receiver,
                data.amount,
                data.vaultId,
                keccak256(abi.encodePacked(data.token)),
                keccak256(abi.encodePacked(data.dexBrokerId))
            )
        );

        // Create final EIP-712 hash
        bytes32 finalHash = MessageHashUtils.toTypedDataHash(eip712DomainHash, hashStruct);
        // Generate signature using receiver's private key
        (v, r, s) = vm.sign(privateKey, finalHash);
    }

    function _getDexRequestSignature(DexRequest[] memory dexRequests) internal view returns (bytes memory) {
        // Create message hash for engine signature
        bytes32 messageHash = keccak256(abi.encode(dexRequests));

        // Sign with engine private key
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));

        return abi.encodePacked(r, s, v);
    }

    function _generateEngineSignature(DexRequest[] memory dexRequests) internal view returns (bytes memory) {
        // Create message hash for engine signature (simple eth signed message)
        bytes32 messageHash = keccak256(abi.encode(dexRequests));

        // Sign with engine private key using eth signed message format
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(enginePrivateKey, MessageHashUtils.toEthSignedMessageHash(messageHash));

        return abi.encodePacked(r, s, v);
    }
    /// @notice Helper function to construct DexRequestData
    /// @param payloadType Operation type
    /// @param requestId Request ID
    /// @param receiver Receiver address
    /// @param amount Amount
    /// @return DexRequestData structure

    function _createDexRequestData(PayloadType payloadType, uint256 requestId, address receiver, uint256 amount)
        internal
        view
        returns (DexRequestData memory)
    {
        return DexRequestData({
            payloadType: payloadType,
            dexRequestId: requestId,
            receiver: bytes32(uint256(uint160(receiver))),
            amount: amount,
            vaultId: keccak256(abi.encode(protocolVault, ORDERLY_BROKER)),
            token: "USDC",
            dexBrokerId: "orderly"
        });
    }

    /// @notice Helper function to construct DexRequest
    /// @param id Account or strategy provider ID
    /// @param receiver Receiver address
    /// @param privateKey Private key
    /// @param dexRequestData DexRequestData structure
    /// @return DexRequest structure
    function _createDexRequest(bytes32 id, address receiver, uint256 privateKey, DexRequestData memory dexRequestData)
        internal
        view
        returns (DexRequest memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = _generateUserSignatureComponents(receiver, privateKey, dexRequestData);
        return DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: id,
            dexRequestData: dexRequestData,
            r: r,
            s: s,
            v: v
        });
    }

    /// @notice Helper function to construct DexRequest array
    /// @param id Account or strategy provider ID
    /// @param receiver Receiver address
    /// @param privateKey Private key
    /// @param dexRequestData DexRequestData structure
    /// @return DexRequest array
    function _createDexRequestArray(
        bytes32 id,
        address receiver,
        uint256 privateKey,
        DexRequestData memory dexRequestData
    ) internal view returns (DexRequest[] memory) {
        DexRequest[] memory dexRequests = new DexRequest[](1);
        dexRequests[0] = _createDexRequest(id, receiver, privateKey, dexRequestData);
        return dexRequests;
    }

    /// @notice Check LP account token info
    /// @param accountId LP account ID
    /// @param expectedUnAllocatedAssets Expected unAllocated assets
    /// @param expectedFrozenShares Expected frozen shares
    /// @param expectedPendingShares Expected pending shares
    function _assertLPAccountTokenInfo(
        bytes32 accountId,
        uint256 expectedUnAllocatedAssets,
        uint256 expectedFrozenShares,
        uint256 expectedPendingShares
    ) internal view {
        (
            , // shares
            uint256 unAllocatedAssets,
            uint256 frozenShares,
            uint256 pendingShares
        ) = svLedger.accountTokenInfo(accountId, USDC_HASH);

        assertEq(unAllocatedAssets, expectedUnAllocatedAssets, "Unexpected unAllocatedAssets");
        assertEq(frozenShares, expectedFrozenShares, "Unexpected frozenShares");
        assertEq(pendingShares, expectedPendingShares, "Unexpected pendingShares");
    }

    /// @notice Check SP strategy fund token info
    /// @param spId Strategy provider ID
    /// @param expectedUnAllocatedAssets Expected unAllocated assets
    /// @param expectedFrozenShares Expected frozen shares
    function _assertSPTokenInfo(bytes32 spId, uint256 expectedUnAllocatedAssets, uint256 expectedFrozenShares)
        internal
        view
    {
        (
            , // pendingState
            , // performanceFee
            , // fundAssetsAfterFee
            uint256 unAllocatedAssets,
            uint256 frozenShares,
            , // mainShares
            , // strategyProviderShares
            , // totalAssets
            , // totalShares
                // hwm
        ) = svLedger.strategyFundTokenInfo(spId, USDC_HASH);

        assertEq(unAllocatedAssets, expectedUnAllocatedAssets, "Unexpected SP unAllocatedAssets");
        assertEq(frozenShares, expectedFrozenShares, "Unexpected SP frozenShares");
    }

    /// @notice Check if request is handled
    /// @param requestId Request ID
    function _assertRequestHandled(uint256 requestId) internal view {
        assertTrue(svLedger.isDexRequestHandled(requestId), "Request should be marked as handled");
    }

    /// @notice Combine check for LP deposit result
    /// @param accountId LP account ID
    /// @param requestId Request ID
    /// @param expectedUnAllocatedAssets Expected increase in unAllocated assets
    function _assertLPDepositResult(bytes32 accountId, uint256 requestId, uint256 expectedUnAllocatedAssets)
        internal
        view
    {
        _assertLPAccountTokenInfo(accountId, expectedUnAllocatedAssets, 0, 0);
        _assertRequestHandled(requestId);
    }

    /// @notice Combine check for LP withdrawal result
    /// @param accountId LP account ID
    /// @param requestId Request ID
    /// @param expectedFrozenShares Expected frozen shares
    /// @param expectedPendingShares Expected remaining pending shares
    function _assertLPWithdrawResult(
        bytes32 accountId,
        uint256 requestId,
        uint256 expectedFrozenShares,
        uint256 expectedPendingShares
    ) internal view {
        _assertLPAccountTokenInfo(accountId, 0, expectedFrozenShares, expectedPendingShares);
        _assertRequestHandled(requestId);
    }

    /// @notice Combine check for SP deposit result
    /// @param spId Strategy provider ID
    /// @param requestId Request ID
    /// @param expectedUnAllocatedAssets Expected unAllocated assets
    function _assertSPDepositResult(bytes32 spId, uint256 requestId, uint256 expectedUnAllocatedAssets) internal view {
        _assertSPTokenInfo(spId, expectedUnAllocatedAssets, 0);
        _assertRequestHandled(requestId);
    }

    /// @notice  Access Control - Only operator can call handleDexRequests
    function testRevertHandleDexRequestsUnauthorized() public {
        uint256 amount = 1000e6;
        uint256 requestId = 100;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Should revert when called by non-operator
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("InvalidOperator()"));
        svLedger.handleDexRequests(dexRequests, engineSignature);
    }

    /// @notice Duplicate request handling - Should revert on duplicate requestId
    function testRevertHandleDexRequestsDuplicate() public {
        uint256 amount = 1000e6;
        uint256 requestId = 101;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // First call should succeed
        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Second call with same requestId should revert
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("AlreadyCalled()"));
        svLedger.handleDexRequests(dexRequests, engineSignature);
    }

    /// @notice Invalid engine signature should revert
    function testRevertHandleDexRequestsInvalidEngineSignature() public {
        uint256 amount = 1000e6;
        uint256 requestId = 103;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);

        // Create invalid signature
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        vm.prank(operator);
        vm.expectRevert(); // Should revert due to invalid signature
        svLedger.handleDexRequests(dexRequests, invalidSignature);
    }

    /// @notice SP withdraw success case
    function testHandleDexRequestsSPWithdraw() public {
        uint256 withdrawAmount = 500e6;
        uint256 initialShares = 1000e6;
        uint256 requestId = 104;

        // Set up SP with pending strategy provider shares
        bytes32[] memory spIds = new bytes32[](1);
        spIds[0] = spId;
        svLedger.setSpPendingShares(spIds, initialShares);

        DexRequestData memory dexRequestData =
            _createDexRequestData(PayloadType.SP_WITHDRAW, requestId, sp, withdrawAmount);
        DexRequest[] memory dexRequests = _createDexRequestArray(spId, sp, spPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify SP frozen shares increased
        _assertSPTokenInfo(spId, 0, withdrawAmount);
        _assertRequestHandled(requestId);
    }

    /// @notice SP withdraw insufficient balance
    function testHandleDexRequestsSPWithdrawInsufficientBalance() public {
        uint256 withdrawAmount = 1000e6;
        uint256 availableShares = 500e6;
        uint256 requestId = 105;

        // Set up SP with insufficient shares
        bytes32[] memory spIds = new bytes32[](1);
        spIds[0] = spId;
        svLedger.setSpPendingShares(spIds, availableShares);

        DexRequestData memory dexRequestData =
            _createDexRequestData(PayloadType.SP_WITHDRAW, requestId, sp, withdrawAmount);
        DexRequest[] memory dexRequests = _createDexRequestArray(spId, sp, spPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify no frozen shares were added due to insufficient balance
        _assertSPTokenInfo(spId, 0, 0);
        _assertRequestHandled(requestId);
    }

    /// @notice Invalid user signature should revert
    function testRevertHandleDexRequestsInvalidUserSignature() public {
        uint256 amount = 1000e6;
        uint256 requestId = 106;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);

        // Create request with invalid user signature
        DexRequest[] memory dexRequests = new DexRequest[](1);
        dexRequests[0] = DexRequest({
            chainType: ChainType.EVM,
            chainId: block.chainid,
            id: lpId,
            dexRequestData: dexRequestData,
            r: bytes32(0), // Invalid signature components
            s: bytes32(0),
            v: 0
        });

        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        vm.expectRevert(); // Should revert due to invalid user signature
        svLedger.handleDexRequests(dexRequests, engineSignature);
    }

    /// @notice Empty requests array
    function testHandleDexRequestsEmptyArray() public {
        DexRequest[] memory emptyRequests = new DexRequest[](0);
        bytes memory engineSignature = _generateEngineSignature(emptyRequests);

        // Should handle empty array gracefully
        vm.prank(operator);
        svLedger.handleDexRequests(emptyRequests, engineSignature);

        // No state changes should occur
    }

    /// @notice Zero amount request
    function testHandleDexRequestsZeroAmount() public {
        uint256 zeroAmount = 0;
        uint256 requestId = 107;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, zeroAmount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify zero amount deposit (should still be handled)
        _assertLPDepositResult(lpId, requestId, zeroAmount);
    }

    /// @notice Event emission verification
    function testHandleDexRequestsEventEmission() public {
        uint256 amount = 1000e6;
        uint256 requestId = 108;

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Expect DexRequestsHandled event
        vm.expectEmit(true, true, true, true);
        emit DexRequestsHandled(dexRequests[0]);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);
    }

    /// @notice Event emission for insufficient withdrawal
    function testHandleDexRequestsWithdrawNotEnoughEvent() public {
        uint256 withdrawAmount = 1000e6;
        uint256 insufficientShares = 500e6;
        uint256 requestId = 109;

        // Set insufficient shares for withdrawal
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = lpId;
        svLedger.setAccountPendingShares(accountIds, insufficientShares);

        DexRequestData memory dexRequestData =
            _createDexRequestData(PayloadType.LP_WITHDRAW, requestId, lp, withdrawAmount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        // Expect DexWithdrawNotEnough event
        vm.expectEmit(true, true, true, true);
        emit DexWithdrawNotEnough(requestId);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);
    }

    /// @notice Mixed LP and SP operations
    function testHandleDexRequestsMixedLPSPOperations() public {
        uint256 lpDepositAmount = 1000e6;
        uint256 spWithdrawAmount = 500e6;
        uint256 initialSPShares = 800e6;

        // Set up SP with shares for withdrawal
        bytes32[] memory spIds = new bytes32[](1);
        spIds[0] = spId;
        svLedger.setSpPendingShares(spIds, initialSPShares);

        // Create mixed requests: LP deposit + SP withdraw
        DexRequest[] memory dexRequests = new DexRequest[](2);

        // LP deposit
        DexRequestData memory lpData = _createDexRequestData(PayloadType.LP_DEPOSIT, 110, lp, lpDepositAmount);
        dexRequests[0] = _createDexRequest(lpId, lp, lpPrivateKey, lpData);

        // SP withdraw
        DexRequestData memory spData = _createDexRequestData(PayloadType.SP_WITHDRAW, 111, sp, spWithdrawAmount);
        dexRequests[1] = _createDexRequest(spId, sp, spPrivateKey, spData);

        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify both operations succeeded
        _assertLPDepositResult(lpId, 110, lpDepositAmount);
        _assertSPTokenInfo(spId, 0, spWithdrawAmount);
        _assertRequestHandled(111);
    }

    /// @notice Large batch processing
    function testHandleDexRequestsLargeBatch() public {
        uint256 batchSize = 10;
        uint256 amount = 100e6;

        // Create large batch of LP deposits
        DexRequest[] memory dexRequests = new DexRequest[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            DexRequestData memory data = _createDexRequestData(PayloadType.LP_DEPOSIT, 200 + i, lp, amount);
            dexRequests[i] = _createDexRequest(lpId, lp, lpPrivateKey, data);
        }

        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify all requests were handled
        for (uint256 i = 0; i < batchSize; i++) {
            _assertRequestHandled(200 + i);
        }

        // Verify total accumulated assets
        (, uint256 totalUnAllocatedAssets,,) = svLedger.accountTokenInfo(lpId, USDC_HASH);
        assertEq(totalUnAllocatedAssets, amount * batchSize);
    }

    /// @notice State consistency after failed operations
    function testHandleDexRequestsStateConsistencyAfterFailures() public {
        uint256 successAmount = 500e6;
        uint256 failAmount = 1000e6;
        uint256 availableShares = 300e6; // Insufficient for failAmount

        // Set up account with limited shares
        bytes32[] memory accountIds = new bytes32[](1);
        accountIds[0] = lpId;
        svLedger.setAccountPendingShares(accountIds, availableShares);

        // Create requests: one success, one fail
        DexRequest[] memory dexRequests = new DexRequest[](2);

        // This should succeed
        DexRequestData memory successData = _createDexRequestData(PayloadType.LP_DEPOSIT, 300, lp, successAmount);
        dexRequests[0] = _createDexRequest(lpId, lp, lpPrivateKey, successData);

        // This should fail (insufficient shares)
        DexRequestData memory failData = _createDexRequestData(PayloadType.LP_WITHDRAW, 301, lp, failAmount);
        dexRequests[1] = _createDexRequest(lpId, lp, lpPrivateKey, failData);

        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // Verify state consistency: success operation processed, fail operation handled but no state change
        (, uint256 unAllocatedAssets, uint256 frozenShares, uint256 pendingShares) =
            svLedger.accountTokenInfo(lpId, USDC_HASH);

        assertEq(unAllocatedAssets, successAmount, "Successful deposit should be recorded");
        assertEq(frozenShares, 0, "Failed withdrawal should not freeze shares");
        assertEq(pendingShares, availableShares, "Pending shares should remain unchanged");

        // Both requests should be marked as handled
        _assertRequestHandled(300);
        _assertRequestHandled(301);
    }

    /// @notice Request handling status verification
    function testHandleDexRequestsHandlingStatus() public {
        uint256 amount = 1000e6;
        uint256 requestId = 400;

        // Initially request should not be handled
        assertFalse(svLedger.isDexRequestHandled(requestId));

        DexRequestData memory dexRequestData = _createDexRequestData(PayloadType.LP_DEPOSIT, requestId, lp, amount);
        DexRequest[] memory dexRequests = _createDexRequestArray(lpId, lp, lpPrivateKey, dexRequestData);
        bytes memory engineSignature = _generateEngineSignature(dexRequests);

        vm.prank(operator);
        svLedger.handleDexRequests(dexRequests, engineSignature);

        // After handling, request should be marked as handled
        assertTrue(svLedger.isDexRequestHandled(requestId));
    }
}
