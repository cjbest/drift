## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/5/demo.gif)

## Summary
Implemented cursor blink animation in the editor to make the cursor easier to locate while typing. Changed the CodeMirror `cursorBlinkRate` from 0 (disabled) to 1200ms and removed the CSS `animation: none` rule that prevented blinking. The cursor now has a gentle blink cycle matching standard text editor behavior.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/5/screenshots/before.png) | ![after](e2e/issues/5/screenshots/after.png) |
| Static cursor with no animation | Cursor enabled with 1200ms blink animation |

## Files Changed
- `src/components/Editor.tsx:1145` - Changed `cursorBlinkRate` from 0 to 1200 to enable blinking
- `src/components/Editor.css:186` - Removed `animation: none !important` to allow CodeMirror's blink animation

## Tests
- `e2e/issues/5/verify.spec.ts` - Verification test with before/after assertions
- `e2e/issues/5/demo.spec.ts` - Demo recording showing cursor blinking during typing