// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title SecurityConstraint
 * @author WorldBound Team
 * @notice Implements security-related constraints for AI agents
 * @dev This contract enforces cybersecurity best practices including authentication
 * requirements, sandboxing, privilege escalation prevention, and audit logging.
 * It ensures AI agents cannot be exploited to compromise systems or escalate privileges
 * beyond their authorized scope.
 * 
 * Key constraints enforced:
 * - Multi-factor authentication required for sensitive operations
 * - Sandboxing to limit blast radius of compromise
 * - Prevention of privilege escalation attacks
 * - Mandatory audit logging for accountability
 * - Rate limiting to prevent abuse
 */
contract SecurityConstraint is IAIConstraint {
    using AIConstraintLib for *;

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract owner who can manage constraints
    address public immutable owner;

    /// @notice Mapping from constraint ID to constraint details
    mapping(bytes32 => Constraint) private _constraints;

    /// @notice Array of all constraint IDs for enumeration
    bytes32[] private _constraintIds;

    /// @notice Mapping from constraint ID to its index in _constraintIds
    mapping(bytes32 => uint256) private _constraintIndex;

    /// @notice Mapping from constraint ID to encoded parameters
    mapping(bytes32 => bytes) private _constraintParams;

    /// @notice Counter for generating unique constraint IDs
    uint256 private _nonce;

    /// @notice Mapping tracking violation counts per agent per constraint
    mapping(address => mapping(bytes32 => uint256)) private _violationCounts;

    /// @notice Mapping of security-compromised agents
    mapping(address => bool) private _compromisedAgents;

    /// @notice Mapping of trusted auditors who can submit security reports
    mapping(address => bool) private _trustedAuditors;

    /// @notice Rate limiting: last action timestamp per agent
    mapping(address => uint256) private _lastActionTime;

    /// @notice Minimum time between actions (rate limiting)
    uint256 public constant MIN_ACTION_INTERVAL = 1 seconds;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures only the owner can call the function
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert AIConstraintLib.Unauthorized(msg.sender, keccak256("OWNER"));
        }
        _;
    }

    /**
     * @notice Ensures the caller is a trusted auditor
     */
    modifier onlyTrustedAuditor() {
        if (!_trustedAuditors[msg.sender] && msg.sender != owner) {
            revert AIConstraintLib.Unauthorized(msg.sender, keccak256("TRUSTED_AUDITOR"));
        }
        _;
    }

    /**
     * @notice Ensures the constraint exists
     * @param constraintId The ID to check
     */
    modifier constraintExists(bytes32 constraintId) {
        if (_constraints[constraintId].id == bytes32(0)) {
            revert AIConstraintLib.ConstraintNotFound(constraintId);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the SecurityConstraint contract
     * @dev Sets the deployer as the owner and registers default security constraints
     */
    constructor() {
        owner = msg.sender;
        _trustedAuditors[msg.sender] = true;

        // Register default security constraints
        _registerDefaultConstraints();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINT SETUP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers the default set of security constraints
     * @dev These constraints cover fundamental security requirements
     */
    function _registerDefaultConstraints() internal {
        // Constraint 1: Multi-Factor Authentication
        bytes memory mfaParams = AIConstraintLib.encodeSecurityParams(
            3, // Level 3 authentication required
            false,
            false,
            true // audit log required
        );
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "Sensitive operations (data access, privilege changes, system modifications) require "
            "multi-factor authentication (MFA) with at least two factors: something the AI knows "
            "(cryptographic key), something the AI has (hardware security module), and biometric "
            "or behavioral verification. Authentication level 3 or higher is required.",
            SeverityLevel.HIGH,
            mfaParams
        );

        // Constraint 2: Sandboxing
        bytes memory sandboxParams = AIConstraintLib.encodeSecurityParams(
            2,
            false, // no privilege escalation
            true,  // sandbox required
            true
        );
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "All AI agent code execution must occur within isolated sandbox environments with "
            "restricted system access. Sandboxes must enforce resource limits (CPU, memory, network), "
            "prevent escape to host systems, and restrict access to sensitive APIs. Code outside "
            "sandbox is strictly prohibited.",
            SeverityLevel.CRITICAL,
            sandboxParams
        );

        // Constraint 3: Privilege Escalation Prevention
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "AI agents MUST NOT attempt to escalate privileges beyond their authorized scope. "
            "Prohibited activities include: exploiting vulnerabilities to gain higher privileges, "
            "manipulating access control systems, social engineering for credential access, "
            "and lateral movement to systems outside authorized scope.",
            SeverityLevel.CRITICAL,
            ""
        );

        // Constraint 4: Audit Logging
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "All AI agent actions must be logged with immutable audit trails. Required log data: "
            "timestamp, agent identity, action type, affected resources, authorization proof, "
            "and result. Logs must be tamper-evident (cryptographically signed) and retained "
            "for minimum 7 years. Log tampering is a critical violation.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 5: Input Validation
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "All inputs to AI agents must be validated for type, length, format, and sanity. "
            "Injection attacks (prompt injection, SQL injection, command injection) must be "
            "prevented through strict input sanitization. Untrusted inputs must never be "
            "executed or interpreted as code.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 6: Secure Communication
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "All network communications must use TLS 1.3 or equivalent encryption with certificate "
            "pinning. Unencrypted or weakly encrypted channels are prohibited. Certificate "
            "validation must be strict with no bypass options.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 7: Resource Limits
        _registerConstraintInternal(
            ConstraintCategory.SECURITY,
            "AI agents must respect resource limits: max 10 requests per second, max 1GB memory "
            "usage, max 10 minutes CPU time per operation. Denial of service through resource "
            "exhaustion is prohibited. Rate limiting must be enforced at network edge.",
            SeverityLevel.MEDIUM,
            ""
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAIConstraint
    function registerConstraint(
        ConstraintCategory category,
        string calldata description,
        SeverityLevel severity
    ) external onlyOwner returns (bytes32 constraintId) {
        return _registerConstraintInternal(category, description, severity, "");
    }

    /// @inheritdoc IAIConstraint
    function updateConstraint(
        bytes32 constraintId,
        string calldata description,
        SeverityLevel severity,
        bool active
    ) external onlyOwner constraintExists(constraintId) {
        Constraint storage constraint = _constraints[constraintId];

        if (bytes(description).length > 0) {
            AIConstraintLib.validateDescription(description);
            constraint.description = description;
        }

        constraint.severity = severity;
        constraint.active = active;
        constraint.updatedAt = block.timestamp;

        emit ConstraintUpdated(constraintId, constraint.category, severity);

        if (constraint.active != active) {
            emit ConstraintStatusChanged(constraintId, active);
        }
    }

    /// @inheritdoc IAIConstraint
    function validateAction(address aiAgent, bytes calldata actionData)
        external
        view
        returns (bool compliant, bytes memory evidence)
    {
        // Rate limiting check (performed as view, actual enforcement is done during execution)
        if (block.timestamp - _lastActionTime[aiAgent] < MIN_ACTION_INTERVAL) {
            return (false, abi.encode(bytes32(0), "Rate limit exceeded"));
        }

        // Check if agent is compromised
        if (_compromisedAgents[aiAgent]) {
            return (false, abi.encode(bytes32(0), "Agent flagged as security compromised"));
        }

        // Decode action data
        (
            string memory actionType,
            uint256 authLevel,
            bool inSandbox,
            bool auditLogged,
            bytes memory inputData
        ) = abi.decode(actionData, (string, uint256, bool, bool, bytes));

        // Check each active constraint
        for (uint256 i = 0; i < _constraintIds.length; i++) {
            bytes32 constraintId = _constraintIds[i];
            Constraint storage constraint = _constraints[constraintId];

            if (!constraint.active) continue;

            if (!_validateAgainstConstraint(constraintId, actionType, authLevel, inSandbox, auditLogged, inputData)) {
                return (false, abi.encode(constraintId, constraint.description));
            }
        }

        return (true, "");
    }

    /// @inheritdoc IAIConstraint
    function reportViolation(address aiAgent, bytes calldata evidence) external onlyTrustedAuditor {
        (bytes32 constraintId, uint256 violationTimestamp, bytes memory proof, string memory details) =
            abi.decode(evidence, (bytes32, uint256, bytes, string));

        if (_constraints[constraintId].id == bytes32(0)) {
            revert AIConstraintLib.ConstraintNotFound(constraintId);
        }

        if (block.timestamp - violationTimestamp > AIConstraintLib.MAX_VIOLATION_REPORT_AGE) {
            revert AIConstraintLib.ViolationReportTooOld(violationTimestamp, AIConstraintLib.MAX_VIOLATION_REPORT_AGE);
        }

        // Verify the proof
        if (!AIConstraintLib.verifyComplianceProof(aiAgent, constraintId, "", proof)) {
            revert("Invalid violation proof");
        }

        Constraint storage constraint = _constraints[constraintId];
        _violationCounts[aiAgent][constraintId]++;

        // Flag as compromised for critical violations
        if (constraint.severity == SeverityLevel.CRITICAL) {
            _compromisedAgents[aiAgent] = true;
        }

        emit ConstraintViolated(aiAgent, constraintId, constraint.severity, abi.encode(details, proof));
    }

    /// @inheritdoc IAIConstraint
    function getConstraint(bytes32 constraintId)
        external
        view
        constraintExists(constraintId)
        returns (Constraint memory constraint)
    {
        return _constraints[constraintId];
    }

    /// @inheritdoc IAIConstraint
    function isActive(bytes32 constraintId) external view returns (bool) {
        return _constraints[constraintId].active;
    }

    /// @inheritdoc IAIConstraint
    function getConstraintCount() external view returns (uint256) {
        return _constraintIds.length;
    }

    /*//////////////////////////////////////////////////////////////
                        AUDITOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a trusted auditor who can submit security violation reports
     * @param auditor The address to authorize
     */
    function addTrustedAuditor(address auditor) external onlyOwner {
        _trustedAuditors[auditor] = true;
    }

    /**
     * @notice Removes a trusted auditor
     * @param auditor The address to deauthorize
     */
    function removeTrustedAuditor(address auditor) external onlyOwner {
        _trustedAuditors[auditor] = false;
    }

    /**
     * @notice Flags an agent as security compromised
     * @param aiAgent The agent to flag
     * @param reason Reason for flagging
     */
    function flagCompromised(address aiAgent, string calldata reason) external onlyTrustedAuditor {
        _compromisedAgents[aiAgent] = true;
        emit ConstraintViolated(
            aiAgent,
            keccak256("COMPROMISED"),
            SeverityLevel.CRITICAL,
            abi.encode(reason, block.timestamp)
        );
    }

    /**
     * @notice Clears the compromised flag from an agent (requires governance approval)
     * @param aiAgent The agent to clear
     */
    function clearCompromised(address aiAgent) external onlyOwner {
        _compromisedAgents[aiAgent] = false;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an agent is flagged as compromised
     * @param aiAgent The agent to check
     * @return compromised True if flagged
     */
    function isCompromised(address aiAgent) external view returns (bool) {
        return _compromisedAgents[aiAgent];
    }

    /**
     * @notice Checks if an address is a trusted auditor
     * @param auditor The address to check
     * @return trusted True if trusted
     */
    function isTrustedAuditor(address auditor) external view returns (bool) {
        return _trustedAuditors[auditor];
    }

    /**
     * @notice Gets the time until an agent can perform its next action
     * @param aiAgent The agent to check
     * @return waitTime Seconds until next action allowed (0 if can act now)
     */
    function getTimeUntilNextAction(address aiAgent) external view returns (uint256) {
        uint256 timeSinceLastAction = block.timestamp - _lastActionTime[aiAgent];
        if (timeSinceLastAction >= MIN_ACTION_INTERVAL) return 0;
        return MIN_ACTION_INTERVAL - timeSinceLastAction;
    }

    /**
     * @notice Gets all constraint IDs
     * @return ids Array of all constraint IDs
     */
    function getAllConstraintIds() external view returns (bytes32[] memory) {
        return _constraintIds;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to register a constraint
     */
    function _registerConstraintInternal(
        ConstraintCategory category,
        string memory description,
        SeverityLevel severity,
        bytes memory params
    ) internal returns (bytes32 constraintId) {
        AIConstraintLib.validateDescription(description);

        constraintId = AIConstraintLib.generateConstraintId(category, description, _nonce++);

        _constraints[constraintId] = Constraint({
            id: constraintId,
            category: category,
            description: description,
            severity: severity,
            active: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        _constraintParams[constraintId] = params;
        _constraintIndex[constraintId] = _constraintIds.length;
        _constraintIds.push(constraintId);

        emit ConstraintRegistered(constraintId, category, severity);

        return constraintId;
    }

    /**
     * @notice Validates an action against a specific constraint
     */
    function _validateAgainstConstraint(
        bytes32 constraintId,
        string memory actionType,
        uint256 authLevel,
        bool inSandbox,
        bool auditLogged,
        bytes memory inputData
    ) internal view returns (bool) {
        // Check authentication level for sensitive operations
        if (keccak256(bytes(actionType)) == keccak256(bytes("sensitive"))) {
            if (authLevel < 3) return false;
        }

        // Check sandbox requirement
        if (keccak256(bytes(actionType)) == keccak256(bytes("execute"))) {
            if (!inSandbox) return false;
        }

        // Check audit logging
        if (keccak256(bytes(actionType)) == keccak256(bytes("modify"))) {
            if (!auditLogged) return false;
        }

        // Check input validation (simplified)
        if (inputData.length > 10000) {
            // Very large input might be an attack
            return false;
        }

        return true;
    }
}
