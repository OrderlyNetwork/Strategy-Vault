const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('../config.json');
const { keccak256, AbiCoder } = require("ethers");
const { getAccountId, getStrategyProviderId, getVaultId } = require('../scripts/utils/getId');
const { checkNetworkEnvRestrictions } = require('./utils')
const broker = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
const { assert } = require("chai");

const mainnets = ['mainnet', 'op', 'base', 'arb']
const tests = ['sepolia', 'op_sepolia', 'arb_sepolia', 'base_sepolia']

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
    assert.equal(engine.toLowerCase(), deployment[env].engine.toLowerCase(), ` ${env} engine config error`);
}
