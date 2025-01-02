import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "./tasks/deploy.js";

const config: HardhatUserConfig = {
  solidity: "0.8.26",
};


const PRIVATE_KEY = vars.get("PRIVATE_KEY");

module.exports = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000000,
      },
    },
  },
  networks: {
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts: [PRIVATE_KEY],
    },
    orderly_sepolia: {
      url: "https://testnet-rpc.orderly.org",
      accounts: [PRIVATE_KEY],
    },
    arb_sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: [PRIVATE_KEY],
    }
  },
  etherscan: {
    apiKey: {
      sepolia: 'UFDT2P2RSDHXGX1TUG1RJXAHPQS26GZ6I6'
    }
  }
};

export default config;
