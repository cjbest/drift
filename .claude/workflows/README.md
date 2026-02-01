# Verified Fix Workflows

This directory contains the process definitions for agent-driven verified fixes.

## Files

- `fix.md` - The main fix workflow (reproduce → fix → verify → evidence)
- `adjust.md` - Workflow for iterating based on user feedback
- `templates/` - Templates for verification plans and evidence output

## How to Test Locally

1. **Start a fix**: Tell the agent `/fix <describe the issue>`
2. **Review the verification plan**: Agent will create one and ask for approval
3. **Watch the process**: Agent captures before state, fixes, captures after state
4. **Review evidence**: Check `.claude/evidence/current/evidence.md`
5. **Adjust if needed**: Tell the agent `/adjust <your feedback>`

## Key Concepts

### Visual Assertions

We can't easily assert on visual correctness programmatically. Instead:

1. Take a screenshot
2. Ask an LLM: "Does this screenshot show X?"
3. Get back yes/no with confidence

This lets us verify things like "the indent looks correct" or "the button is visible".

### Before/After Comparison

More robust than just checking "after":

1. Capture "before" showing the bug EXISTS
2. Fix it
3. Capture "after" showing the bug is GONE
4. LLM compares: "Is the issue from the before screenshot fixed in the after screenshot?"

### Evidence Generation

The output in `evidence.md` is designed to go directly into a PR, making it
trivial for a human to verify the fix without running the code.

## TODO

- [ ] Implement actual `assertScreenshot()` helper using Claude vision
- [ ] Add GIF generation for demos
- [ ] Add retry logic with different approaches on failure
- [ ] Track verification history across attempts
