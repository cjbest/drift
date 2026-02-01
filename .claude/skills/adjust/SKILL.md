---
name: adjust
description: Iterate on a fix based on user feedback
disable-model-invocation: true
argument-hint: <feedback>
---

# Adjust: $ARGUMENTS

The user has reviewed the evidence from `/fix` and wants changes.

## Process

1. **Parse feedback** - what specifically needs to change?

2. **Update verification plan** if needed:
   - Add new assertions based on feedback
   - Modify success criteria

3. **Implement adjustment**

4. **Re-verify**:
   - Run the updated verification steps
   - Capture new "after" screenshots
   - Run all assertions (original + new from feedback)

5. **Regenerate evidence**:
   - Show updated before/after comparison
   - Explain what changed from the previous attempt

6. **Present to user** for another review cycle

## Notes

- Keep the original "before" screenshots - they show the original problem
- If stuck after 3 adjustment cycles, ask user to clarify or simplify
