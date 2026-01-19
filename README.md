# Drift

The markdown editor I always wanted for my personal notes.

<p align="center">
  <img src="assets/demo.gif?v=2" alt="Drift demo" width="600">
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

Built with Tauri 2, SolidJS, and CodeMirror 6.
