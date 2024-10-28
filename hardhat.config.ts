import { HardhatUserConfig,vars} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.26",
};


const PRIVATE_KEY = vars.get("PRIVATE_KEY");

module.exports = {
  solidity: "0.8.27",
  networks: {
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: 'UFDT2P2RSDHXGX1TUG1RJXAHPQS26GZ6I6'
    }
  }
};

export default config;
