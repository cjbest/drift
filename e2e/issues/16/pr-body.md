## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/16/demo.gif)

## Summary
Added a minimap panel on the right side of the editor that displays a zoomed-out overview of the entire document. The minimap shows document structure as horizontal bars and includes a viewport indicator showing the current scroll position. Users can click anywhere in the minimap to quickly jump to that section of the document, making navigation in longer notes much easier.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/16/screenshots/before.png) | ![after](e2e/issues/16/screenshots/after.png) |
| Editor without minimap - standard view only | Minimap visible on right side showing document overview with viewport indicator |

## Files Changed
- src/components/Editor.tsx: Added minimapPlugin ViewPlugin that creates a canvas-based minimap with viewport tracking and click-to-jump navigation
- src/components/Editor.css: Added styles for .minimap container, .minimap-canvas, and .minimap-viewport indicator with light/dark theme support

## Tests
- `e2e/issues/16/verify.spec.ts` - Verification test with before/after visual assertions confirming minimap presence
- `e2e/issues/16/demo.spec.ts` - Demo showing minimap in action with scrolling and click navigation