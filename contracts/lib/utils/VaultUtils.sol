// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

library VaultUtils {
    error InvalidStrategyProviderId();

    function checkStrategyProviderId(
        address vault,
        address strategyProvider,
        bytes32 brokerHash,
        bytes32 strategyProviderId
    ) internal pure {
        if (keccak256(abi.encode(vault, strategyProvider, brokerHash)) != strategyProviderId) {
            revert InvalidStrategyProviderId();
        }
    }
}
