pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract IssueTest is Test {
    function setUp() public {}

    //forge test --match-test test_calldata --rpc-url  https://gateway.tenderly.co/public/sepolia -vvvv
    function test_calldata() public {
        address target = 0xF5b12d5F1db6DAB8C7c0561152b5e4bb8fD5eb38; //!contract address
        vm.prank(0x4e9FeE6661422BBD72e8133121E9387bf238C2e1);
        // IERC721(address(0x4000b670D2dE065610C78FaE88f479e6BB67b593))
        //     .setApprovalForAll(
        //         0x1E0049783F008A0085193E00003D00cd54003c71,
        //         true
        //     );
        // vm.prank(0x3382A156b02032395473442f357aECbBA16C415C);
        bytes
            memory data = hex"91ccaefd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e9fee6661422bbd72e8133121e9387bf238c2e100000000000000000000000075faf114eafb1bdbe2f0316df893fd58ce46aa4d00000000000000000000000000000000000000000000000000000000000186a095d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b";
        target.call{value: 80692204196641}(data);
    }
}
