// Get implementation address from ERC1967 proxy
// Usage: PROXY_ADDRESS=0x... npx hardhat run scripts/utils/getImplementation.js --network <network>

async function main() {
  const proxyAddress = process.env.PROXY_ADDRESS;
  
  if (!proxyAddress) {
    console.error('Error: PROXY_ADDRESS environment variable not set');
    console.error('Usage: PROXY_ADDRESS=0x... npx hardhat run scripts/utils/getImplementation.js --network <network>');
    process.exit(1);
  }

  // ERC1967 implementation storage slot
  // keccak256("eip1967.proxy.implementation") - 1
  const IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';

  try {
    const implementationBytes = await ethers.provider.getStorage(proxyAddress, IMPLEMENTATION_SLOT);
    
    // Convert 32-byte storage value to address
    const hexWithoutPrefix = implementationBytes.slice(2);
    const addressHex = hexWithoutPrefix.slice(-40);
    const implementationAddr = ethers.getAddress('0x' + addressHex);

    if (implementationAddr === ethers.ZeroAddress) {
      throw new Error('No implementation found in proxy contract');
    }

    console.log(implementationAddr);
  } catch (error) {
    console.error('Error reading implementation:', error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

