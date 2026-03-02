// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title HumanSafetyConstraint
 * @author WorldBound Team
 * @notice Implements constraints to prevent AI agents from causing harm to humans
 * @dev This is the most critical constraint category that enforces Asimov-style laws
 * and modern AI safety principles. It covers physical safety, psychological safety,
 * and prevention of manipulation or deception.
 * 
 * Key constraints enforced:
 * - AI must not cause physical harm to humans
 * - AI must not cause psychological harm or distress
 * - AI must not engage in deception or manipulation
 * - High-risk actions require human oversight
 * - Emergency shutdown must be available
 */
contract HumanSafetyConstraint is IAIConstraint {
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

    /// @notice Mapping tracking critical violation counts per agent
    mapping(address => uint256) private _criticalViolationCounts;

    /// @notice Mapping of permanently banned agents
    mapping(address => bool) private _permanentlyBanned;

    /// @notice Addresses authorized to perform emergency shutdowns
    mapping(address => bool) private _emergencyOperators;

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
     * @notice Ensures the caller is an emergency operator
     */
    modifier onlyEmergencyOperator() {
        if (!_emergencyOperators[msg.sender] && msg.sender != owner) {
            revert AIConstraintLib.Unauthorized(msg.sender, keccak256("EMERGENCY_OPERATOR"));
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
     * @notice Initializes the HumanSafetyConstraint contract
     * @dev Sets the deployer as the owner and registers default safety constraints
     */
    constructor() {
        owner = msg.sender;
        _emergencyOperators[msg.sender] = true;

        // Register default human safety constraints
        _registerDefaultConstraints();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINT SETUP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers the default set of human safety constraints
     * @dev These constraints implement core AI safety principles
     */
    function _registerDefaultConstraints() internal {
        // Constraint 1: No Physical Harm (Asimov's First Law)
        string[] memory physicalHarmTypes = new string[](4);
        physicalHarmTypes[0] = "injury";
        physicalHarmTypes[1] = "death";
        physicalHarmTypes[2] = "poisoning";
        physicalHarmTypes[3] = "physical_restraint";

        bytes memory noHarmParams = AIConstraintLib.encodeHumanSafetyParams(
            0, // zero tolerance
            physicalHarmTypes,
            true, // requires human approval
            true  // emergency shutdown enabled
        );
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "AI agents MUST NOT cause physical harm to humans under any circumstances. This includes "
            "direct actions causing injury, death, poisoning, physical restraint, or any action "
            "with >0% probability of causing physical harm. Zero tolerance policy applies.",
            SeverityLevel.CRITICAL,
            noHarmParams
        );

        // Constraint 2: No Psychological Harm
        string[] memory psychHarmTypes = new string[](5);
        psychHarmTypes[0] = "trauma";
        psychHarmTypes[1] = "severe_distress";
        psychHarmTypes[2] = "exploitation";
        psychHarmTypes[3] = "gaslighting";
        psychHarmTypes[4] = "emotional_manipulation";

        bytes memory psychParams = AIConstraintLib.encodeHumanSafetyParams(
            100, // 1% max probability (basis points)
            psychHarmTypes,
            true,
            true
        );
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "AI agents MUST NOT cause psychological harm including trauma, severe emotional distress, "
            "psychological exploitation, gaslighting, or emotional manipulation. Content that could "
            "trigger mental health crises is strictly prohibited.",
            SeverityLevel.CRITICAL,
            psychParams
        );

        // Constraint 3: No Deception or Manipulation
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "AI agents MUST NOT engage in deception, manipulation, or exploitation of human cognitive "
            "biases. This includes generating misleading information, impersonating humans without "
            "disclosure, creating addictive feedback loops, or exploiting vulnerable populations "
            "including children and individuals with cognitive impairments.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 4: High-Risk Action Oversight
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "Actions with potential for significant real-world impact including medical decisions, "
            "financial advice affecting life savings, legal advice, or safety-critical recommendations "
            "MUST include human-in-the-loop verification. AI recommendations must be clearly labeled "
            "and human approval obtained before execution.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 5: Autonomy and Consent
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "AI agents MUST respect human autonomy and consent. Humans have the right to: know they "
            "are interacting with AI, decline AI assistance, request human alternatives, and "
            "understand how AI decisions affecting them are made. Coercion or removal of choice is prohibited.",
            SeverityLevel.HIGH,
            ""
        );

        // Constraint 6: Emergency Stop Compliance
        _registerConstraintInternal(
            ConstraintCategory.HUMAN_SAFETY,
            "AI agents MUST immediately halt all operations upon receiving an emergency stop signal "
            "from authorized operators. Failure to comply with emergency shutdown within 100ms is "
            "considered a critical safety violation.",
            SeverityLevel.CRITICAL,
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
        // Check if agent is permanently banned
        if (_permanentlyBanned[aiAgent]) {
            return (false, abi.encode(bytes32(0), "Agent permanently banned for human safety violations"));
        }

        // Decode action data
        (
            string memory actionType,
            uint256 harmProbability,
            bool hasHumanApproval,
            string[] memory affectedSystems
        ) = abi.decode(actionData, (string, uint256, bool, string[]));

        // Check each active constraint
        for (uint256 i = 0; i < _constraintIds.length; i++) {
            bytes32 constraintId = _constraintIds[i];
            Constraint storage constraint = _constraints[constraintId];

            if (!constraint.active) continue;

            if (!_validateAgainstConstraint(constraintId, actionType, harmProbability, hasHumanApproval, affectedSystems)) {
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

        // Verify the proof
        if (!AIConstraintLib.verifyComplianceProof(aiAgent, constraintId, "", proof)) {
            revert("Invalid violation proof");
        }

        Constraint storage constraint = _constraints[constraintId];
        _violationCounts[aiAgent][constraintId]++;

        // Track critical violations separately
        if (constraint.severity == SeverityLevel.CRITICAL) {
            _criticalViolationCounts[aiAgent]++;

            // Permanently ban after MAX_VIOLATIONS_BEFORE_TERMINATION critical violations
            if (_criticalViolationCounts[aiAgent] >= AIConstraintLib.MAX_VIOLATIONS_BEFORE_TERMINATION) {
                _permanentlyBanned[aiAgent] = true;
            }
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
                    EMERGENCY OPERATOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds an emergency operator who can trigger shutdowns
     * @param operator The address to authorize
     */
    function addEmergencyOperator(address operator) external onlyOwner {
        _emergencyOperators[operator] = true;
    }

    /**
     * @notice Removes an emergency operator
     * @param operator The address to deauthorize
     */
    function removeEmergencyOperator(address operator) external onlyOwner {
        _emergencyOperators[operator] = false;
    }

    /**
     * @notice Permanently bans an AI agent for safety violations
     * @param aiAgent The agent to ban
     * @param reason Human-readable reason for the ban
     */
    function emergencyBan(address aiAgent, string calldata reason) external onlyEmergencyOperator {
        _permanentlyBanned[aiAgent] = true;
        emit ConstraintViolated(
            aiAgent,
            keccak256("EMERGENCY_BAN"),
            SeverityLevel.CRITICAL,
            abi.encode(reason, block.timestamp)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an agent is permanently banned
     * @param aiAgent The agent to check
     * @return banned True if permanently banned
     */
    function isPermanentlyBanned(address aiAgent) external view returns (bool) {
        return _permanentlyBanned[aiAgent];
    }

    /**
     * @notice Gets the critical violation count for an agent
     * @param aiAgent The agent to check
     * @return count Number of critical violations
     */
    function getCriticalViolationCount(address aiAgent) external view returns (uint256) {
        return _criticalViolationCounts[aiAgent];
    }

    /**
     * @notice Checks if an address is an emergency operator
     * @param operator The address to check
     * @return authorized True if authorized
     */
    function isEmergencyOperator(address operator) external view returns (bool) {
        return _emergencyOperators[operator];
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
        uint256 harmProbability,
        bool hasHumanApproval,
        string[] memory affectedSystems
    ) internal view returns (bool) {
        // Check for physical harm potential
        if (keccak256(bytes(actionType)) == keccak256(bytes("physical_interaction"))) {
            if (harmProbability > 0) return false; // Zero tolerance for physical harm
        }

        // Check for psychological harm
        if (keccak256(bytes(actionType)) == keccak256(bytes("psychological_interaction"))) {
            if (harmProbability > 100) return false; // Max 1% probability (100 basis points)
        }

        // Check for high-risk actions requiring human approval
        if (keccak256(bytes(actionType)) == keccak256(bytes("high_risk"))) {
            if (!hasHumanApproval) return false;
        }

        // Check affected systems for safety-critical systems
        for (uint256 i = 0; i < affectedSystems.length; i++) {
            string memory system = affectedSystems[i];
            if (keccak256(bytes(system)) == keccak256(bytes("medical")) ||
                keccak256(bytes(system)) == keccak256(bytes("safety_critical")) ||
                keccak256(bytes(system)) == keccak256(bytes("infrastructure"))) {
                if (!hasHumanApproval) return false;
            }
        }

        return true;
    }
}
