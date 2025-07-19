// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

library VaultUtils {
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

    /**
     * @notice Validate strategy provider ID
     * @param vault The address of the vault contract
     * @param strategyProvider The address of the strategy provider
     * @param brokerHash The broker hash
     * @param strategyProviderId The strategy provider ID to validate
     * @return True if the strategy provider ID is valid
     */
    function validateSPId(address vault, address strategyProvider, bytes32 brokerHash, bytes32 strategyProviderId)
        internal
        pure
        returns (bool)
    {
        return getStrategyProviderId(vault, strategyProvider, brokerHash) == strategyProviderId;
    }

    /**
     * @notice Validate account ID
     * @param account The address of the account
     * @param brokerHash The broker hash
     * @param accountId The account ID to validate
     * @return True if the account ID is valid
     */
    function validateAccountId(address account, bytes32 brokerHash, bytes32 accountId) internal pure returns (bool) {
        return getAccountId(account, brokerHash) == accountId;
    }

    /**
     * @notice Validate ID (can be either strategy provider ID or account ID)
     * @param vault The address of the vault contract
     * @param receiver The address of the receiver (can be strategy provider or account)
     * @param brokerHash The broker hash
     * @param id The ID to validate
     * @return True if the ID is valid as either strategy provider ID or account ID
     */
    function validateId(address vault, address receiver, bytes32 brokerHash, bytes32 id) internal pure returns (bool) {
        return validateSPId(vault, receiver, brokerHash, id) || validateAccountId(receiver, brokerHash, id);
    }
}
