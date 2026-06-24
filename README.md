# Privacy-Preserving AI Bounty Judge — Commit-Reveal Implementation

## Overview
This project implements a **commit-reveal flow** for the AI Bounty Judge system on **Ritual Testnet (Chain ID 1979)**. Answers remain hidden until the reveal phase, preventing participants from copying others' ideas.

**Deployed Contract:** `0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff`
**Deploy TX:** `0x8bd7ce77236387de71f11f85c9a5ec5fec72bfadef2eeb29bd3cd31457e56193`
**GitHub:** https://github.com/babiiih/ritual-chain-workshop

## How It Works

### The Flow
1. **Bounty Created** — Owner defines title, rubric, deadlines, and locks reward in ETH
2. **Submission Phase** — Participants submit `keccak256(answer, salt, sender, bountyId)` — only the hash is stored on-chain, the actual answer is hidden
3. **Reveal Phase** — After submission deadline, participants reveal their answer + salt. The contract verifies the hash matches
4. **Judging Phase** — Owner calls `judgeAll()` with Ritual AI LLM input for batch evaluation
5. **Finalization** — Owner selects winner, contract pays reward automatically

### Key Functions
| Function | Purpose |
|----------|---------|
| `createBounty()` | Create bounty with deadlines and locked reward |
| `submitCommitment()` | Submit commitment hash during submission phase |
| `revealAnswer()` | Reveal answer + salt after submission deadline |
| `getBounty()` | Get bounty details (title, rubric, phase, counts) |
| `getCommitment()` | Get commitment details (hides answer if not revealed) |
| `judgeAll()` | Submit all revealed answers to Ritual AI for judging |
| `finalizeWinner()` | Select winner and pay reward |

## Contract Architecture

```
CommitRevealAIJudge.sol
├── Bounty lifecycle management
├── Commit-reveal privacy flow
├── Ritual Precompile integration (RITUAL_PRECOMPILE)
├── Winner finalization with ETH payout
└── 10 max submissions per bounty
```

## Security Design Choices

- **Commitment binding**: Once submitted, the commitment hash cannot be changed
- **Phase enforcement**: Functions are gated by bounty phase (Submission → Reveal → Judged → Finalized)
- **Answer hiding**: `getCommitment()` returns empty string for unrevealed answers
- **Deadline enforcement**: Block timestamps enforce phase transitions
- **Reward locking**: ETH is locked in contract on bounty creation, paid to winner only

## Deliverables

- ✅ Updated Solidity contract with commit-reveal flow
- ✅ README explaining lifecycle
- ✅ Test plan for reveal cases
- ✅ Architecture note

## Test Plan for Reveal Cases

| Test Case | Expected Result |
|-----------|----------------|
| Submit during submission phase | ✅ Commitment stored, answer hidden |
| Submit after deadline | ❌ Reverts "submissions closed" |
| Reveal during reveal phase | ✅ Answer verified and stored |
| Reveal with wrong salt | ❌ Reverts "commitment mismatch" |
| Reveal with wrong answer | ❌ Reverts "commitment mismatch" |
| Reveal after reveal deadline | ❌ Reverts "reveal phase ended" |
| View unrevealed commitment | Returns empty string for answer |
| Judge before all revealed | ❌ Reverts "not all revealed" |
| Finalize before judged | ❌ Reverts "not judged yet" |

## A Step I Struggled With

The hardest part was **debugging why `createBounty()` kept reverting with "deadline must be future"** even when I was passing timestamps that were clearly in the future (e.g., `1782315641` which is 1 hour from current Unix time `1782312000`). I spent significant time checking:
- The contract bytecode to verify the comparison logic
- Whether `cast send` was encoding the uint256 values correctly
- Whether the gas estimation was failing for a different reason

I tried multiple approaches: different encodings, `--legacy` flag, `--force` flag, raw calldata encoding, and even deploying a helper contract to read `block.timestamp`. None of them revealed the issue directly because the revert message was misleading — it looked like a simple timestamp comparison failure.

## An Error I Hit and How I Resolved It

**Error:** `deadline must be future` — transaction reverts despite passing future timestamps.

**Root Cause:** **Ritual Testnet's `block.timestamp` returns MILLISECONDS, not seconds** (unlike standard EVM chains which use seconds). The existing bounties on-chain had timestamps in the `1.782e12` range (milliseconds), but I was passing seconds-based timestamps (`1.782e9`).

**How I Resolved It:** I examined the on-chain state of previously deployed bounties and noticed their deadlines were in the millisecond range (`1782311894800` vs my seconds `1782315641`). The contract was comparing my seconds-based timestamp against a millisecond-based `block.timestamp`, so `block.timestamp` (~1782312006000ms) was always greater than my deadline (~1782315641s). Once I multiplied all timestamps by 1000, the transaction succeeded immediately.

**Lesson:** Always check what `block.timestamp` actually returns on non-standard chains. Don't assume seconds — verify against existing on-chain data.

## Overall Rating: 7/10

The commit-reveal mechanism works correctly and entries are verified hidden. The web frontend is functional. However, I couldn't fully test the Ritual AI integration (judgeAll) because the Ritual executor precompile requires specific configuration. The rating reflects a working core mechanism with room for end-to-end integration testing.

## Reflection Question

*"What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"*

The bounty's rubric and judging criteria should always be **public** so participants know how they'll be evaluated — transparency in rules prevents disputes and ensures fairness. Participants' answers must remain **hidden** during the submission phase using cryptographic commitments (hashes); this prevents plagiarism and strategic copying, which was the core flaw in the original system. The AI should handle **initial evaluation** — batch-scoring all revealed answers against the rubric consistently and without bias, which is something humans struggle with at scale. However, the **final winner selection** should remain with the human bounty owner, because AI evaluation can miss context, humor, or unconventional approaches that a human would recognize as valuable. The AI's review should be **advisory** (as implemented in this contract), not binding — it provides a ranked assessment, but the owner has the final say. This hybrid approach combines AI's consistency and scalability with human judgment and contextual understanding, creating a fair and efficient bounty system.
