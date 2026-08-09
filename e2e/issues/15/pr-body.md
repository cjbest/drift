## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/15/demo.gif)

## Summary
Implemented keyboard shortcut hints that smoothly fade in when the user holds down the Cmd key. The hints display common shortcuts (⌘N, ⌘P, ⌘⇧N, ⌘D, ⌘F, ⌘K) in a centered overlay with a semi-transparent background and disappear when Cmd is released.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/15/screenshots/before.png) | ![after](e2e/issues/15/screenshots/after.png) |
| No hints visible when using the editor | Keyboard shortcuts appear in a clean overlay when holding Cmd |

## Files Changed
- `src/components/KeyboardHints.tsx`: New component that displays shortcut hints with fade-in animation
- `src/components/KeyboardHints.css`: Styles for the hint overlay with theme support (light/dark) and smooth fade-in animation
- `src/App.tsx`: Added cmdHeld signal, imported KeyboardHints component, integrated into existing Cmd key handlers

## Tests
- `e2e/issues/15/verify.spec.ts` - Verification test with before/after assertions
- `e2e/issues/15/demo.spec.ts` - Demo recording showing hints fading in and out