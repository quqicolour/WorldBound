// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {IAIAgent} from "../interfaces/IAIAgent.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title AIConstraintGovernance
 * @author WorldBound Team
 * @notice Governance contract for managing the AI constraint system
 * @dev This contract implements decentralized governance for the AI constraint ecosystem.
 * It allows stakeholders to propose and vote on:
 * - Adding or modifying constraints
 * - Updating agent statuses
 * - Upgrading constraint contracts
 * - Emergency actions for critical safety issues
 * 
 * Governance follows a proposal-based system with timelock and quorum requirements.
 */
contract AIConstraintGovernance {
    using AIConstraintLib for *;

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry contract address
    address public immutable registry;

    /// @notice Governance token for voting (can be replaced with any token)
    address public governanceToken;

    /// @notice Minimum tokens required to create a proposal
    uint256 public proposalThreshold;

    /// @notice Duration of voting period in blocks
    uint256 public votingPeriod;

    /// @notice Required quorum for proposal execution (basis points, e.g., 4000 = 40%)
    uint256 public quorumVotes;

    /// @notice Timelock delay for executed proposals (in seconds)
    uint256 public timelockDelay;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Mapping from proposal ID to proposal details
    mapping(uint256 => Proposal) public proposals;

    /// @notice Mapping from proposal ID to voter receipts
    mapping(uint256 => mapping(address => Receipt)) public receipts;

    /// @notice Mapping of authorized proposers (can bypass token threshold)
    mapping(address => bool) public authorizedProposers;

    /// @notice Contract owner
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice States a proposal can be in
     * @param Pending Proposal created but voting not started
     * @param Active Voting is active
     * @param Canceled Proposal was canceled
     * @param Defeated Proposal failed to pass
     * @param Succeeded Proposal passed voting
     * @param Queued Proposal queued for execution (timelock)
     * @param Expired Proposal expired in queue
     * @param Executed Proposal was executed
     */
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Core proposal information
     * @param id Unique identifier
     * @param proposer Address that created the proposal
     * @param targets Contract addresses to call
     * @param values ETH values to send
     * @param signatures Function signatures
     * @param calldatas Encoded function calls
     * @param description Human-readable description
     * @param forVotes Votes in favor
     * @param againstVotes Votes against
     * @param startBlock Block when voting starts
     * @param endBlock Block when voting ends
     * @param eta Timestamp when proposal can be executed (after timelock)
     * @param canceled Whether proposal was canceled
     * @param executed Whether proposal was executed
     */
    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startBlock;
        uint256 endBlock;
        uint256 eta;
        bool canceled;
        bool executed;
    }

    /**
     * @notice Vote receipt for a voter
     * @param hasVoted Whether the voter has voted
     * @param support 0=against, 1=for
     * @param votes Number of votes cast
     */
    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint96 votes;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a proposal is created
     * @param id Proposal ID
     * @param proposer Address creating the proposal
     * @param targets Target contracts
     * @param values ETH values
     * @param signatures Function signatures
     * @param calldatas Encoded calls
     * @param startBlock When voting starts
     * @param endBlock When voting ends
     * @param description Proposal description
     */
    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /**
     * @notice Emitted when a vote is cast
     * @param voter The voter
     * @param proposalId The proposal
     * @param support 0=against, 1=for
     * @param votes Number of votes
     * @param reason Reason for vote
     */
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    /**
     * @notice Emitted when a proposal is canceled
     * @param id The proposal ID
     * @param canceler Address that canceled
     */
    event ProposalCanceled(uint256 indexed id, address canceler);

    /**
     * @notice Emitted when a proposal is queued for execution
     * @param id The proposal ID
     * @param eta When it can be executed
     */
    event ProposalQueued(uint256 indexed id, uint256 eta);

    /**
     * @notice Emitted when a proposal is executed
     * @param id The proposal ID
     * @param executor Address that executed
     */
    event ProposalExecuted(uint256 indexed id, address executor);

    /**
     * @notice Emitted when governance parameters are updated
     * @param parameter Name of parameter
     * @param oldValue Previous value
     * @param newValue New value
     */
    event ParameterUpdated(string parameter, uint256 oldValue, uint256 newValue);

    /**
     * @notice Emitted when emergency action is taken
     * @param target Address affected
     * @param action Description of action
     * @param executor Address that executed
     */
    event EmergencyAction(address indexed target, string action, address executor);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures only the owner can call
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Ensures only authorized proposers can call
     */
    modifier onlyAuthorizedProposer() {
        require(
            authorizedProposers[msg.sender] || msg.sender == owner,
            "Not authorized proposer"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the governance contract
     * @param registryAddress The AI constraint registry address
     * @param token The governance token address
     * @param threshold Minimum tokens to propose
     * @param period Voting period in blocks
     * @param quorum Required quorum in basis points
     * @param delay Timelock delay in seconds
     */
    constructor(
        address registryAddress,
        address token,
        uint256 threshold,
        uint256 period,
        uint256 quorum,
        uint256 delay
    ) {
        require(registryAddress != address(0), "Invalid registry");
        require(token != address(0), "Invalid token");

        owner = msg.sender;
        registry = registryAddress;
        governanceToken = token;
        proposalThreshold = threshold;
        votingPeriod = period;
        quorumVotes = quorum;
        timelockDelay = delay;

        authorizedProposers[msg.sender] = true;
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new governance proposal
     * @param targets Contract addresses to call
     * @param values ETH values to send
     * @param signatures Function signatures
     * @param calldatas Encoded function calls
     * @param description Human-readable description
     * @return proposalId The ID of the new proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256 proposalId) {
        require(
            authorizedProposers[msg.sender] || getVotes(msg.sender) >= proposalThreshold,
            "Below proposal threshold"
        );
        require(
            targets.length == values.length &&
            targets.length == signatures.length &&
            targets.length == calldatas.length,
            "Array length mismatch"
        );
        require(targets.length != 0, "Must provide actions");

        proposalCount++;
        proposalId = proposalCount;

        uint256 startBlock = block.number + 1;
        uint256 endBlock = startBlock + votingPeriod;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startBlock: startBlock,
            endBlock: endBlock,
            eta: 0,
            canceled: false,
            executed: false
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            description
        );

        return proposalId;
    }

    /**
     * @notice Casts a vote on a proposal
     * @param proposalId The proposal to vote on
     * @param support 0=against, 1=for
     * @return votes Number of votes cast
     */
    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
        return castVoteWithReason(proposalId, support, "");
    }

    /**
     * @notice Casts a vote with a reason
     * @param proposalId The proposal to vote on
     * @param support 0=against, 1=for
     * @param reason Reason for the vote
     * @return votes Number of votes cast
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) public returns (uint256 votes) {
        require(state(proposalId) == ProposalState.Active, "Voting closed");
        require(support <= 1, "Invalid support value");

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = receipts[proposalId][msg.sender];

        require(!receipt.hasVoted, "Already voted");

        votes = getVotes(msg.sender);
        require(votes > 0, "No voting power");

        if (support == 0) {
            proposal.againstVotes += votes;
        } else {
            proposal.forVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = uint96(votes);

        emit VoteCast(msg.sender, proposalId, support, votes, reason);

        return votes;
    }

    /**
     * @notice Queues a successful proposal for execution
     * @param proposalId The proposal to queue
     */
    function queue(uint256 proposalId) external {
        require(state(proposalId) == ProposalState.Succeeded, "Proposal not successful");
        Proposal storage proposal = proposals[proposalId];
        proposal.eta = block.timestamp + timelockDelay;
        emit ProposalQueued(proposalId, proposal.eta);
    }

    /**
     * @notice Executes a queued proposal
     * @param proposalId The proposal to execute
     */
    function execute(uint256 proposalId) external payable {
        require(state(proposalId) == ProposalState.Queued, "Proposal not queued");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.eta, "Timelock not expired");

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            _executeTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i]
            );
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /**
     * @notice Cancels a proposal (only proposer or owner)
     * @param proposalId The proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        ProposalState currentState = state(proposalId);
        require(currentState != ProposalState.Executed, "Already executed");

        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer || msg.sender == owner,
            "Not authorized"
        );

        proposal.canceled = true;
        emit ProposalCanceled(proposalId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency function to suspend an agent immediately
     * @param agentAddress The agent to suspend
     * @param reason Reason for emergency suspension
     */
    function emergencySuspend(address agentAddress, string calldata reason)
        external
        onlyAuthorizedProposer
    {
        // Call registry to update status
        (bool success, ) = registry.call(
            abi.encodeWithSignature(
                "updateAgentStatus(address,uint8,string)",
                agentAddress,
                uint8(IAIAgent.AgentStatus.SUSPENDED),
                reason
            )
        );
        require(success, "Emergency suspend failed");

        emit EmergencyAction(agentAddress, "EMERGENCY_SUSPEND", msg.sender);
    }

    /**
     * @notice Emergency function to terminate an agent immediately
     * @param agentAddress The agent to terminate
     * @param reason Reason for emergency termination
     */
    function emergencyTerminate(address agentAddress, string calldata reason)
        external
        onlyOwner
    {
        (bool success, ) = registry.call(
            abi.encodeWithSignature(
                "updateAgentStatus(address,uint8,string)",
                agentAddress,
                uint8(IAIAgent.AgentStatus.TERMINATED),
                reason
            )
        );
        require(success, "Emergency terminate failed");

        emit EmergencyAction(agentAddress, "EMERGENCY_TERMINATE", msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds an authorized proposer
     * @param proposer Address to authorize
     */
    function addAuthorizedProposer(address proposer) external onlyOwner {
        authorizedProposers[proposer] = true;
    }

    /**
     * @notice Removes an authorized proposer
     * @param proposer Address to deauthorize
     */
    function removeAuthorizedProposer(address proposer) external onlyOwner {
        authorizedProposers[proposer] = false;
    }

    /**
     * @notice Updates proposal threshold
     * @param newThreshold New threshold value
     */
    function setProposalThreshold(uint256 newThreshold) external onlyOwner {
        uint256 old = proposalThreshold;
        proposalThreshold = newThreshold;
        emit ParameterUpdated("proposalThreshold", old, newThreshold);
    }

    /**
     * @notice Updates voting period
     * @param newPeriod New period in blocks
     */
    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        uint256 old = votingPeriod;
        votingPeriod = newPeriod;
        emit ParameterUpdated("votingPeriod", old, newPeriod);
    }

    /**
     * @notice Updates quorum requirement
     * @param newQuorum New quorum in basis points
     */
    function setQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 10000, "Quorum cannot exceed 100%");
        uint256 old = quorumVotes;
        quorumVotes = newQuorum;
        emit ParameterUpdated("quorumVotes", old, newQuorum);
    }

    /**
     * @notice Updates timelock delay
     * @param newDelay New delay in seconds
     */
    function setTimelockDelay(uint256 newDelay) external onlyOwner {
        uint256 old = timelockDelay;
        timelockDelay = newDelay;
        emit ParameterUpdated("timelockDelay", old, newDelay);
    }

    /**
     * @notice Transfers ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current state of a proposal
     * @param proposalId The proposal to check
     * @return The proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "Invalid proposal");
        Proposal storage proposal = proposals[proposalId];

        if (proposal.canceled) return ProposalState.Canceled;
        if (proposal.executed) return ProposalState.Executed;

        if (block.number <= proposal.startBlock) return ProposalState.Pending;
        if (block.number <= proposal.endBlock) return ProposalState.Active;

        // Voting ended
        bool quorumReached = (proposal.forVotes + proposal.againstVotes) >= quorumVotes;
        bool majorityFor = proposal.forVotes > proposal.againstVotes;

        if (!quorumReached || !majorityFor) return ProposalState.Defeated;

        if (proposal.eta == 0) return ProposalState.Succeeded;
        if (block.timestamp >= proposal.eta + timelockDelay) return ProposalState.Expired;
        if (block.timestamp >= proposal.eta) return ProposalState.Queued;

        return ProposalState.Succeeded;
    }

    /**
     * @notice Gets voting power of an address
     * @param voter The address to check
     * @return votes The voting power
     * @dev Currently returns 1 for any address (demo), integrate with token for production
     */
    function getVotes(address voter) public view returns (uint256) {
        // In production, this should call governanceToken.balanceOf(voter)
        // or a voting escrow contract
        return voter == address(0) ? 0 : 1;
    }

    /**
     * @notice Gets proposal information
     * @param proposalId The proposal ID
     * @return The proposal struct
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Gets a voter's receipt for a proposal
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @return The receipt
     */
    function getReceipt(uint256 proposalId, address voter)
        external
        view
        returns (Receipt memory)
    {
        return receipts[proposalId][voter];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes a single transaction from a proposal
     */
    function _executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal {
        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, ) = target.call{value: value}(callData);
        require(success, "Transaction execution failed");
    }
}
