# Drift Development Notes

## Rules

- **Menu + Hotkey**: Every new functionality that has a keyboard shortcut must also be added to the app menu, with the hotkey displayed in the menu item.

## Development Workflow

- **After TypeScript changes**: Run `npx tsc --noEmit` to catch type errors before telling the user it's ready.
- **Check dev server output**: Tail the background task output file to catch compile/runtime errors after changes.
