const { ethers } = require("hardhat");

async function main() {
  console.log("Starting Sone contract deployment...");

  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log(
    "Account balance:",
    (await deployer.provider.getBalance(deployer.address)).toString()
  );

  // Contract constructor parameters
  const deploymentParams = {
    owner: deployer.address, // Contract owner (can be changed later)
    roundDuration: 3600, // 1 hour in seconds (uint40)
    valuePerEntry: ethers.parseEther("0.01"), // 0.01 ETH per entry (uint256)
    protocolFeeRecipient: deployer.address, // Address to receive protocol fees
    protocolFeeBp: 500, // 5% protocol fee (500 basis points, uint16)
    maximumNumberOfParticipantsPerRound: 100, // Max 100 participants per round (uint40)
    keeper: deployer.address, // Keeper address for drawing winners
  };

  console.log("\nDeployment Parameters:");
  console.log("- Owner:", deploymentParams.owner);
  console.log("- Round Duration:", deploymentParams.roundDuration, "seconds");
  console.log(
    "- Value Per Entry:",
    ethers.formatEther(deploymentParams.valuePerEntry),
    "ETH"
  );
  console.log(
    "- Protocol Fee Recipient:",
    deploymentParams.protocolFeeRecipient
  );
  console.log("- Protocol Fee:", deploymentParams.protocolFeeBp / 100, "%");
  console.log(
    "- Max Participants:",
    deploymentParams.maximumNumberOfParticipantsPerRound
  );
  console.log("- Keeper:", deploymentParams.keeper);

  // Deploy the contract
  console.log("\nDeploying Sone contract...");
  const Sone = await ethers.getContractFactory("Sone");

  const sone = await Sone.deploy(
    deploymentParams.owner,
    deploymentParams.roundDuration,
    deploymentParams.valuePerEntry,
    deploymentParams.protocolFeeRecipient,
    deploymentParams.protocolFeeBp,
    deploymentParams.maximumNumberOfParticipantsPerRound,
    deploymentParams.keeper
  );

  await sone.waitForDeployment();
  const contractAddress = await sone.getAddress();

  console.log("\n✅ Sone contract deployed successfully!");
  console.log("Contract address:", contractAddress);
  console.log("Transaction hash:", sone.deploymentTransaction().hash);

  // Verify deployment by calling some view functions
  console.log("\n📊 Verifying deployment...");
  try {
    const currentRoundId = await sone.currentRoundId();
    const valuePerEntry = await sone.valuePerEntry();
    const owner = await sone.owner();

    console.log("- Current Round ID:", currentRoundId.toString());
    console.log("- Value Per Entry:", ethers.formatEther(valuePerEntry), "ETH");
    console.log("- Contract Owner:", owner);
    console.log("✅ Contract is working correctly!");
  } catch (error) {
    console.error("❌ Error verifying contract:", error.message);
  }

  // Save deployment info
  const network = await ethers.provider.getNetwork();
  const deploymentInfo = {
    contractName: "Sone",
    contractAddress: contractAddress,
    deployerAddress: deployer.address,
    network: network.name,
    chainId: network.chainId.toString(),
    blockNumber: (await ethers.provider.getBlockNumber()).toString(),
    deploymentParams: {
      ...deploymentParams,
      valuePerEntry: ethers.formatEther(deploymentParams.valuePerEntry) + " ETH"
    },
    transactionHash: sone.deploymentTransaction().hash,
    timestamp: new Date().toISOString(),
  };

  console.log("\n📄 Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Instructions for next steps
  console.log("\n🚀 Next Steps:");
  console.log("1. Verify the contract on Etherscan (if on mainnet/testnet)");
  console.log("2. Add supported ERC20 tokens using addSupportedToken()");
  console.log("3. Configure native token support using setNativeTokenConfig()");
  console.log("4. Test the contract with small deposits");
  console.log("\n📝 Save this deployment info for your records!");

  return contractAddress;
}

// Execute deployment
main()
  .then((contractAddress) => {
    console.log(
      `\n🎉 Deployment completed! Contract address: ${contractAddress}`
    );
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  });
