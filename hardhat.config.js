require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    somnia: {
      url: "https://dream-rpc.somnia.network",
      accounts: [
        "9da5fd0ecccd23652031c21c5be3b9e246be331192df74edbf87e56875400c66",
      ], // put dev menomonic or PK here,
    },
  },
};
