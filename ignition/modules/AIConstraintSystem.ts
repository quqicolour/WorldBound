import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * @title AIConstraintSystem Module
 * @author WorldBound Team
 * @notice Hardhat Ignition module for deploying the complete AI constraint system
 * @dev This module deploys all contracts in the correct order:
 * 1. Constraint contracts (Privacy, HumanSafety, Security)
 * 2. AIConstraintRegistry
 * 3. AIConstraintGovernance
 * 4. Sample AIAgent
 * 
 * The deployment ensures proper initialization and linking between contracts.
 */

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

  // Deploy registry with placeholder governance (will update after governance deploy)
  // We use a temporary zero address that will be updated
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

  // Register constraint contracts with the registry
  const registerPrivacy = m.call(
    registry,
    "registerConstraintContract",
    [privacyConstraint],
    {
      id: "RegisterPrivacyConstraint",
      after: [setGovernance],
    }
  );

  const registerHumanSafety = m.call(
    registry,
    "registerConstraintContract",
    [humanSafetyConstraint],
    {
      id: "RegisterHumanSafetyConstraint",
      after: [setGovernance],
    }
  );

  const registerSecurity = m.call(
    registry,
    "registerConstraintContract",
    [securityConstraint],
    {
      id: "RegisterSecurityConstraint",
      after: [setGovernance],
    }
  );

  // Deploy a sample AI agent
  const sampleAgent = m.contract("AIAgent", [registry], {
    id: "SampleAIAgent",
    after: [setGovernance],
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
