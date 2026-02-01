# Fix Workflow

When the user invokes `/fix <issue>`, follow this process:

## Phase 1: Understand & Plan Verification

1. **Parse the issue** - What exactly needs to be fixed/built?

2. **Create verification plan** - Write to `.claude/evidence/current/verification-plan.md`:
   - Steps to reproduce the issue (if bug) or demonstrate the feature works (if feature)
   - What "success" looks like in plain language
   - Specific assertions to check (both programmatic and visual)

3. **Get user approval** on the verification plan before proceeding

## Phase 2: Capture "Before" State

1. **Execute the reproduction steps** from the verification plan
2. **Capture evidence**:
   - Screenshots at key moments → `.claude/evidence/current/before/`
   - Use `assertScreenshot()` to confirm the bug IS present (or feature IS missing)
3. **If can't reproduce**: Stop and ask user for clarification

## Phase 3: Implement Fix

1. Implement the fix/feature
2. Run type checks, lints, existing tests
3. If tests fail, fix them before proceeding

## Phase 4: Verify Fix

1. **Execute the same steps** from the verification plan
2. **Capture evidence**:
   - Screenshots at key moments → `.claude/evidence/current/after/`
   - Use `assertScreenshot()` to confirm the bug IS fixed (or feature IS working)
3. **Compare before/after** - Use LLM to verify the fix is apparent
4. **If verification fails**:
   - Log what went wrong
   - Revert changes
   - Try a different approach (back to Phase 3)
   - Max 3 attempts before asking user for help

## Phase 5: Generate Evidence

1. Create `.claude/evidence/current/evidence.md` with:
   - Issue summary
   - Before/after screenshots with captions
   - Video/GIF if helpful
   - Explanation of the fix
2. Show the user the evidence for review

## Phase 6: User Review

Present the evidence and ask:
- "Does this look correct? Should I proceed to commit/PR?"
- If user says adjust → go to `/adjust` workflow
- If user approves → commit and optionally create PR

---

## Helper: assertScreenshot

To verify visual state, use the pattern:

```
1. Take screenshot
2. Send to Claude vision with the assertion
3. Get back { passed, confidence, explanation }
4. If confidence < 0.8, treat as uncertain
5. Log all results for debugging
```

Example assertions:
- "The bug is visible: the second wrapped line has no indent"
- "The fix is working: all wrapped lines are properly indented"
- "The button is visible and enabled"
- "The error message is displayed"
