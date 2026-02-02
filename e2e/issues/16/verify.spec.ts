import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify minimap feature - before', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content to create a longer document that benefits from a minimap
  await page.locator('.cm-content').click()

  const longContent = `My Document Title

## Introduction
This is the first section of the document. It contains several lines of text that help demonstrate the minimap feature. The minimap should show an overview of all this content.

## Section One
Here we have more content in the first section. This section talks about various topics and includes multiple paragraphs.

We can add bullet points:
- First point about something
- Second point with more details
- Third point to expand on ideas

## Section Two
This is another major section with its own content. The minimap should help users navigate between these sections quickly.

### Subsection A
More detailed content here under a subsection. This helps create even more vertical space in the document.

### Subsection B
Additional subsection content to make the document longer and more realistic.

## Section Three
Yet another section to demonstrate the minimap overview. The longer the document, the more useful the minimap becomes.

This section has multiple paragraphs to add even more content. The minimap provides a bird's eye view of the entire document structure.

## Conclusion
Final section wrapping up the document. The minimap should show all sections at once in a zoomed-out view.

Some final thoughts and closing remarks to complete this longer document that demonstrates the minimap feature.`

  await page.keyboard.type(longContent, { delay: 0 })

  // Wait for content to render
  await page.waitForTimeout(500)

  // Save "before" screenshot - should show NO minimap on the right
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'before.png'), fullPage: true })

  // Verify no minimap exists yet
  const result = await assertScreenshot(page, 'no minimap panel visible on the right side')
  console.log('Before assertion:', result)
  expect(result.passed).toBe(true)
})

test('verify minimap feature - after', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type the same content
  await page.locator('.cm-content').click()

  const longContent = `My Document Title

## Introduction
This is the first section of the document. It contains several lines of text that help demonstrate the minimap feature. The minimap should show an overview of all this content.

## Section One
Here we have more content in the first section. This section talks about various topics and includes multiple paragraphs.

We can add bullet points:
- First point about something
- Second point with more details
- Third point to expand on ideas

## Section Two
This is another major section with its own content. The minimap should help users navigate between these sections quickly.

### Subsection A
More detailed content here under a subsection. This helps create even more vertical space in the document.

### Subsection B
Additional subsection content to make the document longer and more realistic.

## Section Three
Yet another section to demonstrate the minimap overview. The longer the document, the more useful the minimap becomes.

This section has multiple paragraphs to add even more content. The minimap provides a bird's eye view of the entire document structure.

## Conclusion
Final section wrapping up the document. The minimap should show all sections at once in a zoomed-out view.

Some final thoughts and closing remarks to complete this longer document that demonstrates the minimap feature.`

  await page.keyboard.type(longContent, { delay: 0 })

  // Wait for minimap to render
  await page.waitForTimeout(1000)

  // Wait for minimap to be visible
  await expect(page.locator('.minimap')).toBeVisible({ timeout: 5000 })

  // Save "after" screenshot - should show minimap on the right
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png'), fullPage: true })

  // Verify minimap is visible
  const result = await assertScreenshot(page, 'a minimap panel is visible on the right side showing a zoomed-out overview of the document')
  console.log('After assertion:', result)
  expect(result.passed).toBe(true)
})
