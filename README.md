# Privacy-Preserving AI Bounty Judge - Commit-Reveal Solution

## Problem
In the original AI Judge system, submissions were **public during the submission phase**, allowing participants to copy others' ideas and submit improved versions. This creates an unfair advantage and undermines the integrity of the bounty system.

## Solution: Commit-Reveal Flow
Implemented a commit-reveal mechanism where:
1. **Submission Phase**: Participants submit only a **commitment hash** (`keccak256(answer, salt, sender, bountyId)`)
2. **Reveal Phase**: After submission deadline, participants reveal their answer and salt
3. **Judging Phase**: Only revealed answers are eligible for AI judging

## Key Implementation
- `submitCommitment()` - Submit commitment hash (answer stays hidden)
- `revealAnswer()` - Reveal after deadline with salt verification
- Automatic phase transitions based on timestamps
- Answer hiding until revealed

## Contract Address (Ritual Testnet)
**Deployed:** `0x0d57fA1bA3446508019366637AbD035B00Aa51B4`

## Deploy TX Hash
`0x359a6bf855b210125b34e5a464795f88dbde8586e3744ab8118109c932d495f3`

## Problem Solved
| Before | After |
|--------|-------|
| Answers visible during submission | Only hashes visible |
| Can copy improved versions | Can't see answers until reveal |
| Unfair advantage | Fair competition |

## Reflection Question
In a bounty system, the rubric and judging criteria should be public to ensure fairness. Participants' answers should remain hidden during submission to prevent copying. AI should handle initial evaluation based on rubric compliance, but humans should make final winner selection to account for nuanced judgment. The commitment hash proves submission without revealing content, while the reveal phase ensures accountability. Final payouts should be automated through smart contracts to ensure trustless execution.
