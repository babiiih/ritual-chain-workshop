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
 *         Answers remain hidden until reveal phase, preventing copying.
 */
contract CommitRevealAIJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;

    uint256 public nextBountyId = 1;

    IRitualWallet wallet =
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

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
     * @param rubric Judging criteria
     * @param submissionDeadline Timestamp when commitments close
     * @param revealDeadline Timestamp when reveals close (must be after submission)
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
     * @param bountyId The bounty to submit to
     * @param commitment keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
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
     * @param bountyId The bounty to reveal for
     * @param answer The original answer
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

        // Verify commitment
        bytes32 computed = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        require(
            computed == bounty.commitments[index].commitment,
            "commitment mismatch"
        );

        bounty.commitments[index].revealed = true;
        bounty.commitments[index].revealedAnswer = answer;

        // Transition to reveal phase if not already
        if (bounty.phase == Phase.Submission) {
            bounty.phase = Phase.Reveal;
        }

        emit AnswerRevealed(bountyId, msg.sender, index);
    }

    /**
     * @notice Judge all revealed answers using Ritual AI
     * @param bountyId The bounty to judge
     * @param llmInput Encoded LLM call data
     */
    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp >= bounty.revealDeadline,
            "reveal phase not ended"
        );
        require(
            bounty.phase == Phase.Reveal || bounty.phase == Phase.Submission,
            "already judged or finalized"
        );

        // Check at least one answer was revealed
        bool hasRevealed = false;
        for (uint256 i = 0; i < bounty.commitments.length; i++) {
            if (bounty.commitments[i].revealed) {
                hasRevealed = true;
                break;
            }
        }
        require(hasRevealed, "no revealed answers");

        bytes memory output = _executePrecompile(
            LLM_INFERENCE_PRECOMPILE,
            llmInput
        );

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,

        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        require(!hasError, errorMessage);

        bounty.phase = Phase.Judged;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    /**
     * @notice Finalize winner and pay reward
     * @param bountyId The bounty to finalize
     * @param winnerIndex Index of the winning submission
     */
    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.phase == Phase.Judged, "not judged yet");
        require(winnerIndex < bounty.commitments.length, "invalid index");
        require(
            bounty.commitments[winnerIndex].revealed,
            "winner not revealed"
        );

        bounty.phase = Phase.Finalized;
        bounty.winnerIndex = winnerIndex;

        address winner = bounty.commitments[winnerIndex].submitter;
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    /**
     * @notice Get bounty details
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
     * @notice Get commitment details (only after reveal or for own commitments)
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
            bool revealed,
            string memory answer
        )
    {
        Bounty storage bounty = bounties[bountyId];
        require(index < bounty.commitments.length, "invalid index");

        Commitment storage c = bounty.commitments[index];

        // Only show answer if revealed or if caller is the submitter/owner
        if (c.revealed || msg.sender == c.submitter || msg.sender == bounty.owner) {
            return (c.submitter, c.revealed, c.revealedAnswer);
        }

        // Hide answer during submission/reveal phases
        return (c.submitter, c.revealed, "");
    }

    /**
     * @notice Get current phase of a bounty
     */
    function getPhase(
        uint256 bountyId
    ) external view bountyExists(bountyId) returns (Phase) {
        Bounty storage bounty = bounties[bountyId];
        
        // Auto-transition phases based on time
        if (bounty.phase == Phase.Submission && block.timestamp >= bounty.submissionDeadline) {
            return Phase.Reveal;
        }
        if (bounty.phase == Phase.Reveal && block.timestamp >= bounty.revealDeadline) {
            // Can't auto-transition to Judged, needs judgeAll call
            return Phase.Reveal;
        }
        
        return bounty.phase;
    }
}
