# Adjust Workflow

When the user invokes `/adjust <feedback>`, follow this process:

## Context

The user has reviewed the evidence from a `/fix` and wants changes.
The current state is in `.claude/evidence/current/`.

## Process

1. **Parse feedback** - What specifically needs to change?

2. **Update verification plan** if needed:
   - Add new assertions based on feedback
   - Modify success criteria
   - Save updated plan to `.claude/evidence/current/verification-plan.md`

3. **Archive current "after" state**:
   - Move `.claude/evidence/current/after/` → `.claude/evidence/current/attempt-N/`
   - This preserves history of attempts

4. **Implement adjustment**

5. **Re-verify**:
   - Run the updated verification plan
   - Capture new "after" screenshots
   - Run all assertions (original + new from feedback)

6. **Regenerate evidence**:
   - Update `.claude/evidence/current/evidence.md`
   - Show user the new before/after comparison

7. **Present to user** for another review cycle

## Notes

- Keep the original "before" screenshots - they show the original problem
- Each adjustment attempt should be numbered and logged
- If stuck after 3 adjustment cycles, ask user to clarify or simplify
