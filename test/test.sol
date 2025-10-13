pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract IssueTest is Test {
    function setUp() public {}

    //forge test --match-test test_calldata --rpc-url  https://gateway.tenderly.co/public/sepolia -vvvv
    //orderly sepolia: https://testnet-rpc.orderly.org
    //arb - https://sepolia-rollup.arbitrum.io/rpc
    //base: https://sepolia.base.org
    function test_calldata() public {
        address target = 0xaEBc84930b3fFB48A393717342078F1c69cb5f0C; //!contract address
        vm.prank(0x8211b71Ea278d6Dbe85bb1E5ec8D4350C3564182);
        // IERC721(address(0x4000b670D2dE065610C78FaE88f479e6BB67b593))
        //     .setApprovalForAll(
        //         0x1E0049783F008A0085193E00003D00cd54003c71,
        //         true
        //     );
        // vm.prank(0x3382A156b02032395473442f357aECbBA16C415C);
        bytes memory data =
            hex"91ccaefd00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008211b71ea278d6dbe85bb1e5ec8d4350c3564182000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e0000000000000000000000000000000000000000000000000000000002faf0806ca2f644ef7bd6d75953318c7f2580014941e753b3c6d54da56b3bf75dd14dfc";
        target.call{value: 500000000000000}(data);
    }
}
