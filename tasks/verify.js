const { task } = require('hardhat/config');
const deployment = require('../deployment.json');

task("verify-adapter", "Verify VaultAdapter contracts on block explorer")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        
        // Get addresses from deployment.json
        const proxyAddr = deployment[taskArgs.env].vaultAdapter;
        
        if (!proxyAddr) {
            throw new Error(`Missing contract addresses for ${taskArgs.env} environment. Please deploy first.`);
        }

        // Get configuration values for constructor arguments
        const operator = deployment[taskArgs.env].dex_operator;
        const dexVault = deployment[taskArgs.env].dex[currentNetwork];
        const engine = deployment[taskArgs.env].adapter_engine;
        const usdc = require('../config.json')[currentNetwork].USDC;
        const owner = deployment[taskArgs.env].owner;

        if (!operator || !dexVault || !engine || !usdc || !owner) {
            throw new Error(`Missing required configuration for ${taskArgs.env} environment on ${currentNetwork}`);
        }

        // Read implementation address from proxy contract
        const implAddr = await getImplementationFromProxy(proxyAddr);
        console.log(`Implementation address read from proxy: ${implAddr}`);

        await verifyVaultAdapterContracts(implAddr, proxyAddr, operator, dexVault, engine, usdc, owner);
    });

task("verify-protocolvault", "Verify ProtocolVault contracts on block explorer")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        
        // Get addresses from deployment.json
        const proxyAddr = deployment[taskArgs.env].protocolVault;
        
        if (!proxyAddr) {
            throw new Error(`Missing contract addresses for ${taskArgs.env} environment. Please deploy first.`);
        }

        // Read implementation address from proxy contract
        const implAddr = await getImplementationFromProxy(proxyAddr);
        console.log(`Implementation address read from proxy: ${implAddr}`);

        // Get configuration values for constructor arguments
        const dexVault = deployment[taskArgs.env].dex[currentNetwork];
        const usdc = require('../config.json')[currentNetwork].USDC;
        const owner = deployment[taskArgs.env].owner;
        const minDepositForLp = deployment[taskArgs.env].minDepositForLp;
        const minDepositForSp = deployment[taskArgs.env].minDepositForSp;

        if (!dexVault || !usdc || !owner || !minDepositForLp || !minDepositForSp) {
            throw new Error(`Missing required configuration for ${taskArgs.env} environment on ${currentNetwork}`);
        }

        await verifyProtocolVaultContracts(implAddr, proxyAddr, dexVault, owner, usdc, minDepositForLp, minDepositForSp);
    });

/**
 * Verify VaultAdapter contracts on block explorer
 * @param {string} implAddr - Implementation contract address
 * @param {string} proxyAddr - Proxy contract address
 * @param {string} operator - Operator address
 * @param {string} dexVault - Dex vault address
 * @param {string} engine - Engine address
 * @param {string} usdc - USDC token address
 * @param {string} owner - Owner address
 */
async function verifyVaultAdapterContracts(implAddr, proxyAddr, operator, dexVault, engine, usdc, owner) {
    console.log("Starting VaultAdapter contract verification...");
    
    try {
        // Prepare constructor arguments for ERC1967Proxy
        const VaultAdapter = await ethers.getContractFactory("VaultAdapter");
        const initializeData = VaultAdapter.interface.encodeFunctionData(
            "initialize",
            [
                operator,
                dexVault,
                engine,
                usdc,
                owner
            ]
        );

        // Verify ERC1967Proxy contract
        console.log(`Verifying ERC1967Proxy contract: ${proxyAddr}`);
        await hre.run("verify:verify", {
            address: proxyAddr,
            contract: "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
            constructorArguments: [implAddr, initializeData]
        });
        console.log(`✅ ERC1967Proxy contract verified successfully: ${proxyAddr}`);
    } catch (error) {
        console.log(`⚠️ ERC1967Proxy contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ERC1967Proxy contract verification error:", error);
        }
    }

    console.log("VaultAdapter contract verification completed!");
}

/**
 * Verify ProtocolVault contracts on block explorer
 * @param {string} implAddr - Implementation contract address
 * @param {string} proxyAddr - Proxy contract address
 * @param {string} dexVault - Dex vault address
 * @param {string} owner - Owner address
 * @param {string} usdc - USDC token address
 * @param {number} minDepositForLp - Minimum deposit for LP
 * @param {number} minDepositForSp - Minimum deposit for SP
 */
async function verifyProtocolVaultContracts(implAddr, proxyAddr, dexVault, owner, usdc, minDepositForLp, minDepositForSp) {
    console.log("Starting ProtocolVault contract verification...");
    
    try {
        // Prepare constructor arguments for ERC1967Proxy
        const ProtocolVault = await ethers.getContractFactory("ProtocolVault");
        const initializeData = ProtocolVault.interface.encodeFunctionData(
            "initialize",
            [
                dexVault,
                owner,
                usdc,
                minDepositForLp,
                minDepositForSp
            ]
        );

        // Verify ERC1967Proxy contract
        console.log(`Verifying ERC1967Proxy contract: ${proxyAddr}`);
        await hre.run("verify:verify", {
            address: proxyAddr,
            contract: "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
            constructorArguments: [implAddr, initializeData]
        });
        console.log(`✅ ERC1967Proxy contract verified successfully: ${proxyAddr}`);
    } catch (error) {
        console.log(`⚠️ ERC1967Proxy contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ERC1967Proxy contract verification error:", error);
        }
    }

    console.log("ProtocolVault contract verification completed!");
}

/**
 * Read implementation address from ERC1967 proxy contract
 * @param {string} proxyAddr - Proxy contract address
 * @returns {string} Implementation contract address
 */
async function getImplementationFromProxy(proxyAddr) {
    // ERC1967 implementation storage slot
    // keccak256("eip1967.proxy.implementation") - 1
    const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    
    try {
        // Read storage slot from proxy contract
        // In ethers v6, use getStorage instead of getStorageAt
        const implementationBytes = await hre.ethers.provider.getStorage(proxyAddr, IMPLEMENTATION_SLOT);
        
        // Convert 32-byte storage value to address
        // Storage returns 32 bytes (64 hex chars + 0x), address is the last 20 bytes (40 hex chars)
        const hexWithoutPrefix = implementationBytes.slice(2); // Remove '0x' prefix
        const addressHex = hexWithoutPrefix.slice(-40); // Take last 40 hex chars (20 bytes)
        const implementationAddr = hre.ethers.getAddress("0x" + addressHex);
        
        if (implementationAddr === hre.ethers.ZeroAddress) {
            throw new Error(`No implementation found in proxy contract ${proxyAddr}`);
        }
        
        return implementationAddr;
    } catch (error) {
        throw new Error(`Failed to read implementation from proxy ${proxyAddr}: ${error.message}`);
    }
}

// Export functions for use in other files
module.exports = {
    verifyVaultAdapterContracts,
    verifyProtocolVaultContracts,
    getImplementationFromProxy
};
