## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/7/demo.gif)

## Summary
Implemented a rainbow text feature that applies a smooth, subtle color gradient to all typed characters. Each character receives a unique hue from the HSL color spectrum (70% saturation, 60% lightness), creating a pleasant rainbow effect that flows across the text as you type. The implementation uses CodeMirror's decoration system with a custom ViewPlugin that applies inline color styles to individual characters.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/screenshots/verify/before.png) | ![after](e2e/screenshots/verify/after.png) |
| Text displayed in uniform black color | Text displayed with smooth rainbow gradient - each word in different colors flowing from red through yellow, green, cyan, blue, to purple |

## Files Changed
- `src/components/Editor.tsx`: Added `rainbowDecorations` array (360 color decorations using HSL), `rainbowHighlighter` ViewPlugin that applies colors to each character based on position, and registered the plugin in the editor extensions

## Tests
- `e2e/issues/7/verify.spec.ts` - Verification test with before/after assertions confirming rainbow colors are applied
- `e2e/issues/7/demo.spec.ts` - Demo recording showing the rainbow effect in action as text is typed