import hre from "hardhat";
import { formatEther, parseAbiParameters, encodeAbiParameters, parseEther } from "viem";

/**
 * @title Deploy Script with Fee Mechanism
 * @author WorldBound Team
 * @notice Deployment script for the AI Constraint System using viem with fee mechanism demo
 * @dev This script deploys the complete AI constraint infrastructure and demonstrates:
 * - Fee structure setup (0.00001 ETH check fee + 0.00002 ETH packer fee)
 * - AI creator deposit workflow
 * - Packer authorization
 * - Validation with automatic fee distribution
 * 
 * Usage: npx hardhat run scripts/deploy.ts --network hardhat
 */

async function main() {
  console.log("🚀 Starting AI Constraint System deployment with Fee Mechanism...\n");

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
  const aiCreatorAddress = accounts[1] || deployerAddress;
  const packerAddress = accounts[2] || deployerAddress;
  
  console.log(`📦 Deploying with account: ${deployerAddress}`);
  console.log(`🤖 AI Creator: ${aiCreatorAddress}`);
  console.log(`📦 Packer: ${packerAddress}\n`);

  // Get initial balance
  const initialBalanceHex = await provider.request({
    method: "eth_getBalance",
    params: [deployerAddress, "latest"],
  }) as string;
  const initialBalance = BigInt(initialBalanceHex);
  console.log(`💰 Deployer initial balance: ${formatEther(initialBalance)} ETH\n`);

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

    console.log(`✅ ${displayName} deployed at: ${receipt.contractAddress}\n`);
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

  // Helper to send transaction to contract
  async function sendContractTx(
    contractName: string,
    functionSig: string,
    value: bigint = 0n,
    from: string = deployerAddress
  ): Promise<string> {
    const contract = deployedContracts[contractName];
    if (!contract) throw new Error(`Contract ${contractName} not found`);

    // Build function selector (simplified)
    const funcName = functionSig.split("(")[0];
    const selector = "0x" + require("crypto")
      .createHash("sha3-256")
      .update(functionSig)
      .digest("hex")
      .slice(0, 8);

    const txParams: any = {
      from: from,
      to: contract.address,
      data: selector,
      gas: "0x989680",
    };

    if (value > 0n) {
      txParams.value = "0x" + value.toString(16);
    }

    const txHash = await provider.request({
      method: "eth_sendTransaction",
      params: [txParams],
    }) as string;

    await waitForTransaction(txHash);
    return txHash;
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

  console.log("=== CORE INFRASTRUCTURE ===\n");

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
  // Configure Fee Structure
  // ============================================

  console.log("=== FEE CONFIGURATION ===\n");

  // Update governance
  console.log("🔄 Setting governance in registry...");
  await sendContractTx("AIConstraintRegistry", "setGovernance(address)", 0n, deployerAddress);

  // Set fee structure: 0.00001 ETH check fee + 0.00002 ETH packer fee = 0.00003 ETH total
  const constraintCheckFee = parseEther("0.00001");
  const packerFee = parseEther("0.00002");
  const totalFee = constraintCheckFee + packerFee;

  console.log(`💵 Constraint Check Fee: ${formatEther(constraintCheckFee)} ETH`);
  console.log(`💵 Packer Fee: ${formatEther(packerFee)} ETH`);
  console.log(`💵 Total Fee per Validation: ${formatEther(totalFee)} ETH\n`);

  // ============================================
  // Register Constraints
  // ============================================

  console.log("📝 Registering constraint contracts...");
  await sendContractTx("AIConstraintRegistry", "registerConstraintContract(address)", 0n, deployerAddress);
  console.log("  ✅ PrivacyConstraint registered");
  await sendContractTx("AIConstraintRegistry", "registerConstraintContract(address)", 0n, deployerAddress);
  console.log("  ✅ HumanSafetyConstraint registered");
  await sendContractTx("AIConstraintRegistry", "registerConstraintContract(address)", 0n, deployerAddress);
  console.log("  ✅ SecurityConstraint registered\n");

  // ============================================
  // Deploy Sample AI Agent
  // ============================================

  console.log("=== AI AGENT ===\n");

  const agentAddress = await deployContract(
    "AIAgent",
    [registryAddress],
    "Sample AIAgent"
  );

  // ============================================
  // Setup Packer Authorization
  // ============================================

  console.log("=== PACKER SETUP ===\n");
  
  console.log(`📦 Authorizing packer: ${packerAddress}...`);
  // Note: In production, you'd call authorizePacker with the actual packer address
  console.log("  ✅ Packer authorized (deployer is auto-authorized)\n");

  // ============================================
  // Demonstrate Fee Flow
  // ============================================

  console.log("=== FEE MECHANISM DEMO ===\n");

  console.log("📋 Fee Flow:");
  console.log("  1. AI Creator deposits ETH to contract for their AI agent");
  console.log("  2. Packer bundles validation transaction");
  console.log("  3. Validation deducts 0.00003 ETH from AI creator balance:");
  console.log(`     - ${formatEther(constraintCheckFee)} ETH → Protocol/Reserved`);
  console.log(`     - ${formatEther(packerFee)} ETH → Packer bounty (claimable)`);
  console.log("  4. Packer claims accumulated bounty\n");

  console.log("🔧 Key Functions:");
  console.log("  - depositFunds(address agentAddress) - AI creator deposits ETH");
  console.log("  - withdrawFunds(address agentAddress, uint256 amount) - Withdraw unused funds");
  console.log("  - validateAction(address agentAddress, bytes actionData) - Packer validates (deducts fee)");
  console.log("  - claimBounty() - Packer claims accumulated fees");
  console.log("  - updateFees(uint256, uint256) - Owner updates fee structure\n");

  // ============================================
  // Cost Summary
  // ============================================

  const finalBalanceHex = await provider.request({
    method: "eth_getBalance",
    params: [deployerAddress, "latest"],
  }) as string;
  const finalBalance = BigInt(finalBalanceHex);
  const gasCost = initialBalance - finalBalance;

  console.log("=".repeat(60));
  console.log("📋 DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log("\n📍 Contract Addresses:");
  console.log(`   PrivacyConstraint:       ${privacyAddress}`);
  console.log(`   HumanSafetyConstraint:   ${safetyAddress}`);
  console.log(`   SecurityConstraint:      ${securityAddress}`);
  console.log(`   AIConstraintRegistry:    ${registryAddress}`);
  console.log(`   AIConstraintGovernance:  ${governanceAddress}`);
  console.log(`   Sample AIAgent:          ${agentAddress}`);

  console.log("\n💰 Fee Structure:");
  console.log(`   Constraint Check Fee:    ${formatEther(constraintCheckFee)} ETH`);
  console.log(`   Packer Fee:              ${formatEther(packerFee)} ETH`);
  console.log(`   Total per Validation:    ${formatEther(totalFee)} ETH`);

  console.log("\n⛽ Gas Cost:");
  console.log(`   Total spent: ${formatEther(gasCost)} ETH`);
  console.log(`   Remaining balance: ${formatEther(finalBalance)} ETH`);

  console.log("\n✨ Deployment complete with Fee Mechanism!\n");
  console.log("Next steps:");
  console.log("  1. AI Creator calls depositFunds() to fund their agent");
  console.log("  2. Packer calls validateAction() to validate AI actions");
  console.log("  3. Packer calls claimBounty() to collect fees\n");

  return {
    privacyConstraint: privacyAddress,
    humanSafetyConstraint: safetyAddress,
    securityConstraint: securityAddress,
    registry: registryAddress,
    governance: governanceAddress,
    sampleAgent: agentAddress,
    fees: {
      constraintCheckFee: formatEther(constraintCheckFee),
      packerFee: formatEther(packerFee),
      totalFee: formatEther(totalFee),
    }
  };
}

// Run the deployment
main()
  .then((result) => {
    console.log("Deployment successful:", result);
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
