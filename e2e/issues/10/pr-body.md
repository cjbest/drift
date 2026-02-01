## Demo
![Demo](file:///Users/runner/work/drift/drift/e2e/issues/10/demo.gif)

## Summary
Replaced the monospace SF Mono font with an elegant serif font stack (Charter, Georgia, Cambria) for the editor body text, creating a much more refined and aesthetically pleasing note-taking experience. The title now uses SF Pro Display with optimized weight and letter-spacing. All typography has been carefully tuned with improved letter-spacing, line-height, and weight values for maximum readability and visual appeal in both light and dark modes.

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/screenshots/verify/before-light.png) | ![after](e2e/screenshots/verify/after-light.png) |
| Monospace SF Mono throughout - coding-focused aesthetic | Elegant serif body (Charter/Georgia) with refined sans-serif title |

| Dark Mode Before | Dark Mode After |
|--------|-------|
| ![before](e2e/screenshots/verify/before-dark.png) | ![after](e2e/screenshots/verify/after-dark.png) |
| Monospace in dark mode | Beautiful serif in dark mode with excellent contrast |

## Files Changed
- `src/components/Editor.tsx`: Updated editor font stack to elegant serif fonts (Charter, Georgia, Cambria), increased base size to 19px, refined line-height to 1.65, added negative letter-spacing for tighter elegant feel
- `src/components/Editor.css`: Enhanced first-line title with SF Pro Display at 1.75em and bold weight, added size/spacing differentiation for heading levels (H1/H2/H3), improved bold/italic letter-spacing, refined blockquote opacity
- `src/index.css`: Updated body font to SF Pro Text for UI consistency

## Adjustment Made
Re-recorded the demo with significantly more content to better showcase the typography improvements:
- Added more body text to demonstrate reading comfort with the serif fonts
- Expanded heading hierarchy with descriptive text under each heading level (H1, H2, H3)
- Included task list items with checkboxes to show vertical rhythm and alignment
- Added longer blockquote to showcase italic elegance
- Included multiple paragraphs demonstrating the refined letter-spacing and line-height
- Extended scrolling sequences to show the full document in both light and dark modes
- Increased pacing to give viewers more time to appreciate the typography details

The new demo provides a much more comprehensive view of the typographic improvements, showcasing headings, body text, emphasis, lists, blockquotes, and theme switching all in a single cohesive recording.