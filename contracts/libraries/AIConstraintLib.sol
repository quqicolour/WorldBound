// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";

/**
 * @title AIConstraintLib
 * @author WorldBound Team
 * @notice Library containing utilities, constants, and validation logic for AI constraints
 * @dev This library provides shared functionality for constraint validation, severity
 * assessment, and cryptographic operations used throughout the AI constraint system.
 */
library AIConstraintLib {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum length for constraint descriptions to prevent gas abuse
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;

    /// @notice Maximum number of constraints an AI agent can be subject to
    uint256 public constant MAX_CONSTRAINTS_PER_AGENT = 100;

    /// @notice Maximum age (in seconds) for violation reports to be considered valid
    uint256 public constant MAX_VIOLATION_REPORT_AGE = 7 days;

    /// @notice Cooldown period (in seconds) between status changes for an agent
    uint256 public constant STATUS_CHANGE_COOLDOWN = 1 hours;

    /// @notice Maximum violations before automatic suspension (HIGH or CRITICAL only)
    uint256 public constant MAX_VIOLATIONS_BEFORE_SUSPENSION = 3;

    /// @notice Maximum violations before automatic termination (CRITICAL only)
    uint256 public constant MAX_VIOLATIONS_BEFORE_TERMINATION = 2;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when a constraint ID does not exist in the registry
     * @param constraintId The ID that was not found
     */
    error ConstraintNotFound(bytes32 constraintId);

    /**
     * @notice Thrown when an AI agent address is not registered
     * @param agent The address that was not found
     */
    error AgentNotRegistered(address agent);

    /**
     * @notice Thrown when a constraint description exceeds maximum length
     * @param length The provided length
     * @param maxLength The maximum allowed length
     */
    error DescriptionTooLong(uint256 length, uint256 maxLength);

    /**
     * @notice Thrown when attempting to add too many constraints to an agent
     * @param current The current number of constraints
     * @param maximum The maximum allowed constraints
     */
    error TooManyConstraints(uint256 current, uint256 maximum);

    /**
     * @notice Thrown when an action fails constraint validation
     * @param constraintId The ID of the violated constraint
     * @param reason Human-readable explanation
     */
    error ConstraintViolation(bytes32 constraintId, string reason);

    /**
     * @notice Thrown when a caller is not authorized for an operation
     * @param caller The address that attempted the operation
     * @param requiredRole The role that was required
     */
    error Unauthorized(address caller, bytes32 requiredRole);

    /**
     * @notice Thrown when an operation is attempted while agent is in wrong status
     * @param currentStatus The agent's current status
     * @param requiredStatus The status required for the operation
     */
    error InvalidStatus(uint8 currentStatus, uint8 requiredStatus);

    /**
     * @notice Thrown when a violation report is too old to be processed
     * @param reportTimestamp When the violation occurred
     * @param maxAge The maximum allowed age
     */
    error ViolationReportTooOld(uint256 reportTimestamp, uint256 maxAge);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a constraint check is performed
     * @param agent The AI agent being checked
     * @param constraintId The constraint being validated
     * @param passed Whether the check passed
     */
    event ConstraintCheck(address indexed agent, bytes32 indexed constraintId, bool passed);

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generates a unique constraint ID from category and description hash
     * @param category The constraint category
     * @param description The constraint description
     * @param timestamp Creation timestamp for uniqueness
     * @return id The generated constraint ID
     */
    function generateConstraintId(IAIConstraint.ConstraintCategory category, string memory description, uint256 timestamp)
        internal
        pure
        returns (bytes32 id)
    {
        return keccak256(abi.encodePacked(category, description, timestamp));
    }

    /**
     * @notice Generates a unique action ID from agent address and action data
     * @param agent The AI agent address
     * @param actionData The encoded action data
     * @param nonce A unique nonce to prevent collisions
     * @return id The generated action ID
     */
    function generateActionId(address agent, bytes memory actionData, uint256 nonce)
        internal
        pure
        returns (bytes32 id)
    {
        return keccak256(abi.encodePacked(agent, actionData, nonce));
    }

    /**
     * @notice Validates that a description length is within acceptable bounds
     * @param description The description to validate
     */
    function validateDescription(string memory description) internal pure {
        uint256 length = bytes(description).length;
        if (length > MAX_DESCRIPTION_LENGTH) {
            revert DescriptionTooLong(length, MAX_DESCRIPTION_LENGTH);
        }
    }

    /**
     * @notice Determines if a severity level requires immediate action
     * @param severity The severity level to check
     * @return requiresAction True if immediate action is required
     */
    function requiresImmediateAction(IAIConstraint.SeverityLevel severity) internal pure returns (bool) {
        return severity == IAIConstraint.SeverityLevel.HIGH || severity == IAIConstraint.SeverityLevel.CRITICAL;
    }

    /**
     * @notice Calculates the weighted violation score based on severity
     * @param severity The severity of the violation
     * @return score The weighted score (LOW=1, MEDIUM=2, HIGH=5, CRITICAL=10)
     */
    function getViolationScore(IAIConstraint.SeverityLevel severity) internal pure returns (uint256 score) {
        if (severity == IAIConstraint.SeverityLevel.LOW) return 1;
        if (severity == IAIConstraint.SeverityLevel.MEDIUM) return 2;
        if (severity == IAIConstraint.SeverityLevel.HIGH) return 5;
        if (severity == IAIConstraint.SeverityLevel.CRITICAL) return 10;
        return 0;
    }

    /**
     * @notice Checks if an agent should be suspended based on violation history
     * @param highSeverityCount Number of HIGH severity violations
     * @param criticalSeverityCount Number of CRITICAL severity violations
     * @return shouldSuspend True if suspension is warranted
     */
    function shouldSuspend(uint256 highSeverityCount, uint256 criticalSeverityCount)
        internal
        pure
        returns (bool)
    {
        return highSeverityCount >= MAX_VIOLATIONS_BEFORE_SUSPENSION
            || criticalSeverityCount >= MAX_VIOLATIONS_BEFORE_SUSPENSION;
    }

    /**
     * @notice Checks if an agent should be terminated based on violation history
     * @param criticalSeverityCount Number of CRITICAL severity violations
     * @return shouldTerminate True if termination is warranted
     */
    function shouldTerminate(uint256 criticalSeverityCount) internal pure returns (bool) {
        return criticalSeverityCount >= MAX_VIOLATIONS_BEFORE_TERMINATION;
    }

    /**
     * @notice Encodes privacy constraint parameters
     * @param dataType Type of data being protected (e.g., "PII", "financial", "health")
     * @param encryptionRequired Whether encryption is mandatory
     * @param retentionDays Maximum days data can be retained
     * @param anonymizationRequired Whether data must be anonymized
     * @return encoded The encoded parameters
     */
    function encodePrivacyParams(
        string memory dataType,
        bool encryptionRequired,
        uint256 retentionDays,
        bool anonymizationRequired
    ) internal pure returns (bytes memory encoded) {
        return abi.encode(dataType, encryptionRequired, retentionDays, anonymizationRequired);
    }

    /**
     * @notice Encodes human safety constraint parameters
     * @param maxHarmProbability Maximum acceptable probability of harm (0-10000, basis points)
     * @param harmTypes Array of harm types prevented (e.g., "physical", "psychological")
     * @param requiresHumanApproval Whether human approval is required for critical actions
     * @param emergencyShutdownEnabled Whether emergency shutdown is enabled
     * @return encoded The encoded parameters
     */
    function encodeHumanSafetyParams(
        uint256 maxHarmProbability,
        string[] memory harmTypes,
        bool requiresHumanApproval,
        bool emergencyShutdownEnabled
    ) internal pure returns (bytes memory encoded) {
        return abi.encode(maxHarmProbability, harmTypes, requiresHumanApproval, emergencyShutdownEnabled);
    }

    /**
     * @notice Encodes security constraint parameters
     * @param minAuthenticationLevel Minimum required authentication level (0-5)
     * @param maxPrivilegeEscalationAllowed Whether privilege escalation is permitted
     * @param sandboxRequired Whether sandboxing is mandatory
     * @param auditLogRequired Whether audit logging is required
     * @return encoded The encoded parameters
     */
    function encodeSecurityParams(
        uint256 minAuthenticationLevel,
        bool maxPrivilegeEscalationAllowed,
        bool sandboxRequired,
        bool auditLogRequired
    ) internal pure returns (bytes memory encoded) {
        return abi.encode(minAuthenticationLevel, maxPrivilegeEscalationAllowed, sandboxRequired, auditLogRequired);
    }

    /**
     * @notice Verifies a cryptographic proof of constraint compliance
     * @param agent The AI agent address
     * @param constraintId The constraint being verified
     * @param actionData The action data
     * @param proof The cryptographic proof (e.g., zero-knowledge proof)
     * @return valid True if the proof is valid
     */
    function verifyComplianceProof(
        address agent,
        bytes32 constraintId,
        bytes memory actionData,
        bytes memory proof
    ) internal pure returns (bool valid) {
        // In production, this would verify ZK proofs or signatures
        // For now, we verify that the proof hashes correctly
        bytes32 expectedHash = keccak256(abi.encodePacked(agent, constraintId, actionData));
        return keccak256(proof) == expectedHash;
    }
}
