# Drift

The markdown editor I always wanted for my personal notes.

<p align="center">
  <img src="assets/demo2.gif" alt="Drift demo" width="600">
</p>

Most note apps are slow, bloated, or want to own your data. Drift is different:

- **Instant** - Native macOS app, not Electron. Launches in under a second.
- **Plain markdown files** - Your notes live in `~/Documents/Drift`. Open them in any editor.
- **AI that helps** - Cmd+K fixes typos, grammar, and fills in placeholders.
- **Zero friction** - Auto-save, auto-naming from content, Cmd+P to find anything.

## Shortcuts

| | |
|----------|--------|
| **Cmd+P** | Quick open |
| **Cmd+K** | AI fix selection |
| **Cmd+N** | New note |
| **Cmd+F** | Find in document |
| **Cmd+D** | Toggle dark/light |

## Development

```bash
npm install
npm run tauri dev
```

## Build

```bash
npm run tauri build
```

## Claude Agent

This repo has an automated Claude agent that can fix issues and respond to PR feedback.

### Creating Issues

Add the `claude` label to any issue and Claude will:
1. Analyze the issue and explore the codebase
2. Capture a "before" screenshot proving the problem
3. Implement the fix
4. Capture an "after" screenshot proving it works
5. Record a demo GIF showing the feature
6. Open a PR with all the evidence

### Iterating on PRs

Comment `@claude <feedback>` on any PR to request changes. Claude will:
1. Read your feedback and the conversation history
2. Update the implementation
3. Re-record the demo
4. Push the changes

### Running Locally

```bash
# Fix an issue
npm run fix -- --issue 123 "Issue description"

# Adjust a PR
npm run fix -- --pr 8 "Make it smoother"
```

Requires `ANTHROPIC_API_KEY` in environment or `.env` file.

---

Built with Tauri 2, SolidJS, and CodeMirror 6.
