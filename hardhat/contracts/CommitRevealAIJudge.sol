// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function lockUntil(address) external view returns (uint256);
}

/**
 * @title CommitRevealAIJudge
 * @notice Privacy-preserving AI bounty judge with commit-reveal flow.
 *         Answers remain hidden until reveal phase, preventing participants
 *         from copying others' ideas.
 * 
 * @dev Implements the commit-reveal pattern:
 *      1. Submission Phase: Participants submit commitment hashes
 *      2. Reveal Phase: After deadline, participants reveal answers
 *      3. Judging Phase: AI judges revealed answers
 *      4. Finalization: Winner selected and paid
 */
contract CommitRevealAIJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;
    address public constant RITUAL_PRECOMPILE = 0x7b7AD7D719c88F72ed298bd7c21C7d6DDE1e7E3D;

    uint256 public nextBountyId = 1;

    IRitualWallet wallet = IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    enum Phase { None, Submission, Reveal, Judged, Finalized }

    struct Commitment {
        address submitter;
        bytes32 commitment;
        bool revealed;
        string revealedAnswer;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        Phase phase;
        bytes aiReview;
        uint256 winnerIndex;
        Commitment[] commitments;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => bool)) public hasCommitted;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        address indexed submitter
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        address indexed submitter,
        uint256 indexed commitmentIndex
    );

    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "bounty not found");
        _;
    }

    /**
     * @notice Create a new bounty with submission and reveal deadlines
     * @param title Bounty title
     * @param rubric Judging criteria for AI
     * @param submissionDeadline Timestamp when commitments close
     * @param revealDeadline Timestamp when reveals close (must be after submission)
     * @return bountyId The ID of the newly created bounty
     */
    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(submissionDeadline > block.timestamp, "deadline must be future");
        require(revealDeadline > submissionDeadline, "reveal must be after submission");

        bountyId = nextBountyId++;

        Bounty storage bounty = bounties[bountyId];
        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.submissionDeadline = submissionDeadline;
        bounty.revealDeadline = revealDeadline;
        bounty.phase = Phase.Submission;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(
            bountyId,
            msg.sender,
            title,
            msg.value,
            submissionDeadline,
            revealDeadline
        );
    }

    /**
     * @notice Submit a commitment hash during submission phase
     * @dev Commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
     * @param bountyId The bounty to submit to
     * @param commitment The commitment hash (answer stays hidden)
     */
    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.phase == Phase.Submission, "not in submission phase");
        require(block.timestamp < bounty.submissionDeadline, "submissions closed");
        require(!hasCommitted[bountyId][msg.sender], "already committed");
        require(bounty.commitments.length < MAX_SUBMISSIONS, "too many submissions");

        bounty.commitments.push(
            Commitment({
                submitter: msg.sender,
                commitment: commitment,
                revealed: false,
                revealedAnswer: ""
            })
        );

        hasCommitted[bountyId][msg.sender] = true;

        emit CommitmentSubmitted(bountyId, msg.sender);
    }

    /**
     * @notice Reveal answer after submission deadline
     * @dev Verifies that keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
     *      matches the previously submitted commitment
     * @param bountyId The bounty to reveal for
     * @param answer The original answer (plaintext)
     * @param salt The salt used in commitment
     */
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp >= bounty.submissionDeadline,
            "submission phase not over"
        );
        require(
            block.timestamp < bounty.revealDeadline,
            "reveal phase ended"
        );
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        // Find the commitment for this sender
        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < bounty.commitments.length; i++) {
            if (bounty.commitments[i].submitter == msg.sender && !bounty.commitments[i].revealed) {
                index = i;
                break;
            }
        }
        require(index != type(uint256).max, "no commitment found");

        // Verify commitment matches
        bytes32 computed = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        require(
            computed == bounty.commitments[index].commitment,
            "commitment mismatch"
        );

        bounty.commitments[index].revealed = true;
        bounty.commitments[index].revealedAnswer = answer;

        if (bounty.phase == Phase.Submission) {
            bounty.phase = Phase.Reveal;
        }

        emit AnswerRevealed(bountyId, msg.sender, index);
    }

    /**
     * @notice Judge all revealed answers using Ritual AI
     * @dev Only callable by bounty owner after reveal deadline
     * @param bountyId The bounty to judge
     * @param llmInput The input for the LLM (rubric + answers)
     */
    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external onlyOwner(bountyId) bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp >= bounty.revealDeadline,
            "reveal phase not over"
        );
        require(bounty.phase == Phase.Reveal, "not in reveal phase");
        require(bounty.commitments.length > 0, "no submissions");

        // Verify all commitments are revealed
        for (uint256 i = 0; i < bounty.commitments.length; i++) {
            require(bounty.commitments[i].revealed, "not all revealed");
        }

        (bool success, bytes memory result) = RITUAL_PRECOMPILE.call(llmInput);
        require(success, "LLM call failed");

        bounty.aiReview = result;
        bounty.phase = Phase.Judged;

        emit AllAnswersJudged(bountyId, result);
    }

    /**
     * @notice Finalize the winner and pay reward
     * @dev Only callable by bounty owner after judging
     * @param bountyId The bounty to finalize
     * @param winnerIndex Index of the winning submission
     */
    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external onlyOwner(bountyId) bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.phase == Phase.Judged, "not judged yet");
        require(winnerIndex < bounty.commitments.length, "invalid winner");
        require(bounty.commitments[winnerIndex].revealed, "winner not revealed");

        bounty.winnerIndex = winnerIndex;
        bounty.phase = Phase.Finalized;

        address winner = bounty.commitments[winnerIndex].submitter;

        (bool success, ) = winner.call{value: bounty.reward}("");
        require(success, "transfer failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, bounty.reward);
    }

    /**
     * @notice Get bounty details
     * @param bountyId The bounty to query
     * @return owner Bounty creator
     * @return title Bounty title
     * @return rubric Judging criteria
     * @return reward Bounty reward
     * @return submissionDeadline Commitment deadline
     * @return revealDeadline Reveal deadline
     * @return phase Current phase
     * @return commitmentCount Total commitments
     * @return revealedCount Revealed commitments
     * @return winnerIndex Winner index (type(uint256).max if not finalized)
     * @return aiReview AI review bytes
     */
    function getBounty(
        uint256 bountyId
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 submissionDeadline,
            uint256 revealDeadline,
            Phase phase,
            uint256 commitmentCount,
            uint256 revealedCount,
            uint256 winnerIndex,
            bytes memory aiReview
        )
    {
        Bounty storage bounty = bounties[bountyId];

        uint256 revealed = 0;
        for (uint256 i = 0; i < bounty.commitments.length; i++) {
            if (bounty.commitments[i].revealed) {
                revealed++;
            }
        }

        return (
            bounty.owner,
            bounty.title,
            bounty.rubric,
            bounty.reward,
            bounty.submissionDeadline,
            bounty.revealDeadline,
            bounty.phase,
            bounty.commitments.length,
            revealed,
            bounty.winnerIndex,
            bounty.aiReview
        );
    }

    /**
     * @notice Get commitment details
     * @param bountyId The bounty
     * @param index Commitment index
     * @return submitter Commitment creator
     * @return commitment Commitment hash
     * @return revealed Whether answer is revealed
     * @return answer Revealed answer (empty if not revealed and not owner/submitter)
     */
    function getCommitment(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address submitter,
            bytes32 commitment,
            bool revealed,
            string memory answer
        )
    {
        Bounty storage bounty = bounties[bountyId];
        require(index < bounty.commitments.length, "invalid index");

        Commitment storage c = bounty.commitments[index];

        if (c.revealed || msg.sender == c.submitter || msg.sender == bounty.owner) {
            return (c.submitter, c.commitment, c.revealed, c.revealedAnswer);
        }

        return (c.submitter, c.commitment, c.revealed, "");
    }

    /**
     * @notice Get current phase (auto-transitions based on time)
     * @param bountyId The bounty
     * @return phase Current phase
     */
    function getPhase(
        uint256 bountyId
    ) external view bountyExists(bountyId) returns (Phase) {
        Bounty storage bounty = bounties[bountyId];
        
        if (bounty.phase == Phase.Submission && block.timestamp >= bounty.submissionDeadline) {
            return Phase.Reveal;
        }
        
        return bounty.phase;
    }
}
