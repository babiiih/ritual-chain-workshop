# Privacy-Preserving AI Bounty Judge - Commit-Reveal Implementation

## Problem Statement

### The Critical Flaw
In the original AI Judge system, **submissions were public during the submission phase**. This created a major vulnerability:

| Issue | Impact |
|-------|--------|
| **Answers visible** | Participants could see others' submissions |
| **Copy improved versions** | Late submitters could copy and improve early answers |
| **Unfair advantage** | Those who submit later get unfair advantage |
| **Undermined integrity** | The bounty system becomes unfair |

### Example Scenario
1. Alice submits a creative solution at T=10
2. Bob sees Alice's answer at T=11
3. Bob copies Alice's idea, improves it, submits at T=12
4. Bob wins with "improved" version of Alice's idea

**This is unfair!** Alice should win because she had the original idea.

---

## Solution: Commit-Reveal Pattern

### Core Concept
The commit-reveal pattern separates **submission** from **disclosure**:

1. **Commit Phase**: Submit a cryptographic hash (commitment) that proves you know the answer
2. **Reveal Phase**: After deadline, reveal your answer and salt
3. **Verification**: Contract verifies the revealed answer matches the commitment
4. **Judging**: Only verified, revealed answers are eligible for AI judging

### Why This Works
- **During submission**: Only hashes visible — can't see actual answers
- **After deadline**: Reveal phase begins — can't change your answer
- **Before judging**: All answers revealed — AI can judge fairly

---

## Implementation Details

### Smart Contract Architecture

```
+---------------------------------------------------------------+
|                  CommitRevealAIJudge                          |
+---------------------------------------------------------------+
|  State Variables:                                             |
|  - nextBountyId (uint256)                                    |
|  - bounties (mapping(uint256 => Bounty))                     |
|  - hasCommitted (mapping(uint256 => mapping(address => bool)))|
+---------------------------------------------------------------+
|  Bounty Struct:                                               |
|  - owner, title, rubric, reward                              |
|  - submissionDeadline, revealDeadline                        |
|  - phase (Phase enum)                                        |
|  - commitments (Commitment[])                                |
+---------------------------------------------------------------+
|  Commitment Struct:                                           |
|  - submitter (address)                                       |
|  - commitment (bytes32)                                      |
|  - revealed (bool)                                           |
|  - revealedAnswer (string)                                   |
+---------------------------------------------------------------+
```

### Phase Flow

```
PHASE 1: SUBMISSION --> PHASE 2: REVEAL --> PHASE 3: JUDGING --> FINALIZED

  - Submit hash only    - Reveal answer     - AI Judges answers   - Winner paid
  - Answer hidden       - Verify matches    - Select winner
```

### Key Functions

#### 1. `createBounty()`
Creates a new bounty with two deadlines:
- `submissionDeadline`: When commitments close
- `revealDeadline`: When reveals close (must be after submission)

```solidity
function createBounty(
    string calldata title,
    string calldata rubric,
    uint256 submissionDeadline,
    uint256 revealDeadline
) external payable returns (uint256 bountyId)
```

#### 2. `submitCommitment()`
Submits a commitment hash during submission phase:
```solidity
function submitCommitment(
    uint256 bountyId,
    bytes32 commitment  // keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
) external
```

#### 3. `revealAnswer()`
Reveals the answer after submission deadline:
```solidity
function revealAnswer(
    uint256 bountyId,
    string calldata answer,
    bytes32 salt
) external
```

#### 4. `judgeAll()` (Owner Only)
Judges all revealed answers using Ritual AI:
```solidity
function judgeAll(
    uint256 bountyId,
    bytes calldata llmInput
) external onlyOwner(bountyId)
```

#### 5. `finalizeWinner()` (Owner Only)
Selects winner and pays reward:
```solidity
function finalizeWinner(
    uint256 bountyId,
    uint256 winnerIndex
) external onlyOwner(bountyId)
```

---

## Security Analysis

### What's Hidden, What's Public

| Data | During Submission | During Reveal | After Judging |
|------|-------------------|---------------|---------------|
| **Answer** | Hidden (hash only) | Revealed | Public |
| **Salt** | Hidden | Revealed | Public |
| **Submitter** | Public | Public | Public |
| **Commitment** | Public | Public | Public |
| **Rubric** | Public | Public | Public |

### Attack Vectors and Mitigations

| Attack | Mitigation |
|--------|------------|
| **Copy during submission** | Only hashes visible, can't reverse |
| **Change answer after commit** | Commitment is binding (hash match) |
| **Front-running** | Deadline-based, not first-come-first-served |
| **Denial of reveal** | Grace period for reveals |
| **Sybil attacks** | One commitment per address per bounty |

### Commitment Binding
The commitment hash proves:
1. You knew the answer at commitment time
2. You can't change it without invalidating the hash
3. The salt prevents rainbow table attacks

```
commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

---

## Comparison: Commit-Reveal vs Ritual-Native

### Approach 1: Commit-Reveal (Implemented)
**On-chain:** Commitment hashes, phase transitions, winner selection
**Off-chain:** Plaintext answers (revealed later), salt values

**Pros:**
- Simple implementation
- Works on any EVM chain
- No TEE dependency
- Lower gas costs

**Cons:**
- Answers become public before judging
- Potential for last-minute reveals
- Requires active participation (reveal step)

### Approach 2: Ritual-Native (Advanced Track)
**On-chain:** Encrypted submissions, phase transitions
**Off-chain:** Plaintext answers (never on-chain), decryption keys in TEE

**Pros:**
- Answers hidden until judging
- Better privacy
- No reveal step needed

**Cons:**
- More complex implementation
- Requires Ritual TEE
- Higher gas costs
- Ritual-specific dependency

---

## Deployment and Testing

### Contract Details
- **Network:** Ritual Testnet (Chain ID 1979)
- **Contract Address:** `0x0d57fA1bA3446508019366637AbD035B00Aa51B4`
- **Deploy TX:** `0x359a6bf855b210125b34e5a464795f88dbde8586e3744ab8118109c932d495f3`
- **Deployer:** `0x1801Ade4ebD374CCB3ddFC3AF64C539433DF4fBa`

### Test Plan

#### Test Case 1: Basic Commit-Reveal Flow
```javascript
// 1. Create bounty
await contract.createBounty("Test", "Rubric", deadline1, deadline2, {value: parseEther("0.1")});

// 2. Submit commitment
const answer = "My answer";
const salt = ethers.utils.randomBytes(32);
const commitment = ethers.utils.solidityKeccak256(
  ["string", "bytes32", "address", "uint256"],
  [answer, salt, userAddress, bountyId]
);
await contract.submitCommitment(bountyId, commitment);

// 3. Reveal (after deadline)
await contract.revealAnswer(bountyId, answer, salt);

// 4. Judge
await contract.judgeAll(bountyId, llmInput);
```

#### Test Case 2: Invalid Reveal (Mismatched Commitment)
```javascript
// Should revert with "commitment mismatch"
await contract.revealAnswer(bountyId, "wrong answer", salt);
```

#### Test Case 3: Double Commit Prevention
```javascript
// Should revert with "already committed"
await contract.submitCommitment(bountyId, commitment);
await contract.submitCommitment(bountyId, commitment); // FAILS
```

#### Test Case 4: Deadline Enforcement
```javascript
// Should revert with "submissions closed" if after deadline
await contract.submitCommitment(bountyId, commitment);
```

---

## Reflection Question

**"What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"**

**Answer (5-8 sentences):**

**Public Elements:** Rubric and judging criteria should be public to ensure fairness and transparency. Submission deadlines and bounty rules must be visible to all participants. The commitment hashes should be public to prove submission without revealing content.

**Hidden Elements:** Participants' answers must remain hidden during the submission phase to prevent copying. Salt values should stay hidden until reveal to maintain commitment binding. Personal information about submitters should be protected.

**AI vs Human Judgment:** AI should handle initial evaluation based on rubric compliance, ensuring objective assessment and scalability. Humans should make final winner selection to account for nuanced judgment, context, and creative merit that AI may miss. The commitment hash proves submission without revealing content, while the reveal phase ensures accountability. This hybrid approach leverages AI efficiency while maintaining human oversight for fairness. Final payouts should be automated through smart contracts to ensure trustless execution.

---

## Deliverables Checklist

- [x] Updated Solidity contract with commit-reveal flow
- [x] README explaining lifecycle (this document)
- [x] Test plan for reveal cases (see Test Plan section)
- [x] Architecture note comparing approaches (see Comparison section)
- [x] Reflection question answered (see Reflection section)
- [x] Deployed contract on Ritual Testnet
- [x] GitHub repository with all code

---

## Build and Run

### Prerequisites
- Node.js >= 16
- npm or yarn
- Hardhat

### Setup
```bash
cd hardhat
npm install
```

### Compile
```bash
npx hardhat compile
```

### Deploy
```bash
npx hardhat ignition deploy ignition/modules/CommitRevealAIJudge.ts --network ritualTestnet
```

### Test
```bash
npx hardhat test
```

---

## License

MIT License
