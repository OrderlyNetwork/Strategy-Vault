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
    /**
     * @notice Calculate the strategy provider ID
     * @param vault The address of the vault contract
     * @param strategyProvider The address of the strategy provider
     * @param brokerHash The broker hash
     * @return The strategy provider ID
     */

    function getStrategyProviderId(address vault, address strategyProvider, bytes32 brokerHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(vault, strategyProvider, brokerHash));
    }

    /**
     * @notice Calculate the account ID
     * @param account The address of the account
     * @param brokerHash The broker hash
     * @return The account ID
     */
    function getAccountId(address account, bytes32 brokerHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, brokerHash));
    }
}
