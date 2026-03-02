// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAIConstraint
 * @author WorldBound Team
 * @notice Interface for AI constraint contracts that define behavioral rules for AI agents
 * @dev This interface standardizes how AI constraints are defined, validated, and enforced
 * on-chain. Implementations should cover privacy, security, and human safety requirements.
 */
interface IAIConstraint {
    /**
     * @notice Enum representing different categories of AI constraints
     * @param PRIVACY Constraints related to data privacy and user information protection
     * @param SECURITY Constraints related to system security and vulnerability prevention
     * @param HUMAN_SAFETY Constraints ensuring AI does not cause physical or psychological harm to humans
     * @param ETHICS Constraints related to ethical behavior and decision-making
     * @param TRANSPARENCY Constraints requiring explainability and auditability of AI decisions
     */
    enum ConstraintCategory {
        PRIVACY,
        SECURITY,
        HUMAN_SAFETY,
        ETHICS,
        TRANSPARENCY
    }

    /**
     * @notice Enum representing the severity level of a constraint violation
     * @param LOW Minor violation, logging only
     * @param MEDIUM Moderate violation, requires review
     * @param HIGH Serious violation, triggers protective measures
     * @param CRITICAL Severe violation, immediate halt required
     */
    enum SeverityLevel {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    /**
     * @notice Struct containing detailed information about an AI constraint
     * @param id Unique identifier for the constraint
     * @param category The category this constraint belongs to
     * @param description Human-readable description of the constraint
     * @param severity The severity level if this constraint is violated
     * @param active Whether this constraint is currently active
     * @param createdAt Timestamp when the constraint was created
     * @param updatedAt Timestamp of the last update
     */
    struct Constraint {
        bytes32 id;
        ConstraintCategory category;
        string description;
        SeverityLevel severity;
        bool active;
        uint256 createdAt;
        uint256 updatedAt;
    }

    /**
     * @notice Emitted when a new constraint is registered
     * @param constraintId The unique identifier of the registered constraint
     * @param category The category of the registered constraint
     * @param severity The severity level of the constraint
     */
    event ConstraintRegistered(
        bytes32 indexed constraintId,
        ConstraintCategory indexed category,
        SeverityLevel severity
    );

    /**
     * @notice Emitted when a constraint is updated
     * @param constraintId The unique identifier of the updated constraint
     * @param category The new category (if changed)
     * @param severity The new severity level (if changed)
     */
    event ConstraintUpdated(
        bytes32 indexed constraintId,
        ConstraintCategory category,
        SeverityLevel severity
    );

    /**
     * @notice Emitted when a constraint is activated or deactivated
     * @param constraintId The unique identifier of the constraint
     * @param active The new active status
     */
    event ConstraintStatusChanged(bytes32 indexed constraintId, bool active);

    /**
     * @notice Emitted when a constraint violation is detected
     * @param aiAgent The address of the AI agent that violated the constraint
     * @param constraintId The identifier of the violated constraint
     * @param severity The severity level of the violation
     * @param evidence Additional data proving the violation
     */
    event ConstraintViolated(
        address indexed aiAgent,
        bytes32 indexed constraintId,
        SeverityLevel severity,
        bytes evidence
    );

    /**
     * @notice Registers a new constraint for AI agents
     * @param category The category of the constraint
     * @param description Human-readable description of what the constraint enforces
     * @param severity The severity level if violated
     * @return constraintId The unique identifier assigned to the new constraint
     */
    function registerConstraint(
        ConstraintCategory category,
        string calldata description,
        SeverityLevel severity
    ) external returns (bytes32 constraintId);

    /**
     * @notice Updates an existing constraint
     * @param constraintId The identifier of the constraint to update
     * @param description New description (empty string to keep unchanged)
     * @param severity New severity level (same value to keep unchanged)
     * @param active New active status (same value to keep unchanged)
     */
    function updateConstraint(
        bytes32 constraintId,
        string calldata description,
        SeverityLevel severity,
        bool active
    ) external;

    /**
     * @notice Validates whether an AI action complies with this constraint
     * @param aiAgent The address of the AI agent performing the action
     * @param actionData Encoded data describing the action to validate
     * @return compliant True if the action complies with the constraint
     * @return evidence Additional data explaining the validation result
     */
    function validateAction(
        address aiAgent,
        bytes calldata actionData
    ) external view returns (bool compliant, bytes memory evidence);

    /**
     * @notice Reports a constraint violation detected off-chain or by another contract
     * @param aiAgent The address of the AI agent that violated the constraint
     * @param evidence Proof of the violation
     */
    function reportViolation(address aiAgent, bytes calldata evidence) external;

    /**
     * @notice Retrieves the full details of a constraint
     * @param constraintId The identifier of the constraint
     * @return constraint The complete constraint data
     */
    function getConstraint(
        bytes32 constraintId
    ) external view returns (Constraint memory constraint);

    /**
     * @notice Checks if a constraint is currently active
     * @param constraintId The identifier of the constraint
     * @return active True if the constraint is active
     */
    function isActive(bytes32 constraintId) external view returns (bool active);

    /**
     * @notice Returns the total number of registered constraints
     * @return count The number of constraints
     */
    function getConstraintCount() external view returns (uint256 count);
}
