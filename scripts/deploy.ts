import hre from "hardhat";
import { formatEther, parseAbiParameters, encodeAbiParameters } from "viem";

/**
 * @title Deploy Script
 * @author WorldBound Team
 * @notice Deployment script for the AI Constraint System using viem
 * @dev This script uses Hardhat 3.x EDR provider with viem utilities
 * Usage: npx hardhat run scripts/deploy.ts --network hardhat
 */

async function main() {
  console.log("🚀 Starting AI Constraint System deployment with viem...\n");

  // Connect to the network
  const network = await hre.network.connect();
  const provider = network.provider;

  // Get accounts
  const accounts = await provider.request({
    method: "eth_accounts",
    params: [],
  }) as string[];

  if (!accounts || accounts.length === 0) {
    throw new Error("No accounts available");
  }

  const deployerAddress = accounts[0];
  console.log(`📦 Deploying with account: ${deployerAddress}`);

  // Get initial balance
  const initialBalanceHex = await provider.request({
    method: "eth_getBalance",
    params: [deployerAddress, "latest"],
  }) as string;
  const initialBalance = BigInt(initialBalanceHex);
  console.log(`💰 Initial balance: ${formatEther(initialBalance)} ETH\n`);

  // Store deployed contracts
  const deployedContracts: Record<string, { address: string; abi: any[] }> = {};

  // Helper function to deploy contract
  async function deployContract(
    contractName: string,
    args: any[] = [],
    label?: string
  ): Promise<string> {
    const displayName = label || contractName;
    console.log(`📄 Deploying ${displayName}...`);

    // Get contract artifact
    const artifact = await hre.artifacts.readArtifact(contractName);

    // Encode constructor arguments if any
    let deployBytecode = artifact.bytecode;
    if (args.length > 0 && artifact.abi) {
      const constructorAbi = artifact.abi.find((item: any) => item.type === "constructor");
      if (constructorAbi && constructorAbi.inputs && constructorAbi.inputs.length > 0) {
        // Encode constructor parameters using viem
        const types = constructorAbi.inputs.map((input: any) => input.type);
        const encodedArgs = encodeConstructorArgs(types, args);
        deployBytecode = deployBytecode + encodedArgs.slice(2);
      }
    }

    // Send deployment transaction
    const txHash = await provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployerAddress,
        data: deployBytecode,
        gas: "0x989680", // 10M gas limit
      }],
    }) as string;

    console.log(`   ⏳ Transaction sent: ${txHash}`);

    // Wait for receipt
    const receipt = await waitForTransaction(txHash);

    if (!receipt.contractAddress) {
      throw new Error(`Failed to deploy ${displayName} - no contract address in receipt`);
    }

    console.log(`✅ ${displayName} deployed at: ${receipt.contractAddress}`);
    deployedContracts[contractName] = {
      address: receipt.contractAddress,
      abi: artifact.abi,
    };

    return receipt.contractAddress;
  }

  // Helper to encode constructor arguments using viem
  function encodeConstructorArgs(types: string[], values: any[]): string {
    if (types.length === 0 || values.length === 0) return "0x";
    
    try {
      // Build parameter string for viem
      const paramString = types.join(",");
      const encoded = encodeAbiParameters(
        parseAbiParameters(paramString),
        values
      );
      return encoded;
    } catch (e) {
      // Fallback: manual encoding for simple types
      console.log(`   ⚠️  Using fallback encoding for: ${types.join(",")}`);
      let encoded = "";
      for (let i = 0; i < values.length; i++) {
        const value = values[i];
        if (typeof value === "string" && value.startsWith("0x")) {
          // Address - pad to 32 bytes
          encoded += value.slice(2).padStart(64, "0");
        } else if (typeof value === "number" || typeof value === "bigint") {
          // Number - convert to hex and pad
          const hex = BigInt(value).toString(16);
          encoded += hex.padStart(64, "0");
        }
      }
      return "0x" + encoded;
    }
  }

  // Helper to wait for transaction receipt
  async function waitForTransaction(hash: string): Promise<any> {
    let receipt = null;
    let attempts = 0;
    const maxAttempts = 50;

    while (!receipt && attempts < maxAttempts) {
      try {
        receipt = await provider.request({
          method: "eth_getTransactionReceipt",
          params: [hash],
        }) as any;
      } catch (e) {
        // Transaction not yet mined
      }

      if (!receipt) {
        await new Promise(resolve => setTimeout(resolve, 100));
        attempts++;
      }
    }

    if (!receipt) {
      throw new Error(`Transaction ${hash} not mined after ${maxAttempts} attempts`);
    }

    return receipt;
  }

  // ============================================
  // Deploy Constraint Contracts
  // ============================================

  console.log("=== CONSTRAINT CONTRACTS ===\n");
  
  const privacyAddress = await deployContract("PrivacyConstraint", [], "PrivacyConstraint");
  const safetyAddress = await deployContract("HumanSafetyConstraint", [], "HumanSafetyConstraint");
  const securityAddress = await deployContract("SecurityConstraint", [], "SecurityConstraint");

  // ============================================
  // Deploy Core Infrastructure
  // ============================================

  console.log("\n=== CORE INFRASTRUCTURE ===\n");

  const registryAddress = await deployContract(
    "AIConstraintRegistry",
    [deployerAddress],
    "AIConstraintRegistry"
  );

  const governanceAddress = await deployContract(
    "AIConstraintGovernance",
    [registryAddress, deployerAddress, 1, 100, 4000, 172800],
    "AIConstraintGovernance"
  );

  // ============================================
  // Deploy Sample AI Agent
  // ============================================

  console.log("\n=== AI AGENT ===\n");

  const agentAddress = await deployContract(
    "AIAgent",
    [registryAddress],
    "Sample AIAgent"
  );

  // ============================================
  // Cost Summary
  // ============================================

  const finalBalanceHex = await provider.request({
    method: "eth_getBalance",
    params: [deployerAddress, "latest"],
  }) as string;
  const finalBalance = BigInt(finalBalanceHex);
  const gasCost = initialBalance - finalBalance;

  console.log("\n" + "=".repeat(60));
  console.log("📋 DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log("\n📍 Contract Addresses:");
  console.log(`   PrivacyConstraint:       ${privacyAddress}`);
  console.log(`   HumanSafetyConstraint:   ${safetyAddress}`);
  console.log(`   SecurityConstraint:      ${securityAddress}`);
  console.log(`   AIConstraintRegistry:    ${registryAddress}`);
  console.log(`   AIConstraintGovernance:  ${governanceAddress}`);
  console.log(`   Sample AIAgent:          ${agentAddress}`);

  console.log("\n💰 Gas Cost:");
  console.log(`   Total spent: ${formatEther(gasCost)} ETH`);
  console.log(`   Remaining balance: ${formatEther(finalBalance)} ETH`);

  console.log("\n✨ Deployment complete with viem!\n");

  return {
    privacyConstraint: privacyAddress,
    humanSafetyConstraint: safetyAddress,
    securityConstraint: securityAddress,
    registry: registryAddress,
    governance: governanceAddress,
    sampleAgent: agentAddress,
  };
}

// Run the deployment
main()
  .then((addresses) => {
    console.log("Deployment successful:", addresses);
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
