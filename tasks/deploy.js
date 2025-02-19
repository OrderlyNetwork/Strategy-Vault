const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('../config.json');
const { task } = require('hardhat/config');

const ERC1967ProxyPath = path.join(__dirname, '../scripts/utils/ERC1967Proxy.json');
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

}
async function deployProtocolVault(env) {
    //deploy impl
    const ProtocolVault = await ethers.getContractFactory("ProtocolVault");

    const implAddr = await deployProtocolVaultImpl(ProtocolVault);
    //const implAddr = "0x83F367998EC5C78C107F32666B053D6A8991D773";
    const [owner] = await ethers.getSigners();

    //Deploy contract by factory
    const bytecode = getProlcolVaultBytecode(ProtocolVault, implAddr, owner.address,env);
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
}

async function deployProtocolVaultImpl(ProtocolVault) {
    const ProtocolVaultContract = await ProtocolVault.deploy();
    const implAddr = ProtocolVaultContract.target;
    await ProtocolVaultContract.waitForDeployment();

    console.log("ProtocolVaultContract Impl deployed to:", implAddr);

    return implAddr;
}
async function deployCrossChainManagerImpl(VaultCrossChainManager) {
    const VaultCrossChainManagerContract = await VaultCrossChainManager.deploy();
    const implAddr = VaultCrossChainManagerContract.target;
    await VaultCrossChainManagerContract.waitForDeployment();

    console.log("VaultCrossChainManager Impl deployed to:", implAddr);

    return implAddr;
}
function getProlcolVaultBytecode(ProtocolVault, implAddr, ownerAddr,env) {
    //get usdc address 
    const currentNetwork = hre.network.name;
    const tokenAddress = config[currentNetwork].USDC
    if (!tokenAddress) {
        throw new Error(`No USDC address found for network: ${currentNetwork}`);
    }
    console.log(`USDC Address for ${currentNetwork}: ${tokenAddress}`);
    const minDepositForLp = 0;
    const minDepositForSp = 0;

    const initializeData = ProtocolVault.interface.encodeFunctionData(
        "initialize",
        [
            deployment[env].dex,
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
        ERC1967ProxyArtifact.bytecode,
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
        ERC1967ProxyArtifact.bytecode,
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

