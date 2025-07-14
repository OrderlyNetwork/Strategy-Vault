const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('../config.json');
const { keccak256, AbiCoder } = require("ethers");
const { getAccountId, getStrategyProviderId, getVaultId } = require('../scripts/utils/getId');
const { checkNetworkEnvRestrictions } = require('./utils')
const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
const { assert } = require("chai");

task("check-evm", "Check strategy vault contracts on EVM")
    .addParam("env", "environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await checkProtocolVault(taskArgs.env);
        console.log("✅ ----------------------Protocol Vault Config Done----------------------")

        await checkEVMCrossChainManager(taskArgs.env);
        console.log("✅ ----------------------EVM CrossChainManager Config Done----------------------")
    });


task("check-orderly", "Check strategy vault contracts on Orderly")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        const currentNetwork = hre.network.name;
        checkNetworkEnvRestrictions(currentNetwork, taskArgs.env);

        await checkOrderlyCrossChainManager(taskArgs.env);
        console.log("✅ ----------------------Check Orderly CrossChainManager Config Done----------------------")

        await checkLedger(taskArgs.env);
        console.log("✅ ----------------------Check Ledger Config Done----------------------")
    });

task("check-adapter", "Check VaultAdapter contract configuration")
    .addParam("env", "environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }

        const currentNetwork = hre.network.name;
        const env = taskArgs.env;

        if (!deployment[env].vaultAdapter) {
            throw new Error(`VaultAdapter address not found in deployment.json for ${env} environment`);
        }

        console.log(`Checking VaultAdapter on network: ${currentNetwork}`);
        console.log(`VaultAdapter address: ${deployment[env].vaultAdapter}`);

        try {
            await checkVaultAdapter(env);
            console.log("✅ ----------------------VaultAdapter Config Done----------------------")
        } catch (error) {
            console.error("❌ Error checking VaultAdapter configuration:");
            console.error(`Network: ${currentNetwork}`);
            console.error(`Environment: ${env}`);
            console.error(`Contract Address: ${deployment[env].vaultAdapter}`);
            console.error(`Error: ${error.message}`);
            throw error;
        }
    });

async function checkProtocolVault(env) {
    //get the contract instance
    const pvContract = await ethers.getContractAt(
        "ProtocolVault",
        deployment[env].protocolVault
    )
    //check dex
    const currentNetwork = hre.network.name;
    const netwroks = deployment[env].deployedNetwork;

    if (!netwroks.includes(currentNetwork)) {
        throw new Error(` ${env} on ${currentNetwork} not deployed`);
    }

    //check dexVault
    const dexVault = await pvContract.dexVault();
    assert.equal(dexVault.toLowerCase(), deployment[env].dex[currentNetwork].toLowerCase(), ` ${env} dex on ${currentNetwork} config error`);

    //check isAllowedStrategy
    assert.equal(await pvContract.isAllowedStrategy(deployment[env].dex[currentNetwork]), true, ` ${env} strategy config error`);
    //check crossChainManager
    const crossChainManager = await pvContract.crossChainManager();
    assert.equal(crossChainManager.toLowerCase(), deployment[env].crossChainManager.toLowerCase(), ` ${env} crossChainManager config error`);

    //check ledgerEid
    const ledgerEid = await pvContract.ledgerEid();
    if (env == 'dev' || env == 'qa' || env == 'staging') {
        assert.equal(ledgerEid.toString(), '40200', ` ${env} ledgerEid config error`);
    } else {
        assert.equal(ledgerEid.toString(), '30213', ` ${env} ledgerEid config error`);
    }

    //check allowed sp
    const spId = getStrategyProviderId(deployment[env].protocolVault, deployment[env].allowedSP, broker);
    assert.equal(await pvContract.isAllowedStrategyProvider(spId), true, ` ${env} isAllowedStrategyProvider config error`);

    //check allowed token
    assert.equal(await pvContract.isAllowedToken(config[currentNetwork].USDC), true, ` ${env} token config error`);

    //check isAllowedBroker
    assert.equal(await pvContract.isAllowedBroker(broker), true, ` ${env} broker config error`);

    //check minDepositForLP
    assert.equal((await pvContract.minDepositForLp()).toString(), deployment[env].minDepositForLp, ` ${env} minDepositForLP config error`);

    //check minDepositForSP
    assert.equal((await pvContract.minDepositForSp()).toString(), deployment[env].minDepositForSp, ` ${env} minDepositForSP config error`);
}

async function checkEVMCrossChainManager(env) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //check ledger 
    const vault = await ccManagerContract.vault();
    assert.equal(vault, deployment[env].protocolVault, ` ${env} cc manager pv vault config error`);

    //check chain id to eid
    if (env == 'dev' || env == 'qa' || env == 'staging') {
        //test net 
        const eid = await ccManagerContract.chainIdToEid(config['orderly'].chainId);
        assert.equal(eid.toString(), config['orderly_sepolia'].eid.toString(), ` ${env} chainIdToEid config error`);
    } else if (env == 'mainnet') {
        const eid = await ccManagerContract.chainIdToEid(config['orderly'].chainId);
        assert.equal(eid.toString(), config['orderly'].eid.toString(), ` ${env} chainIdToEid config error`);
    }
}

async function checkOrderlyCrossChainManager(env) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //check ledger 
    const ledger = await ccManagerContract.ledger();
    assert.equal(ledger, deployment[env].pvLedger, ` ${env} cc manager pv Ledger config error`);

    const netwroks = deployment[env].deployedNetwork;
    for (const network of netwroks) {
        const chainId = config[network].chainId;
        const eid = await ccManagerContract.chainIdToEid(chainId);
        assert.equal(eid.toString(), config[network].eid.toString(), ` ${env} chainIdToEid config error`);
    }
}
async function checkLedger(env) {
    //get the contract instance
    const pvLedgerContract = await ethers.getContractAt(
        "ProtocolVaultLedger",
        deployment[env].pvLedger
    )

    //check crossChainManager
    const crossChainManager = await pvLedgerContract.crossChainManager();
    assert.equal(crossChainManager.toLowerCase(), deployment[env].crossChainManager.toLowerCase(), ` ${env} crossChainManager config error`);

    //check operator
    const operator = await pvLedgerContract.operator();
    assert.equal(operator.toLowerCase(), deployment[env].operator.toLowerCase(), ` ${env} operator config error`);

    //check engine
    const engine = await pvLedgerContract.engine();
    assert.equal(engine.toLowerCase(), deployment[env].adapter_engineengine.toLowerCase(), ` ${env} engine config error`);
}

async function checkVaultAdapter(env) {
    const currentNetwork = hre.network.name;

    //get the contract instance
    const adapterContract = await ethers.getContractAt(
        "VaultAdapter",
        deployment[env].vaultAdapter
    )

    // 检查合约代码是否存在
    const code = await ethers.provider.getCode(deployment[env].vaultAdapter);
    if (code === "0x") {
        throw new Error(`No contract code found at address ${deployment[env].vaultAdapter}`);
    }
    console.log("Contract code verified ✓");

    try {
        //check dex operator
        const operator = await adapterContract.operator();
        assert.equal(operator.toLowerCase(), deployment[env].dex_operator.toLowerCase(), `${env} operator config error`);
        console.log("Operator verified ✓");

        //check dexVault
        const dexVault = await adapterContract.dexVault();
        assert.equal(dexVault.toLowerCase(), deployment[env].dex[currentNetwork].toLowerCase(), `${env} dex on ${currentNetwork} config error`);
        console.log("DexVault verified ✓");

        //check engine
        const engine = await adapterContract.engine();
        assert.equal(engine.toLowerCase(), deployment[env].adapter_engine.toLowerCase(), `${env} engine config error`);
        console.log("Engine verified ✓");

        //check USDC token mapping
        const usdcHash = "0xd6aca1be9729c13d677335161321649cccae6a591554772516700f986f942eaa"; // USDC hash
        const mappedToken = await adapterContract.tokenHashToToken(usdcHash);
        assert.equal(mappedToken.toLowerCase(), config[currentNetwork].USDC.toLowerCase(), `${env} USDC token mapping error`);
        console.log("USDC token mapping verified ✓");

        //check USDT token mapping
        console.log("Checking USDT token mapping...");
        const usdtHash = "0x8b1a1d9c2b109e527c9134b25b1a1833b16b6594f92daa9f6d9b7a6024bce9d0"; // USDT hash
        const mappedUsdtToken = await adapterContract.tokenHashToToken(usdtHash);
        assert.equal(mappedUsdtToken.toLowerCase(), config[currentNetwork].USDT.toLowerCase(), `${env} USDT token mapping error`);
        console.log("USDT token mapping verified ✓");

        //check protocol vault
        const protocolVault = await adapterContract.protocolVault();
        assert.equal(protocolVault.toLowerCase(), deployment[env].protocolVault.toLowerCase(), `${env} protocol vault config error`);
        console.log("Protocol vault verified ✓");


        //check brokers
        const allowedBrokers = deployment.allowedBrokersForAdapter;

        if (!allowedBrokers || allowedBrokers.length === 0) {
            console.log("No allowed brokers found in deployment config");
        } else {
            console.log(`Found ${allowedBrokers.length} brokers to verify:`);

            for (const brokerHash of allowedBrokers) {
                console.log(`Checking broker: ${brokerHash}`);
                const isAllowed = await adapterContract.isAllowedBroker(brokerHash);
                assert.equal(isAllowed, true, `${env} broker ${brokerHash} config error - not allowed`);
                console.log(`✓ Broker ${brokerHash} verified`);
            }
            console.log("All brokers verified ✓");
        }
    } catch (error) {
        console.error(`Failed to verify configuration: ${error.message}`);
        throw error;
    }
}