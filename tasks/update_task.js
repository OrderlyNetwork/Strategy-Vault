const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const deployment = require('../deployment/deployment.json');
const cvDeployment = require('../deployment/community.json');
const config = require('../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../scripts/utils/getId');
const { checkNetworkEnvRestrictions, getEndpointV2 } = require('./utils');
const { task } = require('hardhat/config');

task("deploy-impl", "Deploy implementation contracts on a single chain")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        console.log(`\n🚀 Deploying implementation contracts on ${currentNetwork} for ${taskArgs.env} environment...\n`);

        // Determine if it's an Orderly chain
        const isOrderlyChain = currentNetwork.includes('orderly');

        if (isOrderlyChain) {
            // Deploy on Orderly chain: LedgerCoreImpl, LedgerExtension, ProtocolVaultLedger
            await deployOrderlyContracts(taskArgs.env, currentNetwork);
        } else {
            // Deploy on EVM chain: ProtocolVault impl and VaultCrossChainManager impl
            await deployEVMContracts(taskArgs.env, currentNetwork);
        }

        console.log(`\n✅ Deployment completed successfully on ${currentNetwork}!\n`);
    });

task("deploy-all-chains", "Deploy implementation contracts on all configured chains")
    .addParam("env", "Deployment environment (dev/qa/staging)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')} (mainnet not supported for batch deployment)`);
        }

        console.log(`\n${'='.repeat(80)}`);
        console.log(`🚀 Starting batch deployment for ${taskArgs.env} environment`);
        console.log(`${'='.repeat(80)}\n`);

        const results = {
            success: [],
            failed: []
        };

        // Get network configurations
        const deployNetworks = getDeployNetworks(taskArgs.env);

        // Deploy on Orderly chain first
        console.log(`\n📍 Step 1: Deploying on Orderly chain (orderly_sepolia)...\n`);
        try {
            execSync(`npx hardhat deploy-impl --env ${taskArgs.env} --network orderly_sepolia`, {
                stdio: 'inherit',
                cwd: process.cwd()
            });
            results.success.push({ network: 'orderly_sepolia', contracts: ['ProtocolVaultLedger', 'VaultCrossChainManager', 'LedgerCoreImpl', 'LedgerExtension'] });
        } catch (error) {
            console.error(`❌ Failed to deploy on orderly_sepolia: ${error.message}`);
            results.failed.push({ network: 'orderly_sepolia', error: error.message });
        }

        // Deploy on EVM chains
        console.log(`\n📍 Step 2: Deploying on EVM chains...\n`);
        for (const network of deployNetworks.evm) {
            console.log(`\n${'─'.repeat(80)}`);
            console.log(`📦 Deploying on ${network}...`);
            console.log(`${'─'.repeat(80)}\n`);

            try {
                execSync(`npx hardhat deploy-impl --env ${taskArgs.env} --network ${network}`, {
                    stdio: 'inherit',
                    cwd: process.cwd()
                });
                results.success.push({ network, contracts: ['ProtocolVault', 'VaultCrossChainManager'] });
            } catch (error) {
                console.error(`❌ Failed to deploy on ${network}: ${error.message}`);
                results.failed.push({ network, error: error.message });
            }
        }

        // Print summary
        printDeploymentSummary(results, taskArgs.env);
    });

task("upgrade", "Upgrade contracts on a single chain")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        console.log(`\n🔄 Upgrading implementation contracts on ${currentNetwork} for ${taskArgs.env} environment...\n`);

        // Determine if it's an Orderly chain
        const isOrderlyChain = currentNetwork.includes('orderly');

        if (isOrderlyChain) {
            // Upgrade on Orderly chain: ProtocolVaultLedger
            await upgradeOrderlyContracts(taskArgs.env, currentNetwork);
        } else {
            // Upgrade on EVM chain: ProtocolVault and VaultCrossChainManager
            await upgradeEVMContracts(taskArgs.env, currentNetwork);
        }

        console.log(`\n✅ Upgrade completed successfully on ${currentNetwork}!\n`);
    });

task("upgrade-all-chains", "Upgrade implementation contracts on all configured chains")
    .addParam("env", "Deployment environment (dev/qa/staging)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')} (mainnet not supported for batch upgrade)`);
        }

        console.log(`\n${'='.repeat(80)}`);
        console.log(`🔄 Starting batch upgrade for ${taskArgs.env} environment`);
        console.log(`${'='.repeat(80)}\n`);

        const results = {
            success: [],
            failed: []
        };

        // Get network configurations
        const deployNetworks = getDeployNetworks(taskArgs.env);

        // Upgrade on Orderly chain first
        console.log(`\n📍 Step 1: Upgrading on Orderly chain (orderly_sepolia)...\n`);
        try {
            execSync(`npx hardhat upgrade --env ${taskArgs.env} --network orderly_sepolia`, {
                stdio: 'inherit',
                cwd: process.cwd()
            });
            results.success.push({ network: 'orderly_sepolia', contracts: ['ProtocolVaultLedger', 'VaultCrossChainManager'] });
        } catch (error) {
            console.error(`❌ Failed to upgrade on orderly_sepolia: ${error.message}`);
            results.failed.push({ network: 'orderly_sepolia', error: error.message });
        }

        // Upgrade on EVM chains
        console.log(`\n📍 Step 2: Upgrading on EVM chains...\n`);
        for (const network of deployNetworks.evm) {
            console.log(`\n${'─'.repeat(80)}`);
            console.log(`🔄 Upgrading on ${network}...`);
            console.log(`${'─'.repeat(80)}\n`);

            try {
                execSync(`npx hardhat upgrade --env ${taskArgs.env} --network ${network}`, {
                    stdio: 'inherit',
                    cwd: process.cwd()
                });
                results.success.push({ network, contracts: ['ProtocolVault', 'VaultCrossChainManager'] });
            } catch (error) {
                console.error(`❌ Failed to upgrade on ${network}: ${error.message}`);
                results.failed.push({ network, error: error.message });
            }
        }

        // Print summary
        printUpgradeSummary(results, taskArgs.env);
    });

// Deploy contracts on Orderly chain
async function deployOrderlyContracts(env, network) {
    checkNetworkEnvRestrictions(network, env);

    console.log("📦 Step 1: Deploying ProtocolVaultLedger implementation...");
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ledgerImpl = await deployProtocolVaultLedgerImpl(ProtocolVaultLedger);

    console.log("\n📦 Step 2: Deploying VaultCrossChainManager implementation...");
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const crossChainManagerImpl = await deployVaultCrossChainManagerImpl(VaultCrossChainManager);

    console.log("\n📦 Step 3: Deploying LedgerCoreImpl...");
    const LedgerCoreImpl = await ethers.getContractFactory("LedgerCoreImpl");
    const coreImpl = await deployLedgerCoreImpl(LedgerCoreImpl);

    console.log("\n📦 Step 4: Deploying LedgerExtension...");
    const LedgerExtension = await ethers.getContractFactory("LedgerExtension");
    const extension = await deployLedgerExtension(LedgerExtension);

    console.log("\n✅ Orderly chain deployment completed!");
    console.log(`   - ProtocolVaultLedger: ${ledgerImpl}`);
    console.log(`   - VaultCrossChainManager: ${crossChainManagerImpl}`);
    console.log(`   - LedgerCoreImpl: ${coreImpl}`);
    console.log(`   - LedgerExtension: ${extension}`);
}

// Deploy contracts on EVM chain
async function deployEVMContracts(env, network) {
    console.log("📦 Step 1: Deploying ProtocolVault implementation...");
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const protocolVaultImpl = await deployProtocolVaultImpl(ProtocolVault);

    console.log("\n📦 Step 2: Deploying VaultCrossChainManager implementation...");
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const crossChainManagerImpl = await deployVaultCrossChainManagerImpl(VaultCrossChainManager);

    console.log("\n✅ EVM chain deployment completed!");
    console.log(`   - ProtocolVault: ${protocolVaultImpl}`);
    console.log(`   - VaultCrossChainManager: ${crossChainManagerImpl}`);
}

// Helper: Deploy LedgerCoreImpl
async function deployLedgerCoreImpl(LedgerCoreImpl) {
    const LedgerCoreImplContract = await LedgerCoreImpl.deploy();
    await LedgerCoreImplContract.waitForDeployment();
    const implAddr = LedgerCoreImplContract.target;

    console.log(`   ✓ LedgerCoreImpl deployed: ${implAddr}`);

    // Verify contract
    try {
        console.log(`   ⏳ Verifying LedgerCoreImpl...`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`   ✓ LedgerCoreImpl verified`);
    } catch (error) {
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.log(`   ⚠️ Verification failed: ${error.message}`);
        } else {
            console.log(`   ✓ Already verified`);
        }
    }

    return implAddr;
}

// Helper: Deploy ProtocolVaultLedger implementation
async function deployProtocolVaultLedgerImpl(ProtocolVaultLedger) {
    const ProtocolVaultLedgerContract = await ProtocolVaultLedger.deploy();
    await ProtocolVaultLedgerContract.waitForDeployment();
    const implAddr = ProtocolVaultLedgerContract.target;

    console.log(`   ✓ ProtocolVaultLedger impl deployed: ${implAddr}`);

    // Verify contract
    try {
        console.log(`   ⏳ Verifying ProtocolVaultLedger...`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`   ✓ ProtocolVaultLedger verified`);
    } catch (error) {
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.log(`   ⚠️ Verification failed: ${error.message}`);
        } else {
            console.log(`   ✓ Already verified`);
        }
    }

    return implAddr;
}

// Helper: Deploy LedgerExtension
async function deployLedgerExtension(LedgerExtension) {
    const LedgerExtensionContract = await LedgerExtension.deploy();
    await LedgerExtensionContract.waitForDeployment();
    const implAddr = LedgerExtensionContract.target;

    console.log(`✓ LedgerExtension deployed: ${implAddr}`);

    // Verify contract
    try {
        console.log(`   ⏳ Verifying LedgerExtension...`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`   ✓ LedgerExtension verified`);
    } catch (error) {
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.log(`   ⚠️ Verification failed: ${error.message}`);
        } else {
            console.log(`   ✓ Already verified`);
        }
    }

    return implAddr;
}

// Helper: Configure ProtocolVaultLedger
async function configureProtocolVaultLedger(env, coreImpl, extension) {
    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    );

    console.log(`   ⏳ Setting Core to: ${coreImpl}`);
    let tx = await protocolVaultLedger.setCore(coreImpl);
    await tx.wait();
    console.log(`   ✓ Core set successfully`);

    console.log(`   ⏳ Setting Extension to: ${extension}`);
    tx = await protocolVaultLedger.setExtension(extension);
    await tx.wait();
    console.log(`   ✓ Extension set successfully`);
}

// Helper: Deploy ProtocolVault implementation
async function deployProtocolVaultImpl(ProtocolVault) {
    const ProtocolVaultContract = await ProtocolVault.deploy();
    await ProtocolVaultContract.waitForDeployment();
    const implAddr = ProtocolVaultContract.target;

    console.log(`   ✓ ProtocolVault impl deployed: ${implAddr}`);

    // Verify contract
    try {
        console.log(`   ⏳ Verifying ProtocolVault...`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`   ✓ ProtocolVault verified`);
    } catch (error) {
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.log(`   ⚠️ Verification failed: ${error.message}`);
        } else {
            console.log(`   ✓ Already verified`);
        }
    }

    return implAddr;
}

// Helper: Deploy VaultCrossChainManager implementation
async function deployVaultCrossChainManagerImpl(VaultCrossChainManager) {
    const VaultCrossChainManagerContract = await VaultCrossChainManager.deploy();
    await VaultCrossChainManagerContract.waitForDeployment();
    const implAddr = VaultCrossChainManagerContract.target;

    console.log(`   ✓ VaultCrossChainManager impl deployed: ${implAddr}`);

    // Verify contract
    try {
        console.log(`   ⏳ Verifying VaultCrossChainManager...`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`   ✓ VaultCrossChainManager verified`);
    } catch (error) {
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.log(`   ⚠️ Verification failed: ${error.message}`);
        } else {
            console.log(`   ✓ Already verified`);
        }
    }

    return implAddr;
}

// Helper: Get deploy networks from deployment.json
function getDeployNetworks(env) {
    // Read from deployedNetwork array and filter out adapter-only networks
    const deployedNetworks = deployment[env].deployedNetwork || [];
    const evmNetworks = deployedNetworks
        .filter(n => !n.includes('adapter:'))
        .map(n => n.trim());

    return {
        orderly: ['orderly_sepolia'],
        evm: evmNetworks
    };
}

// Helper: Print deployment summary
function printDeploymentSummary(results, env) {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`📊 Deployment Summary for ${env} environment`);
    console.log(`${'='.repeat(80)}\n`);

    if (results.success.length > 0) {
        console.log(`✅ Successfully deployed on ${results.success.length} chain(s):`);
        results.success.forEach(({ network, contracts }) => {
            console.log(`   • ${network}: ${contracts.join(', ')}`);
        });
    }

    if (results.failed.length > 0) {
        console.log(`\n❌ Failed to deploy on ${results.failed.length} chain(s):`);
        results.failed.forEach(({ network, error }) => {
            console.log(`   • ${network}: ${error}`);
        });
    }

    console.log(`\n${'='.repeat(80)}\n`);

    if (results.failed.length > 0) {
        console.log(`⚠️  Some deployments failed. Please check the errors above and retry manually.`);
        console.log(`   Use: npx hardhat deploy-impl --env ${env} --network <network_name>\n`);
    } else {
        console.log(`🎉 All deployments completed successfully!\n`);
    }
}

// Upgrade contracts on Orderly chain
async function upgradeOrderlyContracts(env, network) {
    checkNetworkEnvRestrictions(network, env);

    // Step 1: Deploy new ProtocolVaultLedger implementation
    console.log("📦 Step 1: Deploying new ProtocolVaultLedger implementation...");
    const ProtocolVaultLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const ledgerImpl = await deployProtocolVaultLedgerImpl(ProtocolVaultLedger);

    // Step 2: Deploy new VaultCrossChainManager implementation
    console.log("\n📦 Step 2: Deploying new VaultCrossChainManager implementation...");
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const crossChainManagerImpl = await deployVaultCrossChainManagerImpl(VaultCrossChainManager);

    // Step 3: Deploy new LedgerCoreImpl
    console.log("\n📦 Step 3: Deploying new LedgerCoreImpl...");
    const LedgerCoreImpl = await ethers.getContractFactory("LedgerCoreImpl");
    const coreImpl = await deployLedgerCoreImpl(LedgerCoreImpl);

    // Step 4: Deploy new LedgerExtension
    console.log("\n📦 Step 4: Deploying new LedgerExtension...");
    const LedgerExtension = await ethers.getContractFactory("LedgerExtension");
    const extension = await deployLedgerExtension(LedgerExtension);

    // Step 5: Configure ProtocolVaultLedger (setCore and setExtension)
    console.log("\n📦 Step 5: Configuring ProtocolVaultLedger...");
    await configureProtocolVaultLedger(env, coreImpl, extension);

    // Step 6: Upgrade ProtocolVaultLedger proxy
    const pvLedgerProxy = deployment[env].pvLedger;
    if (!pvLedgerProxy) {
        throw new Error(`ProtocolVaultLedger proxy address not found for ${env}.`);
    }

    console.log("\n📦 Step 6: Upgrading ProtocolVaultLedger proxy...");
    console.log(`   Proxy: ${pvLedgerProxy}`);
    console.log(`   New Implementation: ${ledgerImpl}`);

    const protocolVaultLedger = await ethers.getContractAt(
        "ProtocolVaultLedger",
        pvLedgerProxy
    );

    console.log(`   ⏳ Executing upgradeToAndCall...`);
    const tx1 = await protocolVaultLedger.upgradeToAndCall(ledgerImpl, "0x");
    await tx1.wait();
    console.log(`   ✓ ProtocolVaultLedger upgraded successfully`);
    console.log(`   Transaction: ${tx1.hash}`);

    // Step 7: Upgrade VaultCrossChainManager proxy
    const crossChainManagerProxy = deployment[env].crossChainManager;
    if (crossChainManagerProxy) {
        console.log("\n📦 Step 7: Upgrading VaultCrossChainManager proxy...");
        console.log(`   Proxy: ${crossChainManagerProxy}`);
        console.log(`   New Implementation: ${crossChainManagerImpl}`);

        const vaultCrossChainManager = await ethers.getContractAt(
            "VaultCrossChainManager",
            crossChainManagerProxy
        );

        console.log(`   ⏳ Executing upgradeToAndCall...`);
        const tx2 = await vaultCrossChainManager.upgradeToAndCall(crossChainManagerImpl, "0x");
        await tx2.wait();
        console.log(`   ✓ VaultCrossChainManager upgraded successfully`);
        console.log(`   Transaction: ${tx2.hash}`);
    } else {
        console.log("\n⚠️  VaultCrossChainManager proxy address not found, skipping upgrade");
    }

    console.log("\n✅ Orderly chain upgrade completed!");
    console.log(`   - ProtocolVaultLedger impl: ${ledgerImpl}`);
    console.log(`   - VaultCrossChainManager impl: ${crossChainManagerImpl}`);
    console.log(`   - LedgerCoreImpl: ${coreImpl}`);
    console.log(`   - LedgerExtension: ${extension}`);
}

// Upgrade contracts on EVM chain
async function upgradeEVMContracts(env, network) {
    // Step 1: Deploy new ProtocolVault implementation
    console.log("📦 Step 1: Deploying new ProtocolVault implementation...");
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
    const protocolVaultImpl = await deployProtocolVaultImpl(ProtocolVault);

    // Step 2: Deploy new VaultCrossChainManager implementation
    console.log("\n📦 Step 2: Deploying new VaultCrossChainManager implementation...");
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const crossChainManagerImpl = await deployVaultCrossChainManagerImpl(VaultCrossChainManager);

    // Step 3: Upgrade ProtocolVault proxy
    const protocolVaultProxy = deployment[env].protocolVault;
    if (protocolVaultProxy) {
        console.log("\n📦 Step 3: Upgrading ProtocolVault proxy...");
        console.log(`   Proxy: ${protocolVaultProxy}`);
        console.log(`   New Implementation: ${protocolVaultImpl}`);

        const protocolVault = await ethers.getContractAt(
            "ProtocolVault",
            protocolVaultProxy
        );

        console.log(`   ⏳ Executing upgradeToAndCall...`);
        const tx1 = await protocolVault.upgradeToAndCall(protocolVaultImpl, "0x");
        await tx1.wait();
        console.log(`   ✓ ProtocolVault upgraded successfully`);
        console.log(`   Transaction: ${tx1.hash}`);
    } else {
        console.log("\n⚠️  ProtocolVault proxy address not found, skipping upgrade");
    }

    // Step 4: Upgrade VaultCrossChainManager proxy
    const crossChainManagerProxy = deployment[env].crossChainManager;
    if (crossChainManagerProxy) {
        console.log("\n📦 Step 4: Upgrading VaultCrossChainManager proxy...");
        console.log(`   Proxy: ${crossChainManagerProxy}`);
        console.log(`   New Implementation: ${crossChainManagerImpl}`);

        const vaultCrossChainManager = await ethers.getContractAt(
            "VaultCrossChainManager",
            crossChainManagerProxy
        );

        console.log(`   ⏳ Executing upgradeToAndCall...`);
        const tx2 = await vaultCrossChainManager.upgradeToAndCall(crossChainManagerImpl, "0x");
        await tx2.wait();
        console.log(`   ✓ VaultCrossChainManager upgraded successfully`);
        console.log(`   Transaction: ${tx2.hash}`);
    } else {
        console.log("\n⚠️  VaultCrossChainManager proxy address not found, skipping upgrade");
    }

    console.log("\n✅ EVM chain upgrade completed!");
    console.log(`   - ProtocolVault impl: ${protocolVaultImpl}`);
    console.log(`   - VaultCrossChainManager impl: ${crossChainManagerImpl}`);
}

// Helper: Print upgrade summary
function printUpgradeSummary(results, env) {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`📊 Upgrade Summary for ${env} environment`);
    console.log(`${'='.repeat(80)}\n`);

    if (results.success.length > 0) {
        console.log(`✅ Successfully upgraded on ${results.success.length} chain(s):`);
        results.success.forEach(({ network, contracts }) => {
            console.log(`   • ${network}: ${contracts.join(', ')}`);
        });
    }

    if (results.failed.length > 0) {
        console.log(`\n❌ Failed to upgrade on ${results.failed.length} chain(s):`);
        results.failed.forEach(({ network, error }) => {
            console.log(`   • ${network}: ${error}`);
        });
    }

    console.log(`\n${'='.repeat(80)}\n`);

    if (results.failed.length > 0) {
        console.log(`⚠️  Some upgrades failed. Please check the errors above and retry manually.`);
        console.log(`   Use: npx hardhat upgrade-impl --env ${env} --network <network_name>\n`);
    } else {
        console.log(`🎉 All upgrades completed successfully!\n`);
    }
}
