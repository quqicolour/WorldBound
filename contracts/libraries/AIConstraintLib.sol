// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";

/**
 * @title AIConstraintLib
 * @notice Gas-optimized library for AI constraints
 * @dev Uses constants and pure functions to minimize gas
 */
library AIConstraintLib {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MAX_DESC_LEN = 1000;
    uint256 internal constant MAX_CONSTRAINTS = 100;
    uint32 internal constant MAX_REPORT_AGE = 7 days;
    uint32 internal constant STATUS_COOLDOWN = 1 hours;
    uint8 internal constant SUSPENSION_THRESHOLD = 3;
    uint8 internal constant TERMINATION_THRESHOLD = 2;

    /*//////////////////////////////////////////////////////////////
                                CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error ConstraintNotFound(bytes32 id);
    error AgentNotFound(address agent);
    error DescriptionTooLong(uint256 len, uint256 max);
    error TooManyConstraints(uint256 count, uint256 max);
    error Unauthorized(address caller, bytes32 role);
    error InvalidStatus(uint8 current, uint8 required);
    error ReportTooOld(uint256 timestamp, uint32 maxAge);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function generateId(uint8 category, string memory desc, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(category, desc, nonce));
    }

    function generateActionId(address agent, bytes memory data, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(agent, data, nonce));
    }

    function checkDescription(string memory desc) internal pure {
        uint256 len = bytes(desc).length;
        if (len > MAX_DESC_LEN) revert DescriptionTooLong(len, MAX_DESC_LEN);
    }

    function requiresAction(uint8 severity) internal pure returns (bool) {
        return severity >= 2; // HIGH or CRITICAL
    }

    function getScore(uint8 severity) internal pure returns (uint256) {
        // LOW=1, MEDIUM=2, HIGH=5, CRITICAL=10
        assembly {
            switch severity
            case 0 { severity := 1 }
            case 1 { severity := 2 }
            case 2 { severity := 5 }
            case 3 { severity := 10 }
            default { severity := 0 }
        }
        return severity;
    }

    function shouldSuspend(uint256 highCount, uint256 criticalCount) internal pure returns (bool) {
        return highCount >= SUSPENSION_THRESHOLD || criticalCount >= SUSPENSION_THRESHOLD;
    }

    function shouldTerminate(uint256 criticalCount) internal pure returns (bool) {
        return criticalCount >= TERMINATION_THRESHOLD;
    }

    function encodePrivacy(
        string memory dataType,
        bool encryption,
        uint256 retention,
        bool anon
    ) internal pure returns (bytes memory) {
        return abi.encode(dataType, encryption, retention, anon);
    }

    function encodeSafety(
        uint256 harmProb,
        string[] memory harmTypes,
        bool humanApproval,
        bool emergency
    ) internal pure returns (bytes memory) {
        return abi.encode(harmProb, harmTypes, humanApproval, emergency);
    }

    function encodeSecurity(
        uint256 authLevel,
        bool privEsc,
        bool sandbox,
        bool audit
    ) internal pure returns (bytes memory) {
        return abi.encode(authLevel, privEsc, sandbox, audit);
    }

    function verifyProof(
        address agent,
        bytes32 constraintId,
        bytes memory actionData,
        bytes memory proof
    ) internal pure returns (bool) {
        bytes32 expected = keccak256(abi.encodePacked(agent, constraintId, actionData));
        return keccak256(proof) == expected;
    }
}
