const endpointV2ABI = require("@layerzerolabs/lz-evm-protocol-v2/artifacts/contracts/EndpointV2.sol/EndpointV2.json").abi;
const config = require('../config.json');

function checkNetworkEnvRestrictions(currentNetwork, env) {
    if (currentNetwork === 'orderly_sepolia') {
        const allowedEnvs = ['dev', 'qa', 'staging'];
        if (!allowedEnvs.includes(env)) {
            throw new Error(`network is 'orderly', env must be one of ${allowedEnvs.join(', ')} rather than '${env}'`);
        }
        return true;
    } else if (currentNetwork === 'orderly') {
        if (env !== 'mainnet') {
            throw new Error(`network is 'orderly_sepolia', env must be 'mainnet' rather than '${env}'`);
        }
        return true;
    } else {
        throw new Error(`network is '${currentNetwork}', env must be 'orderly' or 'orderly_sepolia'`);
    }
}

async function getEndpointV2(network) {
    const endpointv2 = await ethers.getContractAt(
        endpointV2ABI,
        config[network].endpoint
    );
    return endpointv2;
}
module.exports = {
    checkNetworkEnvRestrictions,
    getEndpointV2
}