## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/13/demo.gif)

## Summary
Added a subtle gray underline to the title line (first line) of notes using CSS text-decoration. The underline uses a semi-transparent gray color (rgba 0.25 opacity) with 1px thickness and slight offset for a tasteful, polished appearance that visually separates the title from the body content without being distracting.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/13/screenshots/before.png) | ![after](e2e/issues/13/screenshots/after.png) |
| Title displayed without underline | Title now has a subtle gray underline for visual separation |

## Files Changed
- src/components/Editor.css: Added text-decoration properties to `.first-line-title` class including underline with rgba(128, 128, 128, 0.25) color, 1px thickness, and 0.18em offset

## Tests
- `e2e/issues/13/verify.spec.ts` - Verification test with before/after screenshots
- `e2e/issues/13/demo.spec.ts` - Demo recording showing the underline in action
- `e2e/issues/13/debug.spec.ts` - Debug test confirming CSS styles are properly applied (computed styles show textDecorationLine: 'underline')