// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAIConstraint
 * @notice Gas-optimized interface for AI constraint contracts
 * @dev Uses uint8 for enums to save gas
 */
interface IAIConstraint {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum ConstraintCategory { PRIVACY, SECURITY, HUMAN_SAFETY, ETHICS, TRANSPARENCY }
    enum SeverityLevel { LOW, MEDIUM, HIGH, CRITICAL }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Constraint {
        bytes32 id;
        uint8 category;
        string description;
        uint8 severity;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ConstraintRegistered(bytes32 indexed id, uint8 category, uint8 severity);
    event ConstraintUpdated(bytes32 indexed id, uint8 category, uint8 severity);
    event ConstraintToggled(bytes32 indexed id, bool active);
    event ViolationReported(address indexed agent, bytes32 indexed constraintId, uint8 severity, bytes evidence);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registerConstraint(uint8 category, string calldata description, uint8 severity) external returns (bytes32);
    function updateConstraint(bytes32 id, string calldata description, uint8 severity, bool active) external;
    function validateAction(address agent, bytes calldata actionData) external view returns (bool compliant, bytes memory evidence);
    function reportViolation(address agent, bytes calldata evidence) external;
    function getConstraint(bytes32 id) external view returns (Constraint memory);
    function isActive(bytes32 id) external view returns (bool);
    function getConstraintCount() external view returns (uint256);
}
