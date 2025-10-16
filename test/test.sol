pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract IssueTest is Test {
    function setUp() public {}

    //forge test --match-test test_calldata --rpc-url  https://gateway.tenderly.co/public/sepolia -vvvv
    function test_calldata() public {
        address target = 0x510dD61a988797114A9a51b0d228E894037BD9cb; //!contract address
        vm.prank(0x4e9FeE6661422BBD72e8133121E9387bf238C2e1);
        // IERC721(address(0x4000b670D2dE065610C78FaE88f479e6BB67b593))
        //     .setApprovalForAll(
        //         0x1E0049783F008A0085193E00003D00cd54003c71,
        //         true
        //     );
        // vm.prank(0x3382A156b02032395473442f357aECbBA16C415C);
        bytes memory data =
            hex"ced10e9100000000000000000000000000000000000000000000000000000000000ae3f30000000000000000000000000000000000000000000000000000000000009d42";
        target.call{value: 0}(data);
    }
}
