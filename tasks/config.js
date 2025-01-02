const fs = require('fs');
const path = require('path');
const deployment = require('../deployment.json');
const config = require('./config.json');

// 定义部署任务  
task("deploy", "Deploy strategy vault contracts")
    .addParam("env", "Deployment environment (dev/qa/staging/mainnet)")
    .setAction(async (taskArgs, hre) => {
        const validEnvs = ['dev', 'qa', 'staging', 'mainnet'];
        if (!validEnvs.includes(taskArgs.env)) {
            throw new Error(`Invalid environment. Must be one of: ${validEnvs.join(', ')}`);
        }
        await deployProtocolLedger(taskArgs.env);
        await deployCrossChainManager(taskArgs.env);
        await deployProtocolVault(taskArgs.env);

    });