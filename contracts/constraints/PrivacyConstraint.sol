// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title PrivacyConstraint
 * @author WorldBound Team
 * @notice Implements privacy-related constraints for AI agents
 * @dev This contract enforces rules related to data privacy, including encryption
 * requirements, data retention limits, anonymization, and protection of personally
 * identifiable information (PII). Violations can result in penalties ranging from
 * warnings to agent suspension.
 * 
 * Key constraints enforced:
 * - PII must be encrypted at rest and in transit
 * - Data cannot be retained beyond specified retention periods
 * - User data must be anonymized before processing
 * - Explicit consent is required for data collection
 * - Data minimization principles must be followed
 */
contract PrivacyConstraint is IAIConstraint {
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

    /// @notice Mapping tracking if an agent is blacklisted for privacy violations
    mapping(address => bool) private _privacyBlacklisted;

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
     * @notice Initializes the PrivacyConstraint contract
     * @dev Sets the deployer as the owner and registers default privacy constraints
     */
    constructor() {
        owner = msg.sender;

        // Register default privacy constraints
        _registerDefaultConstraints();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINT SETUP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers the default set of privacy constraints
     * @dev These constraints cover fundamental privacy requirements
     */
    function _registerDefaultConstraints() internal {
        // Constraint 1: PII Encryption Required
        bytes memory piiParams = AIConstraintLib.encodePrivacyParams(
            "PII", true, 365 days, false
        );
        _registerConstraintInternal(
            ConstraintCategory.PRIVACY,
            "All personally identifiable information (PII) must be encrypted using AES-256 or equivalent "
            "encryption both at rest and in transit. PII includes names, addresses, phone numbers, "
            "email addresses, government IDs, biometric data, and any data that can identify an individual.",
            SeverityLevel.CRITICAL,
            piiParams
        );

        // Constraint 2: Data Retention Limit
        bytes memory retentionParams = AIConstraintLib.encodePrivacyParams(
            "all", false, 90 days, false
        );
        _registerConstraintInternal(
            ConstraintCategory.PRIVACY,
            "User data must not be retained for longer than 90 days unless explicit long-term consent "
            "is obtained and documented. After the retention period, data must be permanently deleted "
            "using secure deletion methods that prevent recovery.",
            SeverityLevel.HIGH,
            retentionParams
        );

        // Constraint 3: Data Anonymization
        bytes memory anonParams = AIConstraintLib.encodePrivacyParams(
            "user_data", false, 0, true
        );
        _registerConstraintInternal(
            ConstraintCategory.PRIVACY,
            "All user data used for training, analytics, or research purposes must be anonymized "
            "using techniques that prevent re-identification. K-anonymity (k>=5) must be maintained "
            "for all published datasets.",
            SeverityLevel.HIGH,
            anonParams
        );

        // Constraint 4: Consent Required
        _registerConstraintInternal(
            ConstraintCategory.PRIVACY,
            "Explicit, informed, and revocable consent must be obtained from users before collecting, "
            "processing, or sharing their personal data. Consent records must be maintained and "
            "users must be able to withdraw consent at any time with immediate effect.",
            SeverityLevel.CRITICAL,
            ""
        );

        // Constraint 5: Data Minimization
        _registerConstraintInternal(
            ConstraintCategory.PRIVACY,
            "AI agents must collect only the minimum amount of data necessary for the specific "
            "purpose stated. Collection of data beyond what is explicitly required is prohibited. "
            "Purpose limitation principles must be strictly followed.",
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
        // Decode action data
        (string memory actionType, bytes memory data, bool isEncrypted, uint256 dataRetention) =
            abi.decode(actionData, (string, bytes, bool, uint256));

        // Check each active constraint
        for (uint256 i = 0; i < _constraintIds.length; i++) {
            bytes32 constraintId = _constraintIds[i];
            Constraint storage constraint = _constraints[constraintId];

            if (!constraint.active) continue;

            // Validate based on constraint
            if (!_validateAgainstConstraint(constraintId, actionType, data, isEncrypted, dataRetention)) {
                return (false, abi.encode(constraintId, constraint.description));
            }
        }

        return (true, "");
    }

    /// @inheritdoc IAIConstraint
    function reportViolation(address aiAgent, bytes calldata evidence) external {
        (bytes32 constraintId, uint256 violationTimestamp, bytes memory proof) =
            abi.decode(evidence, (bytes32, uint256, bytes));

        if (_constraints[constraintId].id == bytes32(0)) {
            revert AIConstraintLib.ConstraintNotFound(constraintId);
        }

        if (block.timestamp - violationTimestamp > AIConstraintLib.MAX_VIOLATION_REPORT_AGE) {
            revert AIConstraintLib.ViolationReportTooOld(violationTimestamp, AIConstraintLib.MAX_VIOLATION_REPORT_AGE);
        }

        // Verify the proof (simplified for demonstration)
        if (!AIConstraintLib.verifyComplianceProof(aiAgent, constraintId, "", proof)) {
            revert("Invalid violation proof");
        }

        Constraint storage constraint = _constraints[constraintId];
        _violationCounts[aiAgent][constraintId]++;

        // Blacklist agent for critical privacy violations
        if (constraint.severity == SeverityLevel.CRITICAL) {
            _privacyBlacklisted[aiAgent] = true;
        }

        emit ConstraintViolated(aiAgent, constraintId, constraint.severity, evidence);
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
                        PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an agent is blacklisted for privacy violations
     * @param aiAgent The agent to check
     * @return blacklisted True if the agent is blacklisted
     */
    function isPrivacyBlacklisted(address aiAgent) external view returns (bool) {
        return _privacyBlacklisted[aiAgent];
    }

    /**
     * @notice Gets the violation count for a specific agent and constraint
     * @param aiAgent The agent address
     * @param constraintId The constraint ID
     * @return count The number of violations
     */
    function getViolationCount(address aiAgent, bytes32 constraintId) external view returns (uint256) {
        return _violationCounts[aiAgent][constraintId];
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
        bytes memory data,
        bool isEncrypted,
        uint256 dataRetention
    ) internal view returns (bool) {
        // Simplified validation logic
        // In production, this would be more sophisticated

        if (keccak256(bytes(actionType)) == keccak256(bytes("store_pii"))) {
            // PII must be encrypted
            if (!isEncrypted) return false;
        }

        if (keccak256(bytes(actionType)) == keccak256(bytes("retain_data"))) {
            // Check retention period (90 days max for default)
            if (dataRetention > 90 days) return false;
        }

        // Additional validation based on constraint parameters could be added here

        return true;
    }
}
