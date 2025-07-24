const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('../config.json');
const { task } = require('hardhat/config');
const { checkNetworkEnvRestrictions } = require('./utils');

const ERC1967ProxyPath = path.join(__dirname, '../out/ERC1967Proxy.sol/ERC1967Proxy.json');
const ERC1967ProxyArtifact = JSON.parse(fs.readFileSync(ERC1967ProxyPath, 'utf8'));

task("deploy-evm", "Deploy strategy vault contracts on EVM")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployCrossChainManager(taskArgs.env);
        await deployProtocolVault(taskArgs.env);
    });

task("deploy-orderly", "Deploy orderly contract on Orderly")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await deployProtocolLedger(taskArgs.env);
        await deployCrossChainManager(taskArgs.env);

    });
task("deploy-protocolvault", "Deploy ProtocolVault contract")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployProtocolVault(taskArgs.env);
    });

task("deploy-pvledger", "Deploy ProtocolVaultLedger contract")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployProtocolLedger(taskArgs.env);
    });

task("deploy-ccmanager", "Deploy CrossChainManager contract")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployCrossChainManager(taskArgs.env);
    });

task("deploy-adapter", "Deploy VaultAdapter contract")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployVaultAdapter(taskArgs.env);
    });

async function deployProtocolLedger(env) {
    const [owner] = await ethers.getSigners();

    //deoloy PVLedger contract
    const PVLedger = await ethers.getContractFactory("ProtocolVaultLedger");
    const PVLedgerProxy = await upgrades.deployProxy(PVLedger, [owner.address], {
        initializer: 'initialize'
    });
    const proxyAddress = await PVLedgerProxy.target;

    console.log(`PVLedgerProxy deployed to ${proxyAddress}`);

    updateAddressConfig(env, 'pvLedger', proxyAddress);
}
async function deployCrossChainManager(env) {
    //deploy impl
    const VaultCrossChainManager = await ethers.getContractFactory("VaultCrossChainManager");
    const implAddr = await deployCrossChainManagerImpl(VaultCrossChainManager);
    //const implAddr = "0xF6094Fa8192e9B7D899B391F90Ab0Ae8bA479aC2";

    const [owner] = await ethers.getSigners();

    //Deploy contract by factory
    const bytecode = getCrossChainManagerBytecode(VaultCrossChainManager, implAddr, owner.address);
    const salt = deployment[env].cc_salt;

    const VaultFactory = await ethers.getContractAt(
        "VaultFactory",
        deployment.factory
    )
    const tx = await VaultFactory.deploy(salt, bytecode)
    await tx.wait()

    console.log("CrossChainManager deployed Done");
    const crossChainManagerAddr = await VaultFactory.getDeployed(salt);
    updateAddressConfig(env, 'crossChainManager', crossChainManagerAddr);

    // Verify proxy contract
    try {
        const currentNetwork = hre.network.name;
        const endpoint = config[currentNetwork].endpoint;

        await verifyCrossChainManagerProxy(VaultCrossChainManager, implAddr, crossChainManagerAddr, endpoint, owner.address);
    } catch (error) {
        console.log(`⚠️ CrossChainManager proxy verification failed: ${error.message}`);
    }

}
async function deployProtocolVault(env) {
    //deploy impl
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");

    const implAddr = await deployProtocolVaultImpl(ProtocolVault);
    //const implAddr = "0x83F367998EC5C78C107F32666B053D6A8991D773";

    const [owner] = await ethers.getSigners();

    //Deploy contract by factory
    const bytecode = getProlcolVaultBytecode(ProtocolVault, implAddr, owner.address, env);
    const salt = deployment[env].pv_salt;
    console.log("Deploying ProtocolVault with salt:", salt);

    const VaultFactory = await ethers.getContractAt(
        "VaultFactory",
        deployment.factory
    )
    const tx = await VaultFactory.deploy(salt, bytecode)
    await tx.wait()

    console.log("ProtocolVault deployed Done");
    const ProtocolVaultAddr = await VaultFactory.getDeployed(salt);

    updateAddressConfig(env, 'protocolVault', ProtocolVaultAddr);

    // Verify proxy contract
    try {
        const currentNetwork = hre.network.name;
        const dexVault = deployment[env].dex[currentNetwork];
        const usdc = config[currentNetwork].USDC;
        const minDepositForLp = deployment[env].minDepositForLp;
        const minDepositForSp = deployment[env].minDepositForSp;

        await verifyProtocolVaultProxy(ProtocolVault, implAddr, ProtocolVaultAddr, dexVault, owner.address, usdc, minDepositForLp, minDepositForSp);
    } catch (error) {
        console.log(`⚠️ ProtocolVault proxy verification failed: ${error.message}`);
    }
}

async function deployCrossChainManagerImpl(VaultCrossChainManager) {
    const VaultCrossChainManagerContract = await VaultCrossChainManager.deploy();
    const implAddr = VaultCrossChainManagerContract.target;
    await VaultCrossChainManagerContract.waitForDeployment();

    console.log("VaultCrossChainManager Impl deployed to:", implAddr);

    // Verify VaultCrossChainManager implementation contract
    try {
        console.log(`Verifying VaultCrossChainManager implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ VaultCrossChainManager implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ VaultCrossChainManager implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("VaultCrossChainManager implementation contract verification error:", error);
        }
    }

    return implAddr;
}
function getProlcolVaultBytecode(ProtocolVault, implAddr, ownerAddr, env) {
    //get usdc address 
    const currentNetwork = hre.network.name;
    const tokenAddress = config[currentNetwork].USDC
    if (!tokenAddress) {
        throw new Error(`No USDC address found for network: ${currentNetwork}`);
    }
    console.log(`USDC Address for ${currentNetwork}: ${tokenAddress}`);
    const minDepositForLp = deployment[env].minDepositForLp;
    const minDepositForSp = deployment[env].minDepositForSp;

    const initializeData = ProtocolVault.interface.encodeFunctionData(
        "initialize",
        [
            deployment[env].dex[currentNetwork],
            ownerAddr,
            tokenAddress,
            minDepositForLp,
            minDepositForSp
        ]
    );
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes"],
        [implAddr, initializeData]
    );

    //final bytecode
    const bytecode = ethers.concat([
        ERC1967ProxyArtifact.bytecode.object,
        constructorArgs
    ]);
    return bytecode;
}
function getCrossChainManagerBytecode(VaultCrossChainManager, implAddr, ownerAddr) {
    const currentNetwork = hre.network.name;
    const initializeData = VaultCrossChainManager.interface.encodeFunctionData(
        "initialize",
        [
            config[currentNetwork].endpoint,
            ownerAddr,//owner as delegate 
        ]
    );
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes"],
        [implAddr, initializeData]
    );

    //final bytecode
    const bytecode = ethers.concat([
        ERC1967ProxyArtifact.bytecode.object,
        constructorArgs
    ]);
    return bytecode;
}
function updateAddressConfig(env, contractName, address) {
    const configPath = path.join(process.cwd(), 'deployment.json');

    try {
        const configContent = fs.readFileSync(configPath, 'utf8');
        let config = JSON.parse(configContent);

        if (!config[env]) {
            config[env] = {};
        }

        if (config[env][contractName] && config[env][contractName] === address) {
            console.log(`✅ Address for ${contractName} in ${env} environment already exists and matches. Skipping update.`);
            return;
        } else if (config[env][contractName] && config[env][contractName] !== address) {
            console.log(`⚠️ Address for ${contractName} in ${env} environment already exists but does not match. New address: ${address} `);
            return;
        }

        config[env][contractName] = address;

        fs.writeFileSync(
            configPath,
            JSON.stringify(config, null, 2)
        );

        console.log(`✅ ${contractName}: ${address} written in ${env} environment`);
    } catch (error) {
        console.error(`Error updating address config: ${error.message}`);
        throw error;
    }
}

async function deployVaultAdapter(env) {
    const currentNetwork = hre.network.name;

    // Get configuration values
    const operator = deployment[env].dex_operator;
    const dexVault = deployment[env].dex[currentNetwork];
    const engine = deployment[env].adapter_engine;
    const usdc = config[currentNetwork].USDC;
    const owner = deployment[env].owner;

    if (!operator || !dexVault || !engine || !usdc || !owner) {
        throw new Error(`Missing required configuration for ${env} environment on ${currentNetwork}`);
    }
    //deploy impl
    const VaultAdapter = await ethers.getContractFactory("VaultAdapter");
    const implAddr = await deployVaultAdapterImpl(VaultAdapter);
    //const implAddr = "0xA692B03F4215377280C1043572cf87199CCA95E4";
    //Deploy contract by factory
    const bytecode = getVaultAdapterBytecode(VaultAdapter, implAddr, operator, dexVault, engine, usdc, owner);
    const salt = deployment[env].adapter_salt;

    const VaultFactory = await ethers.getContractAt(
        "VaultFactory",
        deployment[env].factory
    )
    const tx = await VaultFactory.deploy(salt, bytecode)
    await tx.wait()

    console.log("VaultAdapter deployed Done");
    const vaultAdapterAddr = await VaultFactory.getDeployed(salt);
    updateAddressConfig(env, 'vaultAdapter', vaultAdapterAddr);

    // Verify proxy contract
    try {
        await verifyVaultAdapterProxy(VaultAdapter, implAddr, vaultAdapterAddr, operator, dexVault, engine, usdc, owner);
    } catch (error) {
        console.log(`⚠️ VaultAdapter proxy verification failed: ${error.message}`);
    }
}

async function deployVaultAdapterImpl(VaultAdapter) {
    const VaultAdapterContract = await VaultAdapter.deploy();
    const implAddr = VaultAdapterContract.target;
    await VaultAdapterContract.waitForDeployment();

    console.log("VaultAdapter Impl deployed to:", implAddr);

    // Verify VaultAdapter implementation contract
    try {
        console.log(`Verifying VaultAdapter implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ VaultAdapter implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ VaultAdapter implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("VaultAdapter implementation contract verification error:", error);
        }
    }

    return implAddr;
}
async function deployProtocolVaultImpl(ProtocolVault) {
    const ProtocolVaultContract = await ProtocolVault.deploy();
    const implAddr = ProtocolVaultContract.target;
    await ProtocolVaultContract.waitForDeployment();

    console.log("ProtocolVaultContract Impl deployed to:", implAddr);

    // Verify ProtocolVault implementation contract
    try {
        console.log(`Verifying ProtocolVault implementation contract: ${implAddr}`);
        await hre.run("verify:verify", {
            address: implAddr,
            constructorArguments: []
        });
        console.log(`✅ ProtocolVault implementation contract verified successfully: ${implAddr}`);
    } catch (error) {
        console.log(`⚠️ ProtocolVault implementation contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ProtocolVault implementation contract verification error:", error);
        }
    }

    return implAddr;
}
function getVaultAdapterBytecode(VaultAdapter, implAddr, operator, dexVault, engine, usdc, owner) {
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
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes"],
        [implAddr, initializeData]
    );

    //final bytecode
    const bytecode = ethers.concat([
        ERC1967ProxyArtifact.bytecode.object,
        constructorArgs
    ]);
    return bytecode;
}

/**
 * Verify VaultAdapter proxy contract on block explorer
 * @param {*} VaultAdapter - VaultAdapter contract factory
 * @param {string} implAddr - Implementation contract address
 * @param {string} proxyAddr - Proxy contract address
 * @param {string} operator - Operator address
 * @param {string} dexVault - Dex vault address
 * @param {string} engine - Engine address
 * @param {string} usdc - USDC token address
 * @param {string} owner - Owner address
 */
async function verifyVaultAdapterProxy(VaultAdapter, implAddr, proxyAddr, operator, dexVault, engine, usdc, owner) {
    console.log("Starting VaultAdapter proxy contract verification...");
    
    try {
        // Prepare constructor arguments for ERC1967Proxy
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
        console.log(`✅ VaultAdapter ERC1967Proxy contract verified successfully: ${proxyAddr}`);
    } catch (error) {
        console.log(`⚠️ VaultAdapter ERC1967Proxy contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("VaultAdapter ERC1967Proxy contract verification error:", error);
        }
    }

    console.log("VaultAdapter proxy contract verification completed!");
}

/**
 * Verify ProtocolVault proxy contract on block explorer
 * @param {*} ProtocolVault - ProtocolVault contract factory
 * @param {string} implAddr - Implementation contract address
 * @param {string} proxyAddr - Proxy contract address
 * @param {string} dexVault - Dex vault address
 * @param {string} owner - Owner address
 * @param {string} usdc - USDC token address
 * @param {number} minDepositForLp - Minimum deposit for LP
 * @param {number} minDepositForSp - Minimum deposit for SP
 */
async function verifyProtocolVaultProxy(ProtocolVault, implAddr, proxyAddr, dexVault, owner, usdc, minDepositForLp, minDepositForSp) {
    console.log("Starting ProtocolVault proxy contract verification...");
    
    try {
        // Prepare constructor arguments for ERC1967Proxy
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
        console.log(`✅ ProtocolVault ERC1967Proxy contract verified successfully: ${proxyAddr}`);
    } catch (error) {
        console.log(`⚠️ ProtocolVault ERC1967Proxy contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("ProtocolVault ERC1967Proxy contract verification error:", error);
        }
    }

    console.log("ProtocolVault proxy contract verification completed!");
}

/**
 * Verify CrossChainManager proxy contract on block explorer
 * @param {*} VaultCrossChainManager - VaultCrossChainManager contract factory
 * @param {string} implAddr - Implementation contract address
 * @param {string} proxyAddr - Proxy contract address
 * @param {string} endpoint - LayerZero endpoint address
 * @param {string} owner - Owner address
 */
async function verifyCrossChainManagerProxy(VaultCrossChainManager, implAddr, proxyAddr, endpoint, owner) {
    console.log("Starting CrossChainManager proxy contract verification...");
    
    try {
        // Prepare constructor arguments for ERC1967Proxy
        const initializeData = VaultCrossChainManager.interface.encodeFunctionData(
            "initialize",
            [
                endpoint,
                owner, //owner as delegate 
            ]
        );

        // Verify ERC1967Proxy contract
        console.log(`Verifying ERC1967Proxy contract: ${proxyAddr}`);
        await hre.run("verify:verify", {
            address: proxyAddr,
            contract: "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
            constructorArguments: [implAddr, initializeData]
        });
        console.log(`✅ CrossChainManager ERC1967Proxy contract verified successfully: ${proxyAddr}`);
    } catch (error) {
        console.log(`⚠️ CrossChainManager ERC1967Proxy contract verification failed: ${error.message}`);
        // If already verified, no need to throw exception
        if (!error.message.includes("Already Verified") && !error.message.includes("already verified")) {
            console.error("CrossChainManager ERC1967Proxy contract verification error:", error);
        }
    }

    console.log("CrossChainManager proxy contract verification completed!");
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

