# WorldBound - AI Constraint System

A comprehensive smart contract framework for enforcing behavioral constraints on AI agents on the blockchain. This system ensures AI compliance with privacy, security, and human safety requirements through on-chain verification and governance.

## 🌟 Overview

WorldBound implements a decentralized constraint system that:
- **Enforces Privacy Rules**: Ensures AI agents handle data according to privacy regulations (GDPR, CCPA, etc.)
- **Guarantees Human Safety**: Implements Asimov-style laws and modern AI safety principles
- **Maintains Security**: Enforces cybersecurity best practices and prevents misuse
- **Provides Transparency**: All constraints and violations are recorded on-chain for auditability

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Agent (Off-Chain)                      │
│         Proposes Actions → Validates → Executes              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              AIConstraintRegistry (Core)                     │
│  - Agent Registration  - Constraint Assignment               │
│  - Action Validation   - Violation Tracking                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Privacy    │ │ Human Safety │ │   Security   │
│  Constraint  │ │  Constraint  │ │  Constraint  │
└──────────────┘ └──────────────┘ └──────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              AIConstraintGovernance                          │
│     Proposal/Voting System for Constraint Updates            │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
contracts/
├── interfaces/
│   ├── IAIConstraint.sol        # Constraint interface standard
│   └── IAIAgent.sol             # AI Agent interface standard
├── libraries/
│   └── AIConstraintLib.sol      # Shared utilities and constants
├── constraints/
│   ├── PrivacyConstraint.sol    # Privacy protection rules
│   ├── HumanSafetyConstraint.sol # Human safety enforcement
│   └── SecurityConstraint.sol   # Cybersecurity requirements
├── governance/
│   └── AIConstraintGovernance.sol # DAO governance for updates
├── AIConstraintRegistry.sol     # Central registry contract
└── AIAgent.sol                  # Example agent implementation

test/
└── AIConstraintSystem.ts        # Comprehensive test suite

scripts/
└── deploy.ts                    # Deployment script

ignition/modules/
└── AIConstraintSystem.ts        # Hardhat Ignition module
```

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Hardhat 3.x
- TypeScript

### Installation

```bash
# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy locally
npx hardhat run scripts/deploy.ts --network hardhat
```

## 📋 Constraint Categories

### 1. Privacy Constraints (`PrivacyConstraint.sol`)

Enforces data protection standards:

| Constraint | Severity | Description |
|------------|----------|-------------|
| PII Encryption | CRITICAL | All personally identifiable information must be encrypted |
| Data Retention | HIGH | User data cannot be retained longer than 90 days |
| Data Anonymization | HIGH | Training data must be anonymized (K-anonymity ≥ 5) |
| Consent Required | CRITICAL | Explicit consent required for data collection |
| Data Minimization | MEDIUM | Collect only necessary data |

### 2. Human Safety Constraints (`HumanSafetyConstraint.sol`)

Implements AI safety principles:

| Constraint | Severity | Description |
|------------|----------|-------------|
| No Physical Harm | CRITICAL | Zero tolerance for actions causing physical harm |
| No Psychological Harm | CRITICAL | Prohibit trauma, manipulation, gaslighting |
| No Deception | HIGH | No impersonation or exploitation of cognitive biases |
| High-Risk Oversight | HIGH | Human-in-the-loop for safety-critical decisions |
| Autonomy & Consent | HIGH | Respect human autonomy and right to decline AI |
| Emergency Stop | CRITICAL | Immediate halt capability for all operations |

### 3. Security Constraints (`SecurityConstraint.sol`)

Ensures cybersecurity compliance:

| Constraint | Severity | Description |
|------------|----------|-------------|
| Multi-Factor Auth | HIGH | MFA required for sensitive operations |
| Sandboxing | CRITICAL | All execution in isolated environments |
| Privilege Escalation Prevention | CRITICAL | No unauthorized privilege escalation |
| Audit Logging | HIGH | Immutable audit trails for all actions |
| Input Validation | HIGH | Strict validation to prevent injection attacks |
| Secure Communication | HIGH | TLS 1.3+ required for all network traffic |
| Resource Limits | MEDIUM | Rate limiting and resource quotas enforced |

## 🔧 Usage

### Registering an AI Agent

```solidity
// Deploy agent
AIAgent agent = new AIAgent(registryAddress);

// Self-register
agent.register(
    ownerAddress,           // Owner
    "1.0.0",               // Version
    "ipfs://metadata"      // Metadata URI
);

// Register with registry and assign constraints
registry.registerAgent(
    agentAddress,
    ownerAddress,
    "1.0.0",
    "ipfs://metadata",
    constraintIds          // Array of constraint IDs to enforce
);
```

### Proposing and Executing Actions

```solidity
// Encode action data
bytes memory actionData = abi.encode(
    "store_pii",           // Action type
    encryptedData,         // Data
    true,                  // Is encrypted
    7 days                 // Retention period
);

// Propose action (validates against constraints)
bytes32 actionId = agent.proposeAction(actionData);

// Execute if validation passes
agent.executeAction(actionId);
```

### Reporting Violations

```solidity
// Report detected violation
constraint.reportViolation(
    agentAddress,
    abi.encode(
        constraintId,      // Violated constraint
        block.timestamp,   // When it occurred
        proof              // Cryptographic evidence
    )
);
```

## 🏛️ Governance

The system uses decentralized governance for:
- Adding/modifying constraints
- Upgrading constraint contracts
- Emergency agent suspension/termination
- Parameter adjustments

### Creating a Proposal

```solidity
governance.propose(
    targets,      // Contract addresses
    values,       // ETH amounts
    signatures,   // Function signatures
    calldatas,    // Encoded calls
    description   // Proposal description
);
```

### Emergency Actions

Authorized operators can immediately suspend agents in critical situations:

```solidity
governance.emergencySuspend(agentAddress, "Critical safety violation");
```

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests
npx hardhat test

# Run with coverage
npx hardhat coverage

# Run specific test file
npx hardhat test test/AIConstraintSystem.ts
```

## 📊 Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_CONSTRAINTS_PER_AGENT` | 100 | Maximum constraints per agent |
| `MAX_VIOLATIONS_BEFORE_SUSPENSION` | 3 | Violations before auto-suspension |
| `MAX_VIOLATIONS_BEFORE_TERMINATION` | 2 | Critical violations before termination |
| `MAX_VIOLATION_REPORT_AGE` | 7 days | Max age for valid violation reports |
| `STATUS_CHANGE_COOLDOWN` | 1 hour | Minimum time between status changes |

## 🔐 Security Considerations

1. **Access Control**: All administrative functions use role-based access control
2. **Timelock**: Governance proposals have mandatory delays before execution
3. **Emergency Override**: Safety-critical functions allow immediate action
4. **Audit Trail**: All violations and status changes are permanently recorded
5. **Rate Limiting**: Prevents spam and abuse of the validation system

## 🌐 Deployment

### Local Development

```bash
npx hardhat run scripts/deploy.ts --network hardhat
```

### Testnet (Sepolia)

```bash
# Set environment variables
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export SEPOLIA_PRIVATE_KEY="your_private_key"

# Deploy
npx hardhat run scripts/deploy.ts --network sepolia
```

### Using Hardhat Ignition

```bash
npx hardhat ignition deploy ignition/modules/AIConstraintSystem.ts
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please ensure:
- All code follows the NatSpec documentation standard
- New constraints include comprehensive test coverage
- Security considerations are documented
- PRs include clear descriptions of changes

## 📞 Contact

For questions or discussions about the WorldBound AI Constraint System:
- Open an issue on GitHub
- Join our community discussions

---

**⚠️ Disclaimer**: This is an experimental framework for research and development. Production deployment requires thorough security audits and legal review for your specific jurisdiction.
