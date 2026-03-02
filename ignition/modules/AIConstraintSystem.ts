import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * @title AIConstraintSystem Module
 * @author WorldBound Team
 * @notice Hardhat Ignition module for deploying the complete AI constraint system with fee mechanism
 * @dev This module deploys all contracts in the correct order:
 * 1. Constraint contracts (Privacy, HumanSafety, Security)
 * 2. AIConstraintRegistry with initial fee configuration
 * 3. AIConstraintGovernance
 * 4. Sample AIAgent
 * 
 * Fee Structure:
 * - Constraint Check Fee: 0.00001 ETH per validation
 * - Packer Fee: 0.00002 ETH per transaction
 * 
 * The deployment ensures proper initialization and linking between contracts.
 */

// Fee constants (in wei)
const CONSTRAINT_CHECK_FEE = 10000000000000n; // 0.00001 ETH
const PACKER_FEE = 20000000000000n;            // 0.00002 ETH

export default buildModule("AIConstraintSystem", (m) => {
  // Deploy constraint contracts first
  const privacyConstraint = m.contract("PrivacyConstraint", [], {
    id: "PrivacyConstraint",
  });

  const humanSafetyConstraint = m.contract("HumanSafetyConstraint", [], {
    id: "HumanSafetyConstraint",
  });

  const securityConstraint = m.contract("SecurityConstraint", [], {
    id: "SecurityConstraint",
  });

  // Deploy registry with deployer as initial governance (will update after governance deploy)
  const registry = m.contract("AIConstraintRegistry", [m.getAccount(0)], {
    id: "AIConstraintRegistry",
  });

  // Deploy governance
  // Parameters: registry, token (using deployer address as placeholder), threshold, votingPeriod, quorum, timelockDelay
  const governance = m.contract(
    "AIConstraintGovernance",
    [registry, m.getAccount(0), 1, 100, 4000, 172800],
    {
      id: "AIConstraintGovernance",
    }
  );

  // Update registry with correct governance address
  const setGovernance = m.call(registry, "setGovernance", [governance], {
    id: "SetGovernance",
  });

  // Set initial fee structure
  // constraintCheckFee = 0.00001 ETH, packerFee = 0.00002 ETH
  const setFees = m.call(
    registry, 
    "updateFees", 
    [CONSTRAINT_CHECK_FEE, PACKER_FEE], 
    {
      id: "SetFees",
      after: [setGovernance],
    }
  );

  // Register constraint contracts with the registry
  const registerPrivacy = m.call(
    registry,
    "registerConstraintContract",
    [privacyConstraint],
    {
      id: "RegisterPrivacyConstraint",
      after: [setFees],
    }
  );

  const registerHumanSafety = m.call(
    registry,
    "registerConstraintContract",
    [humanSafetyConstraint],
    {
      id: "RegisterHumanSafetyConstraint",
      after: [setFees],
    }
  );

  const registerSecurity = m.call(
    registry,
    "registerConstraintContract",
    [securityConstraint],
    {
      id: "RegisterSecurityConstraint",
      after: [setFees],
    }
  );

  // Deploy a sample AI agent
  const sampleAgent = m.contract("AIAgent", [registry], {
    id: "SampleAIAgent",
    after: [setFees],
  });

  return {
    privacyConstraint,
    humanSafetyConstraint,
    securityConstraint,
    registry,
    governance,
    sampleAgent,
  };
});
