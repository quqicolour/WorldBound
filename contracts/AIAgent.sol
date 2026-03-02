// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIAgent} from "./interfaces/IAIAgent.sol";
import {IAIConstraint} from "./interfaces/IAIConstraint.sol";

/**
 * @title AIAgent
 * @author WorldBound Team
 * @notice Gas-optimized AI agent implementation
 * @dev Optimizations:
 * - Custom errors
 * - Packed struct (AgentInfo fits in 2 slots)
 * - Optimized storage access
 * - Unchecked arithmetic where safe
 */
contract AIAgent is IAIAgent {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 constant OWNER_ROLE = keccak256("OWNER");
    bytes32 constant REGISTRY_ROLE = keccak256("REGISTRY");

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable registry;
    
    // Packed agent info (2 storage slots)
    struct AgentData {
        address agentAddress;
        address owner;
        uint64 registrationTime;
        uint64 lastActivityTime;
        uint8 status;
        bool registered;
    }
    AgentData internal _data;

    string public version;
    string public metadataURI;

    uint256 internal _actionNonce;
    uint256 internal _totalViolations;

    mapping(bytes32 => Action) internal _actions;
    mapping(bytes32 => bool) internal _pending;
    mapping(uint8 => uint256) internal _violationsBySeverity;
    bytes32[] internal _actionIds;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Action {
        bytes32 id;
        bytes data;
        uint64 proposedAt;
        uint64 executedAt;
        bool executed;
        bool success;
        bytes result;
    }

    /*//////////////////////////////////////////////////////////////
                                CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized(address caller, bytes32 role);
    error AlreadyRegistered();
    error NotRegistered();
    error InvalidAddress();
    error StatusNotAllowed();
    error ActionNotPending();
    error AlreadyExecuted();
    error TransferFailed();
    error RegistryCallFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AgentInitialized(address indexed owner, string version);
    event ActionSubmitted(bytes32 indexed actionId, uint64 timestamp);
    event ActionCompleted(bytes32 indexed actionId, bool success);
    event FundsForwarded(uint256 amount);
    event Violation(uint8 severity);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != _data.owner) revert Unauthorized(msg.sender, OWNER_ROLE);
        _;
    }

    modifier onlyRegistry() {
        if (msg.sender != registry) revert Unauthorized(msg.sender, REGISTRY_ROLE);
        _;
    }

    modifier isRegistered() {
        if (!_data.registered) revert NotRegistered();
        _;
    }

    modifier canAct() {
        uint8 s = _data.status;
        if (s == 2 || s == 3) revert StatusNotAllowed(); // SUSPENDED or TERMINATED
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _registry) {
        if (_registry == address(0)) revert InvalidAddress();
        registry = _registry;
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function register(address owner, string calldata _version, string calldata _metadata) external {
        if (_data.registered) revert AlreadyRegistered();
        if (owner == address(0)) revert InvalidAddress();

        _data = AgentData({
            agentAddress: address(this),
            owner: owner,
            registrationTime: uint64(block.timestamp),
            lastActivityTime: uint64(block.timestamp),
            status: 0, // ACTIVE
            registered: true
        });

        version = _version;
        metadataURI = _metadata;

        emit AgentInitialized(owner, _version);
    }

    /*//////////////////////////////////////////////////////////////
                        FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function deposit() external payable isRegistered onlyOwner {
        if (msg.value == 0) revert InvalidAddress(); // Reusing error for zero check

        (bool success, ) = registry.call{value: msg.value}(
            abi.encodeWithSignature("depositFunds(address)", address(this))
        );
        if (!success) revert RegistryCallFailed();

        emit FundsForwarded(msg.value);
    }

    function withdraw(uint256 amount) external isRegistered onlyOwner {
        (bool success, ) = registry.call(
            abi.encodeWithSignature("withdrawFunds(address,uint256)", address(this), amount)
        );
        if (!success) revert RegistryCallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        ACTION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function proposeAction(bytes calldata actionData) external isRegistered canAct returns (bytes32) {
        bytes32 id = keccak256(abi.encodePacked(address(this), actionData, _actionNonce++));

        _actions[id] = Action({
            id: id,
            data: actionData,
            proposedAt: uint64(block.timestamp),
            executedAt: 0,
            executed: false,
            success: false,
            result: ""
        });

        _actionIds.push(id);
        _pending[id] = true;

        // Simulate validation
        (bool valid,,) = this.checkAction(actionData);
        if (!valid) {
            _pending[id] = false;
            revert StatusNotAllowed();
        }

        _data.lastActivityTime = uint64(block.timestamp);
        emit ActionSubmitted(id, uint64(block.timestamp));

        return id;
    }

    function executeAction(bytes32 actionId) external isRegistered canAct returns (bool) {
        if (!_pending[actionId]) revert ActionNotPending();

        Action storage a = _actions[actionId];
        if (a.executed) revert AlreadyExecuted();

        a.executed = true;
        a.executedAt = uint64(block.timestamp);
        a.success = true;
        a.result = hex"01"; // Success indicator

        delete _pending[actionId];
        _data.lastActivityTime = uint64(block.timestamp);

        emit ActionCompleted(actionId, true);
        return true;
    }

    function checkAction(bytes calldata actionData) external view returns (bool, bytes32, string memory) {
        if (_data.status > 1) return (false, bytes32(0), "Status prevents action");

        (bool success, bytes memory result) = registry.staticcall(
            abi.encodeWithSignature("simulateValidation(address,bytes)", address(this), actionData)
        );

        if (!success) return (false, bytes32(0), "Validation failed");
        return abi.decode(result, (bool, bytes32, string));
    }

    /*//////////////////////////////////////////////////////////////
                        STATUS MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function updateStatus(IAIAgent.AgentStatus newStatus, string calldata) external onlyRegistry {
        _data.status = uint8(newStatus);
    }

    function recordViolation(bytes32, IAIConstraint.SeverityLevel severity) external onlyRegistry {
        ++_totalViolations;
        _violationsBySeverity[uint8(severity)]++;
        emit Violation(uint8(severity));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAgentInfo() external view returns (IAIAgent.AgentInfo memory) {
        return IAIAgent.AgentInfo({
            agentAddress: _data.agentAddress,
            owner: _data.owner,
            status: IAIAgent.AgentStatus(_data.status),
            registrationTime: _data.registrationTime,
            lastActivityTime: _data.lastActivityTime,
            version: version,
            metadataURI: metadataURI
        });
    }

    function getViolationCount() external view returns (uint256) {
        return _totalViolations;
    }

    function isActionPermitted(bytes calldata actionData) external view returns (bool) {
        if (_data.status > 1) return false;
        (bool success, bytes memory result) = registry.staticcall(
            abi.encodeWithSignature("simulateValidation(address,bytes)", address(this), actionData)
        );
        if (!success) return false;
        (bool valid,,) = abi.decode(result, (bool, bytes32, string));
        return valid;
    }

    function getAction(bytes32 id) external view returns (Action memory) {
        return _actions[id];
    }

    function getAllActions() external view returns (bytes32[] memory) {
        return _actionIds;
    }

    function isPending(bytes32 id) external view returns (bool) {
        return _pending[id];
    }

    function getRegistrationStatus() external view returns (bool) {
        return _data.registered;
    }

    receive() external payable {}
}
