import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify rainbow text feature', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some text to see the coloring effect
  const editor = page.locator('.cm-content')
  await editor.click()
  await page.keyboard.type('The quick brown fox jumps over the lazy dog', { delay: 10 })

  // Wait a moment for rendering
  await page.waitForTimeout(500)

  // Capture screenshot showing the current text rendering
  const result = await assertScreenshot(page, 'text with rainbow colors', {
    save: { testFile: import.meta.url, name: 'after' }
  })
  console.log('Assertion:', result)

  // The assertion should pass - text should have rainbow colors
  expect(result.passed).toBe(true)
})
