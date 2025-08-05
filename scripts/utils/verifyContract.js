const hre = require("hardhat");

async function verifyContract(contractAddress, constructorArguments = [], contractName = "Contract") {
    try {
        console.log(`🔍 Verifying ${contractName} contract: ${contractAddress}`);
        
        await hre.run("verify:verify", {
            address: contractAddress,
            constructorArguments: constructorArguments
        });
        
        console.log(`✅ ${contractName} contract verified successfully: ${contractAddress}`);
        return true;
        
    } catch (error) {
        console.log(`⚠️ ${contractName} contract verification failed: ${error.message}`);
        
        if (error.message.includes("Already Verified") || 
            error.message.includes("already verified") ||
            error.message.includes("Contract source code already verified")) {
            console.log(`📋 ${contractName} contract was already verified: ${contractAddress}`);
            return true;
        }
        
        console.error(`❌ ${contractName} contract verification error:`, error.message);
        return false;
    }
}


async function verifyMultipleContracts(contracts) {
    const results = [];
    
    for (const contract of contracts) {
        const result = await verifyContract(
            contract.address, 
            contract.constructorArguments || [], 
            contract.name || "Contract"
        );
        results.push(result);
        
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    return results;
}


async function verifyContractWithRetry(contractAddress, constructorArguments = [], contractName = "Contract", maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        console.log(`🔄 Verification attempt ${attempt}/${maxRetries} for ${contractName}`);
        
        const success = await verifyContract(contractAddress, constructorArguments, contractName);
        
        if (success) {
            return true;
        }
        
        if (attempt < maxRetries) {
            const delay = attempt * 2000;
            console.log(`⏳ Retrying in ${delay/1000} seconds...`);
            await new Promise(resolve => setTimeout(resolve, delay));
        }
    }
    
    console.log(`❌ Failed to verify ${contractName} after ${maxRetries} attempts`);
    return false;
}

module.exports = {
    verifyContract,
    verifyMultipleContracts,
    verifyContractWithRetry
};