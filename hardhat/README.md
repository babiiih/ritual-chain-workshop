# Privacy-Preserving AI Bounty Judge — Commit-Reveal Implementation

## Overview

This project implements a **commit-reveal flow** for the Ritual AI Bounty Judge system, ensuring submissions remain hidden until the reveal phase, preventing participants from copying others' ideas.

## Deployed Contract (Ritual Testnet)

| Field | Value |
|-------|-------|
| **Contract Address** | `0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff` |
| **Network** | Ritual Testnet (Chain ID 1979) |
| **Deploy TX** | `0x8bd7ce77236387de71f11f85c9a5ec5fec72bfadef2eeb29bd3cd31457e56193` |
| **Deployer** | `0x1801Ade4ebD374CCB3ddFC3AF64C539433DF4fBa` |
| **Explorer** | http://explorer.ritualfoundation.org/address/0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff |

## How It Works

### The Commit-Reveal Flow

```
1. CREATE BOUNTY     Owner creates bounty with reward, deadline, rubric
        │
2. SUBMIT PHASE      Participants submit commitment hashes
        │            keccak256(answer, salt, sender, bountyId)
        │            ← Answers are HIDDEN, only hash visible
        │
3. REVEAL PHASE      After submission deadline, participants reveal
        │            Contract verifies hash matches commitment
        │
4. JUDGING           Owner calls judgeAll() with Ritual AI LLM input
        │            AI reviews all revealed answers against rubric
        │
5. FINALIZE          Owner selects winner → contract pays reward
```

### Key Functions

| Function | Phase | Description |
|----------|-------|-------------|
| `createBounty()` | Any | Create bounty with reward + deadlines |
| `submitCommitment()` | Submission | Submit commitment hash (answer hidden) |
| `revealAnswer()` | Reveal | Reveal answer + salt after deadline |
| `getBounty()` | Any | View bounty details |
| `getCommitment()` | Any | View commitment (answer hidden until revealed) |

### Privacy Guarantees

- ✅ During submission phase: **answers are completely hidden** (only hash stored on-chain)
- ✅ `getCommitment()` returns empty string for unrevealed answers
- ✅ Commitment is binding — cannot change answer after submitting
- ✅ Automatic phase transitions based on timestamps

## ⚠️ Important: Ritual Chain Timestamp

**Ritual Testnet uses MILLISECONDS for `block.timestamp`**, not seconds!

```solidity
// ❌ WRONG (standard EVM)
uint256 deadline = block.timestamp + 1 hours; // adds 3600

// ✅ CORRECT (Ritual Chain)
uint256 deadline = block.timestamp + 3600000; // adds 3600 * 1000
```

When creating bounties via CLI, pass timestamps in milliseconds:
```bash
# Get current timestamp in milliseconds
NOW_MS=$(($(date +%s) * 1000))
SUBMIT=$((NOW_MS + 3600000))   # 1 hour
REVEAL=$((NOW_MS + 7200000))   # 2 hours
```

## Setup & Deployment

### Prerequisites
- Node.js 20+
- pnpm
- Private key with Ritual Testnet ETH

### Install
```bash
cd hardhat
cp .env.example .env  # Add your private key
pnpm install
```

### Compile
```bash
pnpm hardhat compile
```

### Deploy
```bash
pnpm hardhat compile
# Deploy using Foundry (recommended for Ritual Testnet)
forge create contracts/CommitRevealAIJudge.sol:CommitRevealAIJudge \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $PRIVATE_KEY
```

### Run Web Frontend
```bash
cd web
cp .env.local.example .env.local  # Set contract address
pnpm install
pnpm dev
```

## Test Plan

### Test Case 1: Happy Path
1. Create bounty with 1-hour submission, 2-hour reveal deadline
2. User A submits commitment
3. User B submits commitment
4. After deadline, User A reveals → success
5. User B reveals → success
6. Owner judges and finalizes winner

### Test Case 2: Hidden Entry Verification
1. During submission phase, call `getCommitment()` → answer is `""`
2. After reveal, call `getCommitment()` → answer is visible
3. Verify commitment hash matches `keccak256(answer, salt, sender, bountyId)`

### Test Case 3: Edge Cases
- ❌ Submit after deadline → reverts "submissions closed"
- ❌ Reveal before deadline → reverts "submission phase not over"
- ❌ Reveal with wrong salt → reverts "commitment mismatch"
- ❌ Double submit → reverts "already committed"
- ❌ Reveal after reveal deadline → reverts "reveal phase ended"

## Architecture Note: Commit-Reveal vs Ritual-Native

| Aspect | Commit-Reveal (This) | Ritual-Native (Advanced) |
|--------|---------------------|--------------------------|
| **Storage** | Hashes on-chain | Encrypted on-chain |
| **Reveal** | User reveals manually | TEE decrypts for judging |
| **Privacy** | Hidden until reveal | Hidden until judging complete |
| **Complexity** | Simple, any EVM | Complex, Ritual-specific |
| **Trade-off** | Answers public before judging | Answers never public |

## Reflection Question

*"What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"*

**Public:** Bounty rubric, deadlines, reward amount, number of participants, and judging criteria should be fully transparent so all participants understand expectations. Commitment hashes should be visible to prove participation without revealing content.

**Hidden:** Individual answers must remain hidden during the submission phase to prevent copying and ensure fair competition. Salts are private by nature. During judging, answers should ideally remain hidden from other participants.

**AI vs Human:** AI excels at consistent, scalable evaluation against defined rubrics — it can judge dozens of submissions simultaneously without bias. However, humans should make the final winner selection, as they can account for creativity, real-world applicability, and nuances that AI might miss. The ideal system uses AI for structured scoring and humans for final decision-making.

## License

MIT
