# Drift

A minimal, distraction-free markdown writing app for macOS. Think iA Writer meets Bear, but lighter.

## Vision

Drift is for writers who want to focus on words, not features. It stays out of your way until you need it.

## Features

### Done
- [x] Native macOS app (Tauri + SolidJS)
- [x] Markdown editor with CodeMirror 6
- [x] Live preview (inline bold/italic rendering)
- [x] Dark theme matching macOS

### In Progress
- [ ] File sidebar organized by date (Today, Yesterday, This Week, etc.)
- [ ] Auto-save with intelligent auto-naming from first line
- [ ] Quick jump search (Cmd+P) for navigating notes

### Planned
- [ ] Native macOS menus with standard shortcuts
- [ ] Light/dark mode following system preference
- [ ] Distraction-free mode (hide sidebar, fade UI)
- [ ] Local file storage (~/.drift or configurable)

## Tech Stack

- **Tauri** - Native macOS wrapper, Rust backend
- **SolidJS** - Reactive UI
- **CodeMirror 6** - Editor foundation
- **TypeScript** - Type safety

## Development

```bash
npm install
npm run tauri dev
```

## Philosophy

1. **Local-first** - Your notes are files on disk, not locked in a database
2. **Fast** - Launch instantly, never wait
3. **Minimal** - No accounts, no sync complexity, no bloat
4. **Native** - Looks and feels like it belongs on macOS
