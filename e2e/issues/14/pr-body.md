## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/14/demo.gif)

## Summary
Added CSS styling to make checked checkboxes `[x]` display in green color (#22c55e in light mode, #4ade80 in dark mode) for satisfying visual feedback. Unchecked checkboxes `[ ]` remain in the default text color.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/14/screenshots/before.png) | ![after](e2e/issues/14/screenshots/after.png) |
| Checked checkboxes displayed in default black/gray color | Checked checkboxes now display in green, providing visual feedback |

## Files Changed
- `src/components/Editor.css`: Added `.checkbox-checked` styles with green color for both light and dark themes

## Tests
- `e2e/issues/14/verify.spec.ts` - Verification test with before/after assertions
- `e2e/issues/14/demo.spec.ts` - Demo recording showing checkboxes turning green when checked