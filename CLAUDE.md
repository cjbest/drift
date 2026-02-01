# Drift Development Notes

## Rules

- **Menu + Hotkey**: Every new functionality that has a keyboard shortcut must also be added to the app menu, with the hotkey displayed in the menu item.

## Development Workflow

- **After TypeScript changes**: Run `npx tsc --noEmit` to catch type errors before telling the user it's ready.
- **Check dev server output**: Tail the background task output file to catch compile/runtime errors after changes.

## Verified Fix Workflow (Experimental)

### Where Things Live

| What | Where | Persists? |
|------|-------|-----------|
| Working state (attempts, debug) | Scratchpad | No (ephemeral) |
| PR evidence (before/after) | PR body | Yes (on GitHub) |
| Test screenshots | `e2e/screenshots/<test>/` | Yes (committed) |
| Workflow definitions | `.claude/workflows/` | Yes (committed) |

### Commands

- `/fix <issue>` - Full workflow: reproduce → fix → verify → generate PR evidence
- `/adjust <feedback>` - Iterate on current fix based on feedback

### Test Screenshots

Use the helper to capture screenshots that get committed:

```typescript
import { screenshot } from './helpers/screenshots'

// Saves to: e2e/screenshots/<test-name>/description.png
await screenshot(page, import.meta.url, 'what-this-shows')
```

These provide visual history - you can see what changed in PR diffs.

### Key Principle: Verify Before AND After

For bugs: First prove the bug EXISTS (before), then prove it's FIXED (after).
For features: First prove it's MISSING (before), then prove it WORKS (after).

The before/after comparison is more robust than just checking "after" state.
