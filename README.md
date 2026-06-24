# Privacy-Preserving AI Bounty Judge — Commit-Reveal Implementation

## Overview
This project implements a **commit-reveal flow** for the AI Bounty Judge system on **Ritual Testnet (Chain ID 1979)**. Answers remain hidden until the reveal phase, preventing participants from copying others' ideas.

## Deployed Contract
| Detail | Value |
|--------|-------|
| **Contract Address** | `0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff` |
| **Network** | Ritual Testnet (Chain ID 1979) |
| **Deploy TX** | `0x8bd7ce77236387de71f11f85c9a5ec5fec72bfadef2eeb29bd3cd31457e56193` |
| **RPC** | `https://rpc.ritualfoundation.org` |
| **Explorer** | `http://explorer.ritualfoundation.org` |

## Commit-Reveal Lifecycle

```
1. CREATE BOUNTY    →  Owner funds reward + sets deadlines
2. SUBMIT PHASE     →  Participants submit commitment hashes
                      keccak256(answer, salt, sender, bountyId)
                      ⚠️ Only the hash is on-chain — answer is HIDDEN
3. REVEAL PHASE     →  After submission deadline, participants reveal
                      answer + salt. Contract verifies hash matches.
4. JUDGING PHASE    →  Owner calls judgeAll() with Ritual AI LLM input
                      All revealed answers judged together (batch)
5. FINALIZE WINNER  →  Owner selects winner → contract pays reward
```

## Required Functions

| Function | Description |
|----------|-------------|
| `submitCommitment(bountyId, commitment)` | Submit commitment hash during submission phase |
| `revealAnswer(bountyId, answer, salt)` | Reveal answer after submission deadline |
| `judgeAll(bountyId, llmInput)` | Batch judge all revealed answers via Ritual AI |
| `finalizeWinner(bountyId, winnerIndex)` | Select winner and pay reward |

## Security Features

- **Answers hidden** during submission phase (only commitment hash on-chain)
- **Commitment binding** — can't change answer after committing
- **Phase-based access control** — functions restricted by bounty phase
- **Automatic phase transitions** based on block timestamps
- **MAX_SUBMISSIONS = 10** and **MAX_ANSWER_LENGTH = 2000** to prevent abuse

## Test Plan for Reveal Cases

| Test Case | Expected Result |
|-----------|----------------|
| Submit before deadline | ✅ Commitment stored |
| Submit after deadline | ❌ Reverts "submissions closed" |
| Reveal before submission deadline | ❌ Reverts "submission phase not over" |
| Reveal after reveal deadline | ❌ Reverts "reveal phase ended" |
| Reveal with wrong salt | ❌ Reverts "commitment mismatch" |
| Reveal with correct salt | ✅ Answer revealed and stored |
| View entry during submission phase | ❌ Answer hidden (empty string) |
| View entry after reveal | ✅ Answer visible |
| Submit duplicate commitment | ❌ Reverts "already committed" |
| Exceed MAX_SUBMISSIONS | ❌ Reverts "too many submissions" |

## Architecture Note: Commit-Reveal vs Ritual-Native

### Commit-Reveal (Implemented — Required Track)
- **On-chain**: Commitment hashes only (keccak256 of answer + salt + sender + bountyId)
- **Off-chain**: Plaintext answers (revealed later during reveal phase)
- **Pros**: Simple, works on any EVM chain, verifiable
- **Cons**: Answers become public after reveal (before judging)

### Ritual-Native (Advanced Track Design)
- **On-chain**: Encrypted submissions (never plaintext)
- **Off-chain**: Plaintext answers exist only inside TEE
- **Judging**: TEE decrypts all answers, judges them in batch, submits result
- **Pros**: Answers hidden until judging complete
- **Cons**: More complex, requires Ritual TEE infrastructure

### Where Plaintext Answers Exist
1. **Participant's browser** — when composing the answer
2. **Reveal transaction calldata** — temporarily visible in mempool
3. **Contract storage** — after reveal (public on-chain)
4. **Ritual TEE memory** — (advanced track) during batch judging, never exposed

### On-chain vs Off-chain
| Data | Location |
|------|----------|
| Commitment hash | On-chain (solidity mapping) |
| Answer (pre-reveal) | Off-chain (participant only) |
| Answer (post-reveal) | On-chain (contract storage) |
| Salt | Off-chain until reveal |
| AI review result | On-chain (bytes field) |
| Winner selection | On-chain (finalized state) |

## A Step I Struggled With

The hardest part was **deploying to Ritual Testnet using Hardhat**. The original workshop used Hardhat 3 with `@nomicfoundation/hardhat-toolbox-viem`, but the deployment script tried to import `viem` directly from `hardhat` — which doesn't work in Hardhat 3 (you must use `hre.viem`). After multiple attempts to fix the Hardhat deploy script, I switched to **Foundry/Forge** which compiled and deployed successfully in one shot. Another major struggle was that **Ritual Testnet's `block.timestamp` returns MILLISECONDS instead of seconds** (standard EVM behavior). This caused all `createBounty()` calls to revert with "deadline must be future" even when timestamps were clearly in the future (in seconds). I discovered the fix by examining the timestamps of existing bounty data (in the ~1.78e12 range = milliseconds) and multiplying all my timestamps by 1000.

## An Error I Hit and How I Resolved It

**Error**: `deadline must be future` — contract reverted on every `createBounty()` call, even with timestamps 1 hour in the future.

**Root Cause**: Ritual Testnet's `block.timestamp` returns time in **milliseconds** (e.g., `1782312006160`) instead of standard EVM seconds (e.g., `1782312006`). The Solidity `require(submissionDeadline > block.timestamp)` check failed because I was passing seconds-scale values (1782315641) which are smaller than millisecond-scale block.timestamp values (1782312006160).

**Resolution**: I multiplied all deadline timestamps by 1000 (e.g., `1782315763000` instead of `1782315641`), which passed the comparison. This was confirmed by checking the `cast block latest` output showing `timestamp: 1782312006160`.

**Overall Rating: 7/10** — The commit-reveal flow is fully functional with all required functions implemented. The hidden submission feature works as demonstrated (entries show empty string before reveal). The main limitation is that Ritual AI precompile integration for batch judging couldn't be fully tested due to testnet constraints.

## Reflection Question

*"What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"*

The bounty rubric and reward should be **public** so participants understand what they're competing for and how they'll be evaluated. Participants' answers must remain **hidden** during the submission phase to prevent plagiarism and ensure fair competition — this is the core problem the commit-reveal pattern solves. During the judging phase, answers can be revealed since the submission window has closed. **AI** should handle the initial evaluation of submissions against the rubric, providing consistent, scalable, and unbiased scoring of all answers simultaneously. However, **humans** (the bounty owner) should make the final winner selection, as AI evaluations may miss nuanced qualities like creativity, practical impact, or domain-specific expertise that the rubric doesn't fully capture. This hybrid approach combines AI's consistency with human judgment's flexibility, creating a fair and efficient bounty system.

## Quick Start

```bash
# Install dependencies
cd hardhat && pnpm install && cd ..
cd web && pnpm install && cd ..

# Set environment variables
export DEPLOYER_PRIVATE_KEY=<your-private-key>
cp web/.env.local.example web/.env.local  # edit with your values

# Compile and deploy (uses Foundry)
cd hardhat
forge build
forge create src/CommitRevealAIJudge.sol:CommitRevealAIJudge \
  --rpc-url https://rpc.ritualfoundation.org \
  --private-key $DEPLOYER_PRIVATE_KEY

# Run the web frontend
cd ../web
pnpm dev
```

## Links
- [Ritual Chain Workshop (Original)](https://github.com/cozfuttu/ritual-chain-workshop)
- [Ritual Documentation](https://docs.ritual.net)
