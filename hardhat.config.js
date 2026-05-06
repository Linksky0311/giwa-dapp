require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const NODIT_API_KEY = process.env.NODIT_API_KEY || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun",
    },
  },
  networks: {
    "giwa-sepolia": {
      url: `https://giwa-sepolia.nodit.io/${NODIT_API_KEY}`,
      chainId: 91342,
      accounts: PRIVATE_KEY !== "0x" + "0".repeat(64) ? [PRIVATE_KEY] : [],
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
