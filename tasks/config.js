const fs = require('fs');
const path = require('path');
const deployment = require('../deployment/deployment.json');
const cvDeployment = require('../deployment/community.json');
const config = require('../config.json');
const { getAccountId, getStrategyProviderId, getVaultId } = require('../scripts/utils/getId');
const { checkNetworkEnvRestrictions, getEndpointV2 } = require('./utils');
const { task } = require('hardhat/config');
const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"

task("config-evm", "Config strategy vault contracts on EVM")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await configProtocolVault(taskArgs.env);
        console.log("✅ ----------------------Protocol Vault Config Done----------------------")

        await configEVMCrossChainManager(taskArgs.env);
        console.log("✅ ----------------------EVM CrossChainManager Config Done----------------------")

        await lz_evm_config(taskArgs.env);
        console.log("✅ ----------------------Lz EVM Config Done----------------------")
    });

task("config-orderly", "Deploy strategy vault contracts on Orderly")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("chain", "Dst evm chain")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await configProtocolVaultLedger(taskArgs.env);
        console.log("✅ ----------------------Protocol Vault Ledger Config Done----------------------")

        await configOrderlyCrossChainManager(taskArgs.env, taskArgs.chain);
        console.log("✅ ----------------------Orderly CrossChainManager Config Done----------------------")

        await lz_orderly_config(taskArgs.env, taskArgs.chain);
        console.log("✅ ----------------------Lz Orderly Config Done----------------------")
    });
task("config-evm-cc", "Config EVM CrossChainManager")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await configEVMCrossChainManager(taskArgs.env);
    });

task("config-protocol-vault", "Config ProtocolVault")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await configProtocolVault(taskArgs.env);
    });
task("config-protocol-vault-ledger", "Config ProtocolVaultLedger")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await configProtocolVaultLedger(taskArgs.env);
    });
task("config-orderly-cc", "Config Orderly CrossChainManager")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("chain", "Dst evm chain")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await configOrderlyCrossChainManager(taskArgs.env, taskArgs.chain);
        console.log("✅ ----------------------Orderly CrossChainManager Config Done----------------------")
    });
task("config-new-evm", "Config new chain for Orderly CrossChainManager")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("chain", "Dst evm chain")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await configNewChainForOrderly(taskArgs.env, taskArgs.chain);
        console.log("✅ ----------------------Config New Chain CC Manager Done----------------------")

        await lz_orderly_config(taskArgs.env, taskArgs.chain);
        console.log("✅ ----------------------Lz Orderly Config Done----------------------")
    });
task("lz-evm-config", "Config Lz on evm")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await lz_evm_config(taskArgs.env);
    });
task("lz-orderly-config", "Config Lz on orderly")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("chain", "Dst evm chain")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await lz_orderly_config(taskArgs.env, taskArgs.chain);
    });

task("config-adapter", "Config VaultAdapter allowed brokers")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await configVaultAdapter(taskArgs.env);
    });
task("config-cv", "Config ProtocolVault")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("cv", "Community Vault name)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        //check if cvname exists in cvDeployment
        if (!cvDeployment[taskArgs.cv]) {
            throw new Error(`CommunityVault deployment not found for environment: ${taskArgs.env}`);
        }
        await configCommunityVault(taskArgs.env, taskArgs.cv);
        await configEVMCCForCommunityVault(taskArgs.env, taskArgs.cv);
    });
task("ledger-add-cv", "Add CommunityVault to ledger")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .addParam("cv", "Community Vault name)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await addCommunityVaultToLedger(taskArgs.env, taskArgs.cv);
    });
async function configCommunityVault(env, cv) {
    //get the contract instance
    const pvContract = await ethers.getContractAt(
        "ProtocolVault",
        cvDeployment[cv].address
    )

    //set crossChainManager
    tx = await pvContract.setCrossChainManager(deployment[env].crossChainManager);
    await tx.wait()
    console.log("CrossChainManager set successfully")

    //set sp 
    const spId = getStrategyProviderId(cvDeployment[cv].address, cvDeployment[cv].sp, cvDeployment[cv].broker);
    tx = await pvContract.setAllowedStrategyProvider(spId, true);
    await tx.wait()
    console.log("Allowed SP set successfully")

    //set ledger eid
    let ledgerEid;
    const currentNetwork = hre.network.name;

    if (env == 'dev' || env == 'qa' || env == 'staging') {
        ledgerEid = config['orderly_sepolia'].eid;
    } else if (env == 'mainnet') {
        ledgerEid = config['orderly'].eid;
    }
    tx = await pvContract.setLedgerEid(ledgerEid);
    await tx.wait()
    console.log(`set ledger eid ${ledgerEid} successfully for ${currentNetwork}`)

    //set broker 
    tx = await pvContract.setAllowedBroker(cvDeployment[cv].broker, true);
    await tx.wait();
    console.log("Allowed broker set successfully");

    //transfer native for cc fee 
    if (env != 'mainet') {
        const [sender] = await ethers.getSigners();
        tx = await sender.sendTransaction({
            to: cvDeployment[cv].address,
            value: ethers.parseEther('0.1'),
        });
        await tx.wait()
        console.log("transfer native to community vault successfully");
    }
}
async function configEVMCCForCommunityVault(env, cv) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    tx = await ccManagerContract.setValidVault(deployment[env].protocolVault, true);
    await tx.wait()
    console.log("Set valid vault for ProtocolVault successfully")

    tx = await ccManagerContract.setValidVault(cvDeployment[cv].address, true);
    await tx.wait()
    console.log("Set valid vault for ProtocolVault and CommunityVault successfully")
}
async function addCommunityVaultToLedger(env, cv) {
    //get the contract instance
    const pvLedgerContract = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )
    //set cv
    tx = await pvLedgerContract.setVault(cvDeployment[cv].vaultId, cvDeployment[cv].address);
    await tx.wait()
    console.log(`Set CommunityVault ${cv} to ledger successfully`)

    //set pv
    vaultId = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "bytes32"],
            [deployment[env].protocolVault, cvDeployment[cv].broker]
        )
    );
    tx = await pvLedgerContract.setVault(vaultId, deployment[env].protocolVault);
    await tx.wait()
    console.log(`Set ProtocolVault ${cv} to ledger successfully`)

    //set fee
    const spId = getStrategyProviderId(cvDeployment[cv].address, cvDeployment[cv].sp, cvDeployment[cv].broker);
    tx = await pvLedgerContract.setFeeRate([spId], [cvDeployment[cv].feeRate]); //0.1%
    await tx.wait()
    console.log(`Set CommunityVault fee to ledger successfully`)

    //set broker
    tx = await pvLedgerContract.setVaultBroker(cvDeployment[cv].vaultId, cvDeployment[cv].broker);
    await tx.wait()
    console.log(`Set CommunityVault ${cv} broker to ledger successfully`)
}
async function configProtocolVaultLedger(env) {
    //get the contract instance
    const pvLedgerContract = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    //set operator
    tx = await pvLedgerContract.setOperatorManager(deployment[env].operator);
    await tx.wait()
    console.log("Operator set successfully")

    //set engine
    tx = await pvLedgerContract.setEngine(deployment[env].engine);
    await tx.wait()
    console.log("Engine set successfully")

    //set crossChainManager
    tx = await pvLedgerContract.setCrossChainManager(deployment[env].crossChainManager);
    await tx.wait()
    console.log("CrossChainManager set successfully")

    //set allowed sp 
    // const vaultId = getVaultId(deployment[env].protocolVault, broker);
    // const sp = deployment[env].allowedSP;
    // const spId = getStrategyProviderId(deployment[env].protocolVault, sp, broker);

    // tx = await pvLedgerContract.setAllowedStrategyProvider(
    //     vaultId,
    //     deployment[env].protocolVault,
    //     sp,
    //     broker,
    //     spId,
    //     true
    // )
    // await tx.wait();
    // console.log("Allowed SP set to:", spId)
}
async function configOrderlyCrossChainManager(env, network) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set eid
    const evmChainId = config[network].chainId;
    const evmEid = config[network].eid;
    tx = await ccManagerContract.setEid(evmChainId, evmEid);
    await tx.wait()
    console.log(`set evmChainId ${evmChainId} to evmEid ${evmEid} successfully for ${network}`)

    //set peer 
    tx = await ccManagerContract.setPeer(evmEid, ethers.zeroPadValue(deployment[env].crossChainManager, 32));
    await tx.wait()
    console.log(`Peer set evmEid ${evmEid} successfully for ${network}`)

    //set option
    tx = await ccManagerContract.setOptions(4, 500000, 0);
    await tx.wait()
    console.log("Option set ASSETS_DISTRIBUTION successfully")

    tx = await ccManagerContract.setOptions(5, 600000, 0);
    await tx.wait()
    console.log("Option set UPDATE_USER_CLAIM successfully")

    //set ledger 
    tx = await ccManagerContract.setLedger(deployment[env].pvLedger);
    await tx.wait()
    console.log("Ledger set successfully")

    //transfer native for cc fee 
    const [sender] = await ethers.getSigners();
    tx = await sender.sendTransaction({
        to: deployment[env].crossChainManager,
        value: ethers.parseEther('1.2'),
    });
    await tx.wait()
    console.log("transfer native to cross chain manager fee successfully");

}

async function configNewChainForOrderly(env, network) {
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )
    console.log(config[network].chainId, config[network].eid)
    console.log(config[network].eid, ethers.zeroPadValue(deployment[env].crossChainManager, 32))
    //set eid
    tx = await ccManagerContract.setEid(config[network].chainId, config[network].eid);
    await tx.wait()
    console.log(`set chainId ${config[network].chainId} to eid ${config[network].eid} successfully for ${network}`)

    //set peer 
    tx = await ccManagerContract.setPeer(config[network].eid, ethers.zeroPadValue(deployment[env].crossChainManager, 32));
    await tx.wait()
    console.log(`Peer set eid ${config[network].eid} successfully for ${network}`)
}
async function configProtocolVault(env) {
    //get the contract instance
    const pvContract = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )

    //set crossChainManager
    tx = await pvContract.setCrossChainManager(deployment[env].crossChainManager);
    await tx.wait()
    console.log("CrossChainManager set successfully")

    //set sp 
    const spId = getStrategyProviderId(deployment[env].protocolVault, deployment[env].allowedSP, broker);
    tx = await pvContract.setAllowedStrategyProvider(spId, true);
    await tx.wait()
    console.log("Allowed SP set successfully")

    //set ledger eid
    let ledgerEid;
    const currentNetwork = hre.network.name;

    if (env == 'dev' || env == 'qa' || env == 'staging') {
        ledgerEid = config['orderly_sepolia'].eid;
    } else if (env == 'mainnet') {
        ledgerEid = config['orderly'].eid;
    }
    tx = await pvContract.setLedgerEid(ledgerEid);
    await tx.wait()
    console.log(`set ledger eid ${ledgerEid} successfully for ${currentNetwork}`)

    //transfer native for cc fee 
    const [sender] = await ethers.getSigners();
    tx = await sender.sendTransaction({
        to: deployment[env].protocolVault,
        value: ethers.parseEther('0.5'),
    });
    await tx.wait()
    console.log("transfer native to protocol vaultsuccessfully");

}

async function configVaultAdapter(env) {
    console.log(`Configuring VaultAdapter for ${env} environment...`);
    const currentNetwork = hre.network.name;

    // Get the contract instance
    const vaultAdapterContract = await ethers.getContractAt(
        "VaultAdapter",
        deployment[env].vaultAdapter
    );

    // Get allowed brokers from deployment config
    const allowedBrokers = deployment.allowedBrokersForAdapter;

    if (!allowedBrokers || allowedBrokers.length === 0) {
        console.log("No allowed brokers found in deployment config");
        return;
    }

    let configuredCount = 0;
    let skippedCount = 0;

    //set allowed brokers
    for (const brokerHash of allowedBrokers) {
        console.log(`Checking broker: ${brokerHash}`);

        try {
            // Check if broker is already allowed
            const isAllowed = await vaultAdapterContract.isAllowedBroker(brokerHash);

            if (isAllowed) {
                console.log(`✓ Broker ${brokerHash} is already configured`);
                skippedCount++;
            } else {
                console.log(`→ Configuring broker ${brokerHash}...`);
                // Set broker as allowed
                const tx = await vaultAdapterContract.setAllowedBroker(brokerHash, true);
                await tx.wait();
                console.log(`✓ Broker ${brokerHash} configured successfully`);
                configuredCount++;
            }
        } catch (error) {
            console.error(`✗ Failed to configure broker ${brokerHash}:`, error.message);
        }
    }

    //set usdt token hash
    const usdtHash = "0x8b1a1d9c2b109e527c9134b25b1a1833b16b6594f92daa9f6d9b7a6024bce9d0"; // USDT hash
    const usdtToken = config[currentNetwork].USDT;
    const mappedUsdtToken = await vaultAdapterContract.tokenHashToToken(usdtHash);

    if (usdtToken != mappedUsdtToken) {
        tx = await vaultAdapterContract.setAllowedTokenHashToToken(usdtHash, usdtToken);
        await tx.wait();
        console.log(`USDT token hash ${usdtHash} set to ${usdtToken} successfully`);
    } else {
        console.log(`USDT token hash ${usdtHash} is already set to ${usdtToken}`);
    }

    //set protocol vault
    const protocolVault = deployment[env].protocolVault;
    tx = await vaultAdapterContract.setProtocolVault(protocolVault);
    await tx.wait();
    console.log(`Protocol Vault set to ${protocolVault} successfully`);

    //send cc fee 
    const [sender] = await ethers.getSigners();
    tx = await sender.sendTransaction({
        to: deployment[env].vaultAdapter,
        value: ethers.parseEther('0.1'),
    });
    await tx.wait()
    console.log("transfer native to vault adapter successfully");
}

async function configEVMCrossChainManager(env) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    const currentNetwork = hre.network.name;

    //set eid
    if (env == 'mainnet') {
        tx = await ccManagerContract.setEid(config['orderly'].chainId, config['orderly'].eid);
        await tx.wait()
        console.log(`set chainId ${config['orderly'].chainId} to eid ${config['orderly'].eid} successfully for ${currentNetwork}`)
    } else if (env == 'dev' || env == 'qa' || env == 'staging') {
        //chainId is hardcode in contract, so here is 'orderly'.chainId instead of 'orderly_sepolia'.chainId
        tx = await ccManagerContract.setEid(config['orderly'].chainId, config['orderly_sepolia'].eid);
        await tx.wait()
        console.log(`set chainId ${config['orderly'].chainId} to eid ${config['orderly_sepolia'].eid} successfully for ${currentNetwork}`)
    } else {
        throw new Error(`Invalid chain`);
    }

    //set peer 
    let ledgerEid;
    if (env == 'dev' || env == 'qa' || env == 'staging') {
        ledgerEid = config['orderly_sepolia'].eid;
    } else if (env == 'mainnet') {
        ledgerEid = config['orderly'].eid;
    }
    tx = await ccManagerContract.setPeer(ledgerEid, ethers.zeroPadValue(deployment[env].crossChainManager, 32));
    await tx.wait()
    console.log(`set peer eid:${ledgerEid}`)

    //set option
    tx = await ccManagerContract.setOptions(0, 120000, 0);
    await tx.wait()
    console.log("Option set LP_DEPOSIT successfully")

    tx = await ccManagerContract.setOptions(1, 150000, 0);
    await tx.wait()
    console.log("Option set LP_WITHDRAW successfully")

    tx = await ccManagerContract.setOptions(2, 150000, 0);
    await tx.wait()
    console.log("Option set SP_DEPOSIT successfully")

    tx = await ccManagerContract.setOptions(3, 150000, 0);
    await tx.wait()
    console.log("Option set SP_WITHDRAW successfully")

    //set vault 
    tx = await ccManagerContract.setVault(deployment[env].protocolVault);
    await tx.wait()
    console.log("Vault set successfully")

}

async function lz_evm_config(env) {
    const networkConfig = config[hre.network.name];
    const oappAddress = deployment[env].crossChainManager;
    let remoteEid;

    if (env == 'dev' || env == 'qa' || env == 'staging') {
        remoteEid = config['orderly_sepolia'].eid;
    } else if (env == 'mainnet') {
        remoteEid = config['orderly'].eid;
    }
    await setLzConfig(env, oappAddress, remoteEid, networkConfig);
}

async function lz_orderly_config(env, dstChain) {
    const remoteEid = config[dstChain].eid;
    const networkConfig = config[hre.network.name];
    const oappAddress = deployment[env].crossChainManager;

    await setLzConfig(env, oappAddress, remoteEid, networkConfig);
}

async function setLzConfig(env, oappAddress, remoteEid, networkConfig) {
    const endpointv2 = await getEndpointV2(hre.network.name);
    const network = hre.network.name;
    //Setting Send and Receive Libraries  
    tx = await endpointv2.setSendLibrary(
        oappAddress,
        remoteEid,
        networkConfig.sendLibConfig.sendLibAddress
    );
    await tx.wait();
    console.log(`setSendLibrary on ${network} ${env} sucessfully`);


    tx = await endpointv2.setReceiveLibrary(
        oappAddress,
        remoteEid,
        networkConfig.receiveLibConfig.receiveLibAddress,
        0
    );
    await tx.wait();
    console.log(`setReceiveLibrary on ${network} ${env} sucessfully`);

    // Setting Send Config  
    const sendUlnConfig = networkConfig.sendLibConfig.ulnConfig;
    const encodedUlnConfig = ethers.AbiCoder.defaultAbiCoder().encode(
        ['tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)'],
        [sendUlnConfig]
    );

    const sendExecutorConfig = {
        maxMessageSize: networkConfig.sendLibConfig.executorConfig.maxMessageSize,
        executorAddress: networkConfig.sendLibConfig.executorConfig.executorAddress
    };
    const encodedExecutorConfig = ethers.AbiCoder.defaultAbiCoder().encode(
        ['tuple(uint32 maxMessageSize, address executorAddress)'],
        [sendExecutorConfig]
    );

    const sendConfigTx = await endpointv2.setConfig(
        oappAddress,
        networkConfig.sendLibConfig.sendLibAddress,
        [
            {
                eid: remoteEid,
                configType: 2, // ULN Config  
                config: encodedUlnConfig
            },
            {
                eid: remoteEid,
                configType: 1, // Executor Config  
                config: encodedExecutorConfig
            }
        ]
    );
    await sendConfigTx.wait();
    console.log(`setSendConfig on ${network} ${env} sucessfully`);

    // Setting Receive Config  
    const receiveUlnConfig = networkConfig.receiveLibConfig.ulnConfig;
    const encodedReceiveUlnConfig = ethers.AbiCoder.defaultAbiCoder().encode(
        ['tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)'],
        [receiveUlnConfig]
    );
    const receiveConfigTx = await endpointv2.setConfig(
        oappAddress,
        networkConfig.receiveLibConfig.receiveLibAddress,
        [
            {
                eid: remoteEid,
                configType: 2, // ULN Config  
                config: encodedReceiveUlnConfig
            }
        ]
    );
    await receiveConfigTx.wait();
    console.log(`setReceiveConfig on ${network} ${env} sucessfully`);
}
