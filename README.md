# Privacy-Preserving AI Bounty Judge — Commit-Reveal Implementation

## Deployed Contract
- **Network:** Ritual Testnet (Chain ID 1979)
- **Contract Address:** `0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff`
- **Deploy TX:** `0x8bd7ce77236387de71f11f85c9a5ec5fec72bfadef2eeb29bd3cd31457e56193`
- **RPC:** `https://rpc.ritualfoundation.org`
- **Explorer:** `http://explorer.ritualfoundation.org`

## Architecture

### Commit-Reveal Flow (Required Track)
1. **Submission Phase**: Participants submit `keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))` — only the hash is stored on-chain, the actual answer is hidden.
2. **Reveal Phase**: After the submission deadline, participants reveal their answer + salt. The contract recomputes the hash and verifies it matches the original commitment.
3. **Judging Phase**: The bounty owner calls `judgeAll(bountyId, llmInput)` which sends all revealed answers to the Ritual AI precompile for batch evaluation.
4. **Finalization**: Owner reviews AI ranking and selects a winner via `finalizeWinner()`. The reward is transferred to the winner.

### Key Functions
| Function | Description |
|----------|-------------|
| `createBounty()` | Create a bounty with submission/reveal deadlines and locked reward |
| `submitCommitment()` | Submit commitment hash during submission phase |
| `revealAnswer()` | Reveal answer + salt after submission deadline |
| `judgeAll()` | Send revealed answers to Ritual AI for batch judging |
| `finalizeWinner()` | Select winner and transfer reward |

### Security Properties
- Answers are **completely hidden** during submission phase (only hash on-chain)
- Commitment is **binding** — cannot change answer after committing
- Phase-based access control prevents out-of-order actions
- Answer length capped at 2000 chars to prevent gas griefing
- Max 10 submissions per bounty

### What's Public vs Hidden?
| Data | Visibility |
|------|-----------|
| Commitment hash | Public (on-chain) |
| Actual answer | Hidden until reveal |
| Bounty rubric | Public |
| AI review | On-chain after judging |
| Winner selection | On-chain, owner decision |

## Setup

### Prerequisites
- Node.js + pnpm
- Foundry (forge, cast)

### Install
```bash
cd hardhat && pnpm install
cd ../web && pnpm install
```

### Configure
```bash
# web/.env.local
NEXT_PUBLIC_CONTRACT_ADDRESS=0x9F3e64602e3b75e17fDC79563026Bc8D2D2eC5Ff
NEXT_PUBLIC_RITUAL_RPC_URL=https://rpc.ritualfoundation.org
NEXT_PUBLIC_RITUAL_CHAIN_ID=1979
NEXT_PUBLIC_RITUAL_EXECUTOR_ADDRESS=0xB42e435c4252A5a2E7440e37B609F00c61a0c91B
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<your-project-id>
```

### Run
```bash
cd web && pnpm dev
```

## Test Plan
1. Create bounty with future deadline
2. Submit commitment from wallet A → entry should be hidden
3. Try to view answer from wallet B → should see empty string
4. After deadline, reveal answer with correct salt → entry becomes visible
5. Try revealing with wrong salt → should revert
6. Call judgeAll → AI reviews all revealed answers
7. Finalize winner → reward transferred

## A Step I Struggled With
The biggest challenge was discovering that **Ritual Testnet's `block.timestamp` returns milliseconds instead of the standard seconds** that Solidity's `block.timestamp` returns on other EVM chains. When I first tried to create a bounty with a deadline calculated in Unix seconds (e.g., `1782315641`), the contract kept reverting with `"deadline must be future"` — even though the deadline was clearly 1 hour in the future. I spent significant time debugging gas estimation, trying `--legacy` flags, and checking bytecode before I realized the existing bounties on-chain had timestamps in the trillions (millisecond range) while my values were in the billions (second range). Multiplying all deadline values by 1000 fixed the issue immediately. This is a critical gotcha for anyone building on Ritual Chain — always use `Date.now()` or equivalent millisecond timestamps, not `Math.floor(Date.now() / 1000)`.

## Reflection Question
> "What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?"

In a bounty system, the **judging rubric** and **bounty parameters** (reward, deadlines) should always be public so participants know what they're competing for and how they'll be evaluated. **Submissions** should remain hidden during the evaluation period — using commitment hashes or encryption — to prevent plagiarism and strategic copying. **AI** should handle the bulk of evaluation: it can objectively score submissions against a rubric at scale, catching nuances that busy humans might miss, and it provides consistency across all entries. However, the **final winner selection** should remain with a human (the bounty owner) because AI has limitations — it may miss creative approaches, misjudge domain expertise, or be vulnerable to prompt injection in submissions. The AI review serves as an advisory ranking, not an autonomous decision. This hybrid approach combines AI's scalability and consistency with human judgment's flexibility and accountability.
