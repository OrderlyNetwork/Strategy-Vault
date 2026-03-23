const { ethers } = require("hardhat")
const deployment = require('../../../deployment/deployment.json');
const cvDeployment = require('../../../deployment/community.json');
const config = require('../../../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../../utils/getId');

async function main() {
    //!need to change with your env and params
    const env = "dev";
    const cv = "woo"; // Community vault name (optional)
    const userAddress = "0x4e9FeE6661422BBD72e8133121E9387bf238C2e1"; // User address for accountId query
    const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"; // Broker hash

    console.log(`\n${'='.repeat(80)}`);
    console.log(`📊 Vault ID Information Query - ${env.toUpperCase()} Environment`);
    console.log(`${'='.repeat(80)}\n`);

    // Protocol Vault Information
    console.log(`🏦 Protocol Vault Information:`);
    console.log(`${'─'.repeat(80)}`);
    const pvVault = deployment[env].protocolVault;
    console.log(`   Vault Address: ${pvVault}`);
    console.log(`   Vault ID:      ${getVaultId(pvVault, broker)}`);
    console.log(`   Broker Hash:   ${broker}`);
    console.log(`   SP ID:         ${getStrategyProviderId(pvVault, deployment[env].allowedSP, broker)}`);

    // User account ID for Protocol Vault
    if (userAddress) {
        const accountId = getAccountId(userAddress, broker);
        console.log(`\n   👤 User Account ID:`);
        console.log(`   User Address:  ${userAddress}`);
        console.log(`   Account ID:    ${accountId}`);
    }

    // Community Vault Information (if specified)
    if (cv && cvDeployment[cv]) {
        console.log(`\n${'─'.repeat(80)}`);
        console.log(`🏛️  Community Vault Information - ${cv}:`);
        console.log(`${'─'.repeat(80)}`);

        const cvVault = cvDeployment[cv].address;
        const cvBroker = cvDeployment[cv].broker;
        const cvSp = cvDeployment[cv].sp;

        console.log(`   Vault Address: ${cvVault}`);
        console.log(`   Vault ID:      ${getVaultId(cvVault, cvBroker)}`);
        console.log(`   Broker Hash:   ${cvBroker}`);
        console.log(`   SP Address:    ${cvSp}`);

        // Strategy Provider ID
        const spId = getStrategyProviderId(cvVault, cvSp, cvBroker);
        console.log(`\n   🎯 Strategy Provider ID:`);
        console.log(`   SP ID:         ${spId}`);

        // User account ID for Community Vault
        if (userAddress) {
            const cvAccountId = getAccountId(userAddress, cvBroker);
            console.log(`\n   👤 User Account ID:`);
            console.log(`   User Address:  ${userAddress}`);
            console.log(`   Account ID:    ${cvAccountId}`);
        }

        // Additional CV Info
        if (cvDeployment[cv].vaultId) {
            console.log(`\n   ℹ️  Additional Info:`);
            console.log(`   Stored Vault ID: ${cvDeployment[cv].vaultId}`);
            console.log(`   Stored SP ID:    ${cvDeployment[cv].spId || 'N/A'}`);
        }
    }
}

main().catch(error => {
    console.error(error)
    process.exitCode = 1
})
