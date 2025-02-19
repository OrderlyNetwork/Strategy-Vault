const { ethers } = require("ethers");

// _getAccountId implementation
function getAccountId(account, brokerHash) {
    return ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "bytes32"],
            [account, brokerHash]
        )
    );
}

// _getStrategyProviderId implementation
function getStrategyProviderId(contractAddress, strategyProvider, brokerHash) {
    return ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "bytes32"],
            [contractAddress, strategyProvider, brokerHash]
        )
    );
}

// _getVaultId implementation 
function getVaultId(contractAddress, brokerHash) {
    return ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "bytes32"],
            [contractAddress, brokerHash]
        )
    );
}

module.exports = {
    getAccountId,
    getStrategyProviderId, 
    getVaultId
};