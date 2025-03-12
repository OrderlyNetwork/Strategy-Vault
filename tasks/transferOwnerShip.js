const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const { task } = require('hardhat/config');
const { checkNetworkEnvRestrictions } = require('./utils');

task("transfer-evm-ownership", "Transfer ownership of EVM contracts to the configured owner")
    .addParam("env", "Deployment environment (staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev','staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        
        // Get owner address from deployment.json
        if (!deployment[taskArgs.env].owner) {
            throw new Error(`Owner address not configured for ${taskArgs.env} environment in deployment.json`);
        }
        
        const newOwnerAddress = deployment[taskArgs.env].owner;
        console.log(`Transferring ownership on ${currentNetwork} EVM network in ${taskArgs.env} environment`);
        console.log(`New owner address (from deployment.json): ${newOwnerAddress}`);

        // Only transfer EVM contracts
        const evmContracts = ["crossChainManager", "protocolVault"];
        
        // Filter out contracts that don't exist in this environment
        const validContracts = evmContracts.filter(contractName => 
            deployment[taskArgs.env][contractName] && deployment[taskArgs.env][contractName] !== ""
        );

        console.log(`Contracts to transfer: ${validContracts.join(", ")}`);

        // Get current signer
        const [signer] = await ethers.getSigners();
        console.log(`Current signer: ${signer.address}`);

        // Transfer ownership for each contract
        for (const contractName of validContracts) {
            await transferContractOwnership(contractName, deployment[taskArgs.env][contractName], newOwnerAddress, taskArgs.env);
        }
    });

task("transfer-orderly-ownership", "Transfer ownership of Orderly contracts to the configured owner")
    .addParam("env", "Deployment environment (staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev','staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        // Get owner address from deployment.json
        if (!deployment[taskArgs.env].owner) {
            throw new Error(`Owner address not configured for ${taskArgs.env} environment in deployment.json`);
        }
        
        const newOwnerAddress = deployment[taskArgs.env].owner;
        console.log(`Transferring ownership on ${currentNetwork} Orderly network in ${taskArgs.env} environment`);
        console.log(`New owner address (from deployment.json): ${newOwnerAddress}`);

        // Only transfer Orderly contracts
        const orderlyContracts = ["pvLedger", "crossChainManager"];
        
        // Filter out contracts that don't exist in this environment
        const validContracts = orderlyContracts.filter(contractName => 
            deployment[taskArgs.env][contractName] && deployment[taskArgs.env][contractName] !== ""
        );

        console.log(`Contracts to transfer: ${validContracts.join(", ")}`);

        // Get current signer
        const [signer] = await ethers.getSigners();
        console.log(`Current signer: ${signer.address}`);

        // Transfer ownership for each contract
        for (const contractName of validContracts) {
            await transferContractOwnership(contractName, deployment[taskArgs.env][contractName], newOwnerAddress, taskArgs.env);
        }
    });

async function transferContractOwnership(contractName, contractAddress, newOwnerAddress, env) {
    console.log(`\nTransferring ownership of ${contractName} at ${contractAddress} to ${newOwnerAddress}...`);
    
    try {
        let contract;
        switch (contractName) {
            case "pvLedger":
                contract = await ethers.getContractAt("ProtocolVaultLedger", contractAddress);
                break;
            case "crossChainManager":
                contract = await ethers.getContractAt("VaultCrossChainManager", contractAddress);
                break;
            case "protocolVault":
                contract = await ethers.getContractAt("ProtocolVault", contractAddress);
                break;
            default:
                throw new Error(`Unknown contract type: ${contractName}`);
        }

        // Check current owner
        const currentOwner = await contract.owner();
        console.log(`Current owner: ${currentOwner}`);

        // Check if current owner is already the new owner
        // if (currentOwner.toLowerCase() === newOwnerAddress.toLowerCase()) {
        //     console.log(`Contract ${contractName} is already owned by ${newOwnerAddress}. No action needed.`);
        //     return;
        // }

        // Check if we have permission to transfer
        const [signer] = await ethers.getSigners();
        if (signer.address.toLowerCase() !== currentOwner.toLowerCase()) {
            console.warn(`WARNING: Signer address (${signer.address}) is not the current owner (${currentOwner}). This transaction will likely fail.`);
        }

        // Transfer ownership (2-step process)
        console.log(`Initiating ownership transfer to ${newOwnerAddress}...`);
        const tx1 = await contract.transferOwnership(newOwnerAddress);
        await tx1.wait();
        console.log(`Ownership transfer initiated. Transaction hash: ${tx1.hash}`);
        
        // Update the ownership status in deployment file
        updateOwnershipStatus(env, contractName, {
            pendingOwner: newOwnerAddress,
            status: "pending",
            txHash: tx1.hash
        });
        
        console.log(`✅ Ownership of ${contractName} transfer initiated. New owner ${newOwnerAddress} needs to accept the transfer.`);
    } catch (error) {
        console.error(`Error transferring ownership of ${contractName}: ${error.message}`);
        if (error.data) {
            console.error(`Error data: ${error.data}`);
        }
        throw error;
    }
}

function updateOwnershipStatus(env, contractName, ownershipInfo) {
    const configPath = path.join(process.cwd(), 'deployment.json');

    try {
        const configContent = fs.readFileSync(configPath, 'utf8');
        let config = JSON.parse(configContent);

        if (!config[env]) {
            config[env] = {};
        }
        
        if (!config[env].ownership) {
            config[env].ownership = {};
        }
        
        if (!config[env].ownership[contractName]) {
            config[env].ownership[contractName] = {};
        }
        
        config[env].ownership[contractName] = {
            ...config[env].ownership[contractName],
            ...ownershipInfo,
            updatedAt: new Date().toISOString()
        };

        fs.writeFileSync(
            configPath,
            JSON.stringify(config, null, 2)
        );

        console.log(`✅ Ownership status for ${contractName} updated in ${env} environment`);
    } catch (error) {
        console.error(`Error updating ownership status: ${error.message}`);
        throw error;
    }
}

// Task for new owner to accept ownership
task("accept-ownership", "Accept ownership of contracts as the new owner")
    .addParam("env", "Deployment environment (staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        const [newOwner] = await ethers.getSigners();
        
        console.log(`Accepting ownership as ${newOwner.address} on ${currentNetwork} network in ${taskArgs.env} environment`);

        // Check if there are pending ownership transfers
        if (!deployment[taskArgs.env].ownership) {
            console.log(`No ownership transfers found in ${taskArgs.env} environment`);
            return;
        }
        
        const contractsToAccept = [];
        for (const contractName in deployment[taskArgs.env].ownership) {
            const ownershipInfo = deployment[taskArgs.env].ownership[contractName];
            if (ownershipInfo.status === "pending" && 
                ownershipInfo.pendingOwner.toLowerCase() === newOwner.address.toLowerCase()) {
                contractsToAccept.push(contractName);
            }
        }
        
        if (contractsToAccept.length === 0) {
            console.log(`No pending ownership transfers for ${newOwner.address} found in ${taskArgs.env} environment`);
            return;
        }
        
        console.log(`Contracts to accept ownership: ${contractsToAccept.join(", ")}`);
        
        for (const contractName of contractsToAccept) {
            const contractAddress = deployment[taskArgs.env][contractName];
            if (!contractAddress) {
                console.warn(`⚠️ Contract ${contractName} not found in ${taskArgs.env} environment. Skipping.`);
                continue;
            }
            
            await acceptContractOwnership(contractName, contractAddress, taskArgs.env);
        }
    });

async function acceptContractOwnership(contractName, contractAddress, env) {
    console.log(`\nAccepting ownership of ${contractName} at ${contractAddress}...`);
    
    try {
        let contract;
        switch (contractName) {
            case "pvLedger":
                contract = await ethers.getContractAt("ProtocolVaultLedger", contractAddress);
                break;
            case "crossChainManager":
                contract = await ethers.getContractAt("VaultCrossChainManager", contractAddress);
                break;
            case "protocolVault":
                contract = await ethers.getContractAt("ProtocolVault", contractAddress);
                break;
            default:
                throw new Error(`Unknown contract type: ${contractName}`);
        }

        // Accept ownership
        const tx = await contract.acceptOwnership();
        await tx.wait();
        console.log(`Ownership accepted. Transaction hash: ${tx.hash}`);
        
        // Update the ownership status in deployment file
        updateOwnershipStatus(env, contractName, {
            pendingOwner: null,
            status: "completed",
            txHash: tx.hash
        });
        
        console.log(`✅ Ownership of ${contractName} successfully accepted.`);
    } catch (error) {
        console.error(`Error accepting ownership of ${contractName}: ${error.message}`);
        if (error.data) {
            console.error(`Error data: ${error.data}`);
        }
        throw error;
    }
}

module.exports = {};