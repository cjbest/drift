## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/18/demo.gif)

## Summary
Added colorful particle effects that appear when typing in the editor. Each keystroke generates 3-5 particles that float upward with gravity, fade out naturally, and create a delightful visual feedback. The particles use a variety of colors (red, blue, green, yellow, purple) and animate smoothly at 60fps without impacting editor performance.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/18/screenshots/before.png) | ![after](e2e/issues/18/screenshots/after.png) |
| Plain editor with no visual effects when typing | Colorful particles appear at cursor position with each keystroke |

## Files Changed
- `src/components/ParticleEffects.tsx`: New component managing particle lifecycle, animation loop, and rendering
- `src/components/ParticleEffects.css`: Styles for particle container and individual particles with fixed positioning
- `src/components/Editor.tsx`: Integrated ParticleEffects component and added particle emission logic in updateListener when text is inserted

## Tests
- `e2e/issues/18/verify.spec.ts` - Verification test with before/after assertions
- `e2e/issues/18/demo.spec.ts` - Demo recording showing particles in action