---
name: fix
description: Fix a bug or implement a feature with verified before/after evidence
disable-model-invocation: true
argument-hint: <issue description>
---

# Fix: $ARGUMENTS

Follow the verified fix workflow:

## Phase 1: Plan Verification

1. Parse the issue - what exactly needs to be fixed/built?
2. Create a verification plan:
   - Steps to reproduce (bug) or demonstrate (feature)
   - What "success" looks like
   - Specific visual assertions to check
3. Get user approval on the plan before proceeding

## Phase 2: Capture "Before" State

1. Execute reproduction steps
2. Take screenshots showing the bug/missing feature
3. Use `assertScreenshot()` to confirm the problem EXISTS
4. If can't reproduce, stop and ask for clarification

## Phase 3: Implement Fix

1. Implement the fix/feature
2. Run `npx tsc --noEmit` to catch type errors
3. Run relevant tests

## Phase 4: Verify Fix

1. Execute the same reproduction steps
2. Take screenshots showing it's fixed
3. Use `assertScreenshot()` to confirm the fix WORKS
4. If verification fails, revert and try a different approach (max 3 attempts)

## Phase 5: Generate Evidence

Create compelling before/after evidence for the user:
- Before screenshot with caption explaining the problem
- After screenshot with caption explaining the fix
- Summary of what changed

## Phase 6: User Review

Present the evidence and ask if it looks correct.
If user wants changes, they'll use `/adjust`.
