const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('../config.json');
const { keccak256, AbiCoder } = require("ethers");

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
    });

task("config-orderly", "Deploy strategy vault contracts on Orderly")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await configProtocolVaultLedger(taskArgs.env);
        console.log("✅ ----------------------Protocol Vault Ledger Config Done----------------------")
       
        await configOrderlyCrossChainManager(taskArgs.env);
        console.log("✅ ----------------------Orderly CrossChainManager Config Done----------------------")

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
    tx = await pvLedgerContract.setCrossChainManagerAddress(deployment[env].crossChainManager);
    await tx.wait()
    console.log("CrossChainManager set successfully")

    //set allowed sp 
    spId = getSpId(env);
    tx = await pvLedgerContract.setAllowedStrategyProvider(
        ethers.ZeroHash,
        deployment[env].protocolVault,
        deployment[env].allowedSP,
        ethers.ZeroHash,
        spId,
        true
    );
    await tx.wait()
    console.log("Allowed SP set successfully")
}
async function configOrderlyCrossChainManager(env) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set eid
    //sepolia
    //todo need to modify on mainnet
    tx = await ccManagerContract.setEid(11155111, 40161);
    await tx.wait()
    console.log("EID set successfully")

    //set peer 
    //todo need to modify on mainnet
    tx = await ccManagerContract.setPeer(40161, ethers.zeroPadValue(deployment[env].crossChainManager, 32));
    await tx.wait()
    console.log("Peer set successfully")

    //set option
    tx = await ccManagerContract.setOptions(4, 120000, 0);
    await tx.wait()
    console.log("Option set ASSETS_DISTRIBUTION successfully")

    tx = await ccManagerContract.setOptions(5, 200000, 0);
    await tx.wait()
    console.log("Option set UPDATE_USER_CLAIM successfully")

    //set ledger 
    tx = await ccManagerContract.setLedger(deployment[env].pvLedger);
    await tx.wait()
    console.log("Ledger set successfully")

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



}
async function configEVMCrossChainManager(env) {
    //get the contract instance
    const ccManagerContract = await ethers.getContractAt(
        "VaultCrossChainManager",
        deployment[env].crossChainManager
    )

    //set eid
    const chainId = hre.ethers.provider.getNetwork();
    const currentNetwork = hre.network.name;

    //todo doesn't need to set on mainnet
    tx = await ccManagerContract.setEid(291, 40200);
    await tx.wait()
    console.log("EID set successfully")

    //set peer 
    //todo need to modify on mainnet  30213
    tx = await ccManagerContract.setPeer(40200, ethers.zeroPadValue(deployment[env].crossChainManager, 32));
    await tx.wait()
    console.log("Peer set successfully")

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
function getSpId(env) {
    const orderlyHash = "0x95d85ced8adb371760e4b6437896a075632fbd6cefe699f8125a8bc1d9b19e5b"
    return keccak256(
        new AbiCoder().encode(
            ["address", "address", "bytes32"],
            [deployment[env].protocolVault, deployment[env].allowedSP, orderlyHash]
        )
    );
}