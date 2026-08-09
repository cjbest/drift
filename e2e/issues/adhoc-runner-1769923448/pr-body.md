## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/adhoc-runner-1769923448/demo.gif)

## Summary
Increased the saturation of rainbow text colors from 70% to 95% and adjusted lightness from 60% to 55% in the HSL color values. This makes the rainbow effect much more vibrant and eye-catching, with colors that really pop off the page. Every character now displays with significantly more saturated and vivid colors across the entire spectrum.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/adhoc-runner-1769923448/screenshots/before.png) | ![after](e2e/issues/adhoc-runner-1769923448/screenshots/after.png) |
| Colors with 70% saturation, 60% lightness | Colors with 95% saturation, 55% lightness - much more vibrant! |

## Files Changed
- `src/components/Editor.tsx`: Updated HSL color values in rainbowDecorations from `hsl(${i}, 70%, 60%)` to `hsl(${i}, 95%, 55%)` for more vibrant and saturated rainbow colors

## Tests
- `e2e/issues/adhoc-runner-1769923448/verify.spec.ts` - Verification test with before/after assertions showing increased color vibrancy
- `e2e/issues/adhoc-runner-1769923448/demo.spec.ts` - Demo recording showcasing the vibrant rainbow effect in action