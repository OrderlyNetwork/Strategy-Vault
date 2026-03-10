import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "./tasks/deploy.js";
import "./tasks/config.js";
import "./tasks/check.js";
import "./tasks/transferOwnerShip.js";
import "./tasks/verify.js";
const config: HardhatUserConfig = {
  solidity: "0.8.26",
};


const PRIVATE_KEY = vars.get("PRIVATE_KEY");
const DEPLOY_KEY = vars.get("DEPLOY_KEY");

module.exports = {
  paths: {
    sources: "./contracts",
  },
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    mainnet: {
      url: "https://eth-mainnet.alchemyapi.io/v2/ygq0_STO_nrASY4_eq3I1JMyY1aLiViw",
      accounts: [PRIVATE_KEY],
    },
    bsc: {
      url: "https://bsc-mainnet.nodereal.io/v1/64a9df0874fb4a93b9d0a3849de012d3",
      accounts: [DEPLOY_KEY],
    },
    polygon: {
      url: "https://polygon-mainnet.g.alchemy.com/v2/xW-oS8VD9ND03JvtAj-C1kPvvGNud8zo",
      accounts: [PRIVATE_KEY],
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: [PRIVATE_KEY],
    },
    arb: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [DEPLOY_KEY],
    },
    op: {
      url: "https://optimism.rpc.subquery.network/public",
      accounts: [DEPLOY_KEY],
    },
    op_sepolia: {
      url: "https://sepolia.optimism.io",
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: [DEPLOY_KEY],
    },
    base_sepolia: {
      url: "https://sepolia.base.org",
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: [PRIVATE_KEY],
    },
    orderly: {
      url: "https://rpc.orderly.network",
      accounts: [DEPLOY_KEY],
    },
    orderly_sepolia: {
      url: "https://testnet-rpc.orderly.org",
      accounts: [PRIVATE_KEY],
    },
    linea: {
      url: "https://rpc.linea.build/",
      accounts: [PRIVATE_KEY],
    },
    scroll: {
      url: "https://rpc.scroll.io/",
      accounts: [PRIVATE_KEY],
    },
    manta: {
      url: "https://pacific-rpc.manta.network/http",
      accounts: [PRIVATE_KEY],
    },
    arb_sepolia: {
      url: "https://sepolia-rollup.arbitrum.io/rpc",
      accounts: [PRIVATE_KEY],
    },
    bsc_test: {
      url: "https://data-seed-prebsc-1-s2.bnbchain.org:8545",
      accounts: [PRIVATE_KEY],
    },
    sei_dev: {
      url: "https://evm-rpc.arctic-1.seinetwork.io",
      accounts: [PRIVATE_KEY],
    },
    sei: {
      url: "https://sei-evm-rpc.stakeme.pro",
      accounts: [DEPLOY_KEY],
    }
  },
  etherscan: { //https://api.etherscan.io/v2/chainlist
    apiKey: {
      orderly_sepolia: '123',//not needed
      orderly: '123',//not needed
      sei_dev: '123',//not needed
      sei: '123',//not needed
      sepolia: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK',
      arb_sepolia: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK',
      arb: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK',
      op: "GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK",
      op_sepolia: 'TZY1RU2T9BJE973MX6SB2FU2D6QZYWW8XN',
      baseSepolia: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK',
      base: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK',
      optimisticEthereum: 'TZY1RU2T9BJE973MX6SB2FU2D6QZYWW8XN',
      bscTestnet: 'A2WXW5P36IKUUB2CGJEC6WEXR4SQ5MRKKE',
      bsc: 'GSEA6USAS8YIHX695W1B1BR3HU7Z77JUSK'
    },
    customChains: [
      {
        network: "orderly_sepolia",
        chainId: 4460,
        urls: {
          apiURL: "https://testnet-explorer.orderly.org/api",
          browserURL: "https://testnet-explorer.orderly.org/",
        }
      },
      {
        network: "orderly",
        chainId: 291,
        urls: {
          apiURL: "https://explorer.orderly.network/api",
          browserURL: "https://explorer.orderly.network/",
        }
      },
      {
        network: "op_sepolia",
        chainId: 11155420,
        urls: {
          apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimism.etherscan.io/",
        }
      },
      {
        network: "arb_sepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=421614",
          browserURL: "https://sepolia.arbiscan.io/",
        }
      },
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=84532",
          browserURL: "https://sepolia.basescan.org/",
        }
      },
      {
        network: "sei_dev",
        chainId: 713715,
        urls: {
          apiURL: "https://seitrace.com/arctic-1/api",
          browserURL: "https://devnet.seitrace.com/",
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
          browserURL: "https://basescan.org/",
        }
      },
      {
        network: "arb",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io/",
        }
      },
      {
        network: "op",
        chainId: 10,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=10",
          browserURL: "https://optimistic.etherscan.io/",
        }
      },
      {
        network: "bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://bscscan.com/",
        }
      },
      {
        network: "sei",
        chainId: 1329,
        urls: {
          apiURL: "https://seitrace.com/pacific-1/api",
          browserURL: "https://seiscan.io/",
        }
      },
    ]
  }
};

export default config;
