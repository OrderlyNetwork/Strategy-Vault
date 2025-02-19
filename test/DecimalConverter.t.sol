// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/lib/utils/DecimalConverter.sol";

contract DecimalConverterTest is Test {
    using DecimalConverter for uint256;

    function testSameDecimals() public pure {
        uint256 amount = 1000;
        uint128 decimal = 18;
        assertEq(amount.convertDecimal(decimal, decimal), 1000);
    }

    function testHigherToLowerDecimals() public pure {
        uint256 amount = 1000 * 10**18; // 1000 tokens with 18 decimals
        uint128 srcDecimal = 18;
        uint128 dstDecimal = 6;
        
        // check should be 1000 * 10**6
        assertEq(amount.convertDecimal(srcDecimal, dstDecimal), 1000 * 10**6);
    }

    function testLowerToHigherDecimals() public  pure{
        uint256 amount = 1000 * 10**6; // 1000 tokens with 6 decimals
        uint128 srcDecimal = 6;
        uint128 dstDecimal = 18;
        
        // check
        assertEq(amount.convertDecimal(srcDecimal, dstDecimal), 1000 * 10**18);
    }

    function testZeroAmount() public pure{
        uint256 amount = 0;
        assertEq(amount.convertDecimal(18, 6), 0);
        assertEq(amount.convertDecimal(6, 18), 0);
    }

    function testRevertOnOverflow() public {
        uint256 amount = type(uint256).max;
        uint128 srcDecimal = 6;
        uint128 dstDecimal = 18;
        
        vm.expectRevert();
        amount.convertDecimal(srcDecimal, dstDecimal);
    }

    function testSpecificCases() public pure{
        uint256 oneEth = 1 ether; // 1 * 10**18
        assertEq(oneEth.convertDecimal(18, 6), 1_000_000);

        uint256 oneUsdc = 1_000_000; // 1 USDC in 6 decimals
        assertEq(oneUsdc.convertDecimal(6, 18), 1 ether);

        uint256 halfEth = 0.5 ether;
        assertEq(halfEth.convertDecimal(18, 8), 50_000_000);
    }
}