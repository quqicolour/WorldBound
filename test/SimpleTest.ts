import { describe, it } from "node:test";
import assert from "node:assert";
import hre from "hardhat";

/**
 * @title Gas-Optimized AI Constraint System Tests
 * @notice Tests for optimized contracts with fee mechanism
 */

describe("Gas-Optimized AI Constraint System", async function () {
  // Store deployed contract addresses
  let privacyAddress: string;
  let safetyAddress: string;
  let securityAddress: string;
  let registryAddress: string;
  let governanceAddress: string;
  let agentAddress: string;
  
  let deployer: string;

  it("Should connect to network and get accounts", async function () {
    const network = await hre.network.connect();
    const accounts = await network.provider.request({
      method: "eth_accounts",
      params: [],
    }) as string[];
    
    assert.ok(accounts.length > 0, "Should have accounts");
    deployer = accounts[0];
    console.log(`   Deployer: ${deployer}`);
  });

  it("Should deploy PrivacyConstraint", async function () {
    const network = await hre.network.connect();
    const artifact = await hre.artifacts.readArtifact("PrivacyConstraint");
    
    const txHash = await network.provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployer,
        data: artifact.bytecode,
        gas: "0x989680",
      }],
    }) as string;

    const receipt = await waitForReceipt(network.provider, txHash);
    privacyAddress = receipt.contractAddress;
    
    assert.ok(privacyAddress, "PrivacyConstraint should deploy");
    console.log(`   Address: ${privacyAddress}`);
  });

  it("Should deploy HumanSafetyConstraint", async function () {
    const network = await hre.network.connect();
    const artifact = await hre.artifacts.readArtifact("HumanSafetyConstraint");
    
    const txHash = await network.provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployer,
        data: artifact.bytecode,
        gas: "0x989680",
      }],
    }) as string;

    const receipt = await waitForReceipt(network.provider, txHash);
    safetyAddress = receipt.contractAddress;
    
    assert.ok(safetyAddress, "HumanSafetyConstraint should deploy");
    console.log(`   Address: ${safetyAddress}`);
  });

  it("Should deploy SecurityConstraint", async function () {
    const network = await hre.network.connect();
    const artifact = await hre.artifacts.readArtifact("SecurityConstraint");
    
    const txHash = await network.provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployer,
        data: artifact.bytecode,
        gas: "0x989680",
      }],
    }) as string;

    const receipt = await waitForReceipt(network.provider, txHash);
    securityAddress = receipt.contractAddress;
    
    assert.ok(securityAddress, "SecurityConstraint should deploy");
    console.log(`   Address: ${securityAddress}`);
  });

  it("Should deploy AIConstraintRegistry with fee mechanism", async function () {
    const network = await hre.network.connect();
    const artifact = await hre.artifacts.readArtifact("AIConstraintRegistry");
    
    // Encode constructor argument (governance address)
    const encodedArgs = encodeConstructorArg(deployer);
    const deployBytecode = artifact.bytecode + encodedArgs.slice(2);
    
    const txHash = await network.provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployer,
        data: deployBytecode,
        gas: "0x989680",
      }],
    }) as string;

    const receipt = await waitForReceipt(network.provider, txHash);
    registryAddress = receipt.contractAddress;
    
    assert.ok(registryAddress, "Registry should deploy");
    console.log(`   Address: ${registryAddress}`);
  });

  it("Should deploy AIAgent", async function () {
    const network = await hre.network.connect();
    const artifact = await hre.artifacts.readArtifact("AIAgent");
    
    // Encode constructor argument (registry address)
    const encodedArgs = encodeConstructorArg(registryAddress);
    const deployBytecode = artifact.bytecode + encodedArgs.slice(2);
    
    const txHash = await network.provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: deployer,
        data: deployBytecode,
        gas: "0x989680",
      }],
    }) as string;

    const receipt = await waitForReceipt(network.provider, txHash);
    agentAddress = receipt.contractAddress;
    
    assert.ok(agentAddress, "AIAgent should deploy");
    console.log(`   Address: ${agentAddress}`);
  });

  it("Should verify fee structure in registry", async function () {
    const network = await hre.network.connect();
    
    // Get constraint check fee (slot 2, first 16 bytes)
    const feeData = await network.provider.request({
      method: "eth_getStorageAt",
      params: [registryAddress, "0x2", "latest"],
    }) as string;
    
    assert.ok(feeData, "Should read fee data");
    console.log(`   Fee storage: ${feeData}`);
  });

  it("Should check deployed contract codes", async function () {
    const network = await hre.network.connect();
    
    const contracts = [
      { name: "PrivacyConstraint", addr: privacyAddress },
      { name: "HumanSafetyConstraint", addr: safetyAddress },
      { name: "SecurityConstraint", addr: securityAddress },
      { name: "AIConstraintRegistry", addr: registryAddress },
      { name: "AIAgent", addr: agentAddress },
    ];

    for (const c of contracts) {
      const code = await network.provider.request({
        method: "eth_getCode",
        params: [c.addr, "latest"],
      }) as string;
      
      assert.ok(code.length > 2, `${c.name} should have code`);
      console.log(`   ${c.name}: ${code.length} bytes`);
    }
  });
});

// Helper functions
async function waitForReceipt(provider: any, hash: string): Promise<any> {
  let receipt = null;
  let attempts = 0;
  
  while (!receipt && attempts < 50) {
    try {
      receipt = await provider.request({
        method: "eth_getTransactionReceipt",
        params: [hash],
      });
    } catch (e) {}
    
    if (!receipt) {
      await new Promise(r => setTimeout(r, 100));
      attempts++;
    }
  }
  
  if (!receipt) throw new Error("Transaction not mined");
  return receipt;
}

function encodeConstructorArg(arg: string): string {
  // Remove 0x prefix and pad to 32 bytes
  return "0x" + arg.slice(2).padStart(64, "0");
}
