## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/9/demo.gif)

## Summary
Implemented a DOOM-style ASCII art face indicator that appears in the bottom right corner of the editor and progressively takes damage as word count increases. The face starts healthy (green) at 0-100 words, becomes scratched and bruised (orange) at 200-400 words, transitions to dead/skull states (red/gray) at 600-800+ words, with increasingly elaborate damage states beyond 800 words. The component displays the current health status and word count, providing a fun visual feedback mechanism for tracking writing progress.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/screenshots/verify/before.png) | ![after](e2e/screenshots/verify/after.png) |
| Clean editor interface without any word count indicator | DOOM face appears in bottom right corner showing healthy face with "FRESH" status and word count |

## Files Changed
- `src/components/DoomFace.tsx`: Created new component with 10 ASCII art face states (healthy → scratched → bruised → bloodied → beaten → dead → skull variants → exploded) that change based on word count thresholds
- `src/components/DoomFace.css`: Added styling with color-coded health states (green/orange/red/gray), fixed positioning in bottom right, hover effects, and theme support
- `src/App.tsx`: Integrated DoomFace component into main app, passing content signal for real-time word count tracking
- `e2e/issues/9/verify.spec.ts`: Verification test with before/after assertions
- `e2e/issues/9/demo.spec.ts`: Demo recording showing face damage progression

## Tests
- `e2e/issues/9/verify.spec.ts` - Verification test with before/after assertions
- `e2e/issues/9/demo.spec.ts` - Demo recording