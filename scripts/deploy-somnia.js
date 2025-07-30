const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting Sone contract deployment on SOMNIA network...");

  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Check account balance
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "STT");

  // Check if balance is sufficient (recommend at least 1 STT for safety)
  const minimumBalance = ethers.parseEther("1.0");
  if (balance < minimumBalance) {
    console.log("⚠️  WARNING: Low balance detected!");
    console.log("Current balance:", ethers.formatEther(balance), "STT");
    console.log(
      "Recommended minimum:",
      ethers.formatEther(minimumBalance),
      "STT"
    );
    console.log("You may need more STT to successfully deploy the contract.");
    console.log("Consider getting STT from:");
    console.log("- Somnia faucet (if available)");
    console.log("- DEX exchanges");
    console.log("- Bridge from other networks");
  }

  // Production-ready parameters for Somnia network
  const deploymentParams = {
    owner: deployer.address, // You may want to change this to a multisig
    roundDuration: 120, // 2 min in seconds (longer for production) - uint40
    valuePerEntry: ethers.parseEther("0.01"), // 0.01  per entry (lower for accessibility)
    protocolFeeRecipient: deployer.address, // Change to treasury address
    protocolFeeBp: 300, // 3% protocol fee (lower for production) - uint16
    maximumNumberOfParticipantsPerRound: 100, // Higher for production - uint40
    keeper: deployer.address, // Change to keeper bot address
  };

  console.log("\n📋 Production Deployment Parameters for SOMNIA:");
  console.log("- Owner:", deploymentParams.owner);
  console.log("- Round Duration:", deploymentParams.roundDuration, "seconds");
  console.log(
    "- Value Per Entry:",
    ethers.formatEther(deploymentParams.valuePerEntry),
    "STT"
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

  // Confirm deployment
  console.log("\n⚠️  WARNING: This will deploy to SOMNIA mainnet!");
  console.log("Make sure all parameters are correct before proceeding.\n");

  // Deploy the contract
  console.log("🔥 Deploying Sone contract to SOMNIA...");
  const Sone = await ethers.getContractFactory("Sone");

  // Estimate gas for deployment
  const deployTx = Sone.getDeployTransaction(
    deploymentParams.owner,
    deploymentParams.roundDuration,
    deploymentParams.valuePerEntry,
    deploymentParams.protocolFeeRecipient,
    deploymentParams.protocolFeeBp,
    deploymentParams.maximumNumberOfParticipantsPerRound,
    deploymentParams.keeper
  );

  const gasEstimate = await deployer.estimateGas(deployTx);
  const gasPrice = await deployer.provider.getFeeData();
  const estimatedCost = gasEstimate * gasPrice.gasPrice;

  console.log("⛽ Gas estimate:", gasEstimate.toString());
  console.log(
    "💰 Estimated deployment cost:",
    ethers.formatEther(estimatedCost),
    "STT"
  );

  const sone = await Sone.deploy(
    deploymentParams.owner,
    deploymentParams.roundDuration,
    deploymentParams.valuePerEntry,
    deploymentParams.protocolFeeRecipient,
    deploymentParams.protocolFeeBp,
    deploymentParams.maximumNumberOfParticipantsPerRound,
    deploymentParams.keeper
  );

  console.log("⏳ Waiting for deployment confirmation...");
  await sone.waitForDeployment();
  const contractAddress = await sone.getAddress();

  console.log("\n✅ Sone contract deployed successfully to SOMNIA!");
  console.log("📍 Contract address:", contractAddress);
  console.log("🔗 Transaction hash:", sone.deploymentTransaction().hash);
  console.log(
    "🌐 Somnia Explorer:",
    `https://shannon-explorer.somnia.network/tx/${
      sone.deploymentTransaction().hash
    }`
  );

  // Verify deployment by calling some view functions
  console.log("\n🔍 Verifying deployment...");
  try {
    const currentRoundId = await sone.currentRoundId();
    const valuePerEntry = await sone.valuePerEntry();
    const owner = await sone.owner();
    const keeper = await sone.keeper();

    console.log("- Current Round ID:", currentRoundId.toString());
    console.log("- Value Per Entry:", ethers.formatEther(valuePerEntry), "STT");
    console.log("- Contract Owner:", owner);
    console.log("- Keeper Address:", keeper);
    console.log("✅ Contract verification successful!");
  } catch (error) {
    console.error("❌ Error verifying contract:", error.message);
  }

  // Get network info
  const network = await ethers.provider.getNetwork();

  // Save deployment info
  const deploymentInfo = {
    contractName: "Sone",
    contractAddress: contractAddress,
    deployerAddress: deployer.address,
    network: "somnia",
    chainId: network.chainId.toString(),
    blockNumber: (await ethers.provider.getBlockNumber()).toString(),
    deploymentParams: {
      ...deploymentParams,
      valuePerEntry:
        ethers.formatEther(deploymentParams.valuePerEntry) + " STT",
    },
    transactionHash: sone.deploymentTransaction().hash,
    explorerUrl: `https://explorer.somnia.network/tx/${
      sone.deploymentTransaction().hash
    }`,
    timestamp: new Date().toISOString(),
    gasUsed: gasEstimate.toString(),
    deploymentCost: ethers.formatEther(estimatedCost) + " STT",
  };

  console.log("\n📊 SOMNIA Deployment Summary:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Production deployment checklist
  console.log("\n✅ Production Deployment Checklist:");
  console.log("1. ⚠️  Change owner to multisig wallet");
  console.log("2. ⚠️  Change protocolFeeRecipient to treasury wallet");
  console.log("3. ⚠️  Change keeper to automated keeper bot");
  console.log("4. 🔧 Add supported ERC20 tokens:");
  console.log(
    "   - await sone.addSupportedToken(tokenAddress, decimals, minDeposit, ratio)"
  );
  console.log("5. 🔧 Configure native token support:");
  console.log("   - await sone.setNativeTokenConfig(true, minDeposit, ratio)");
  console.log("6. 🧪 Test with small deposits before announcing");
  console.log("7. 🔒 Consider getting a security audit");
  console.log("8. 📢 Verify contract source code on Somnia Explorer");

  // Save deployment info to file
  const fs = require("fs");
  const deploymentFile = `deployment-somnia-${Date.now()}.json`;
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n💾 Deployment info saved to: ${deploymentFile}`);

  return contractAddress;
}

// Execute deployment
main()
  .then((contractAddress) => {
    console.log(`\n🎉 SOMNIA deployment completed successfully!`);
    console.log(`📍 Contract Address: ${contractAddress}`);
    console.log(
      `🌐 Explorer: https://explorer.somnia.network/address/${contractAddress}`
    );
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ SOMNIA deployment failed:", error);
    process.exit(1);
  });
