# PR Summary: Cool Explosions While You Type

## Description

Implemented an awesome explosion animation system that creates colorful particle bursts at the cursor position while typing in the Drift editor. The feature is toggleable via keyboard shortcut and menu item.

## Key Features

- **Particle Explosions**: Each keystroke triggers 8 colorful particles that burst outward from the cursor position
- **Rainbow Colors**: Particles have randomized hues (0-360 degrees) creating a vibrant rainbow effect
- **Smooth Animations**: Particles animate outward using CSS transforms with ease-out timing (0.6s duration)
- **Toggleable**: Can be enabled/disabled via Cmd+E keyboard shortcut or View menu
- **Persistent State**: Explosion setting is saved to localStorage and persists across sessions

## Key Files Changed

### src/components/Editor.tsx
- Added `ExplosionParticle` widget class that creates individual particle DOM elements
- Added `explosionAnimator` ViewPlugin that detects typing events and creates explosion decorations
- Added `explosionsEnabled` global state variable (reads from localStorage)
- Added keyboard shortcut (Cmd+E) to toggle explosions
- Added `onToggleExplosions` prop to EditorProps interface
- Registered explosion animator plugin in the editor extensions

### src/components/Editor.css
- Added `.explosion-particle` class for styling particle elements
- Added `@keyframes explosion-burst` animation that:
  - Moves particles outward using polar coordinates (angle + distance)
  - Fades opacity from 1 to 0
  - Scales particles from 1 to 0
- Particles are 6px circles with HSL colors and subtle glow shadow

### src/App.tsx
- Added `toggleExplosions()` function that:
  - Toggles the localStorage setting
  - Shows status message ("Explosions on" / "Explosions off")
  - Reloads the page to apply changes
- Added menu event listener for 'menu-toggle-explosions'
- Wired up `onToggleExplosions` prop to Editor component

### src-tauri/src/lib.rs
- Added "Toggle Explosions" menu item to View menu
- Added Cmd+E keyboard shortcut (displayed in menu)
- Added 'toggle_explosions' menu event handler

### e2e/explosions.spec.ts (NEW)
- Test: Verifies particles appear when typing with explosions enabled
- Test: Verifies Cmd+E toggles the explosion state in localStorage
- Test: Verifies no particles appear when explosions are disabled

## Design Decisions

1. **ViewPlugin Architecture**: Used CodeMirror's ViewPlugin system to integrate seamlessly with the editor's update cycle. This ensures explosions trigger on actual user input (not programmatic changes).

2. **Widget Decorations**: Particles are implemented as widget decorations positioned at the cursor. This approach:
   - Leverages CodeMirror's decoration system
   - Automatically handles positioning relative to text
   - Cleans up particles when they're no longer needed

3. **User Event Detection**: The plugin specifically checks for `tr.isUserEvent('input')` to only trigger on typing, not on other document changes (like AI edits or file loads).

4. **Particle Cleanup**: Explosions older than 1 second are automatically cleaned from the map to prevent memory leaks.

5. **Polar Coordinates**: Used polar coordinates (angle + distance) in CSS for natural radial burst pattern:
   - 8 particles evenly distributed in a circle (360° / 8 = 45° spacing)
   - Random angle offset (±30°) adds organic feel
   - Random distance (20-50px) creates depth variation

6. **Page Reload for Toggle**: The toggle requires a page reload because the `explosionsEnabled` variable is read at module load time. This keeps the implementation simple and ensures consistent state.

7. **Default Enabled**: Explosions are enabled by default (localStorage check for `!== 'false'`), making the feature immediately discoverable.

## Testing

All tests pass:
- 9 existing tests (unchanged)
- 3 new explosion tests
- TypeScript compilation successful (no errors)

The feature is production-ready and provides a fun, engaging visual effect while maintaining code quality and test coverage.
