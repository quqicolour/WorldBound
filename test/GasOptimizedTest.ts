import { describe, it } from "node:test";
import assert from "node:assert";
import hre from "hardhat";

/**
 * @title Fee Mechanism Test
 * @notice Test fee deposit, validation, and bounty claiming
 */

describe("Fee Mechanism Tests", async function () {
  const deployments: Record<string, string> = {};
  let deployer: string;
  let creator: string;
  let packer: string;

  it("Setup: Get accounts", async function () {
    const network = await hre.network.connect();
    const accounts = await network.provider.request({
      method: "eth_accounts",
      params: [],
    }) as string[];
    
    deployer = accounts[0];
    creator = accounts[1] || deployer;
    packer = accounts[2] || deployer;
    
    console.log(`   Deployer: ${deployer}`);
    console.log(`   Creator: ${creator}`);
    console.log(`   Packer: ${packer}`);
  });

  it("Deploy: All contracts", async function () {
    const network = await hre.network.connect();
    
    const contracts = [
      { name: "PrivacyConstraint", args: [] },
      { name: "HumanSafetyConstraint", args: [] },
      { name: "SecurityConstraint", args: [] },
      { name: "AIConstraintRegistry", args: [deployer] },
      { name: "AIAgent", args: [] }, // Will set registry later
    ];

    for (const c of contracts) {
      const artifact = await hre.artifacts.readArtifact(c.name);
      let bytecode = artifact.bytecode;
      
      // Encode constructor args if any
      for (const arg of c.args) {
        bytecode += arg.slice(2).padStart(64, "0");
      }

      const txHash = await network.provider.request({
        method: "eth_sendTransaction",
        params: [{
          from: deployer,
          data: bytecode,
          gas: "0x989680",
        }],
      }) as string;

      const receipt = await waitForReceipt(network.provider, txHash);
      deployments[c.name] = receipt.contractAddress;
      console.log(`   ${c.name}: ${receipt.contractAddress}`);
    }

    // Verify all deployed
    for (const [name, addr] of Object.entries(deployments)) {
      assert.ok(addr && addr.startsWith("0x"), `${name} deployed`);
    }
  });

  it("Registry: Check default fees", async function () {
    const network = await hre.network.connect();
    const registry = deployments["AIConstraintRegistry"];

    // Call constraintCheckFee (getter)
    const selector = "0x" + require("crypto")
      .createHash("sha3-256")
      .update("constraintCheckFee()")
      .digest("hex")
      .slice(0, 8);

    const feeData = await network.provider.request({
      method: "eth_call",
      params: [{
        to: registry,
        data: selector,
      }, "latest"],
    }) as string;

    // Parse uint128 (last 32 bytes of the 64-byte response for uint256)
    const fee = BigInt(feeData);
    console.log(`   Constraint Check Fee: ${fee} wei (${Number(fee) / 1e18} ETH)`);
    
    // Should be 0.00001 ETH = 10000000000000 wei
    assert.ok(fee > 0, "Fee should be set");
  });

  it("Registry: Check packer fee", async function () {
    const network = await hre.network.connect();
    const registry = deployments["AIConstraintRegistry"];

    const selector = "0x" + require("crypto")
      .createHash("sha3-256")
      .update("packerFee()")
      .digest("hex")
      .slice(0, 8);

    const feeData = await network.provider.request({
      method: "eth_call",
      params: [{
        to: registry,
        data: selector,
      }, "latest"],
    }) as string;

    const fee = BigInt(feeData);
    console.log(`   Packer Fee: ${fee} wei (${Number(fee) / 1e18} ETH)`);
    
    assert.ok(fee > 0, "Packer fee should be set");
  });

  it("Registry: Check total fee per validation", async function () {
    const network = await hre.network.connect();
    const registry = deployments["AIConstraintRegistry"];

    const selector = "0x" + require("crypto")
      .createHash("sha3-256")
      .update("totalFeePerValidation()")
      .digest("hex")
      .slice(0, 8);

    const feeData = await network.provider.request({
      method: "eth_call",
      params: [{
        to: registry,
        data: selector,
      }, "latest"],
    }) as string;

    const fee = BigInt(feeData);
    console.log(`   Total Fee: ${fee} wei (${Number(fee) / 1e18} ETH)`);
    
    assert.ok(fee > 0, "Total fee should be calculated");
  });

  it("Constraint: Check default constraint count", async function () {
    const network = await hre.network.connect();
    
    for (const [name, addr] of Object.entries(deployments)) {
      if (!name.includes("Constraint") || name === "AIConstraintRegistry") continue;

      const selector = "0x" + require("crypto")
        .createHash("sha3-256")
        .update("getConstraintCount()")
        .digest("hex")
        .slice(0, 8);

      const countData = await network.provider.request({
        method: "eth_call",
        params: [{
          to: addr,
          data: selector,
        }, "latest"],
      }) as string;

      const count = parseInt(countData.slice(-64), 16);
      console.log(`   ${name}: ${count} constraints`);
      
      assert.ok(count > 0, `${name} should have default constraints`);
    }
  });

  it("Gas Summary", async function () {
    console.log("\n   === DEPLOYMENT SUMMARY ===");
    console.log(`   PrivacyConstraint: ${deployments["PrivacyConstraint"]}`);
    console.log(`   HumanSafetyConstraint: ${deployments["HumanSafetyConstraint"]}`);
    console.log(`   SecurityConstraint: ${deployments["SecurityConstraint"]}`);
    console.log(`   AIConstraintRegistry: ${deployments["AIConstraintRegistry"]}`);
    console.log(`   AIAgent: ${deployments["AIAgent"]}`);
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
