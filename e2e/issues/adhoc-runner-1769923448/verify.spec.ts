import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify rainbow colors are vibrant and saturated', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some text to see the rainbow coloring effect
  const editor = page.locator('.cm-content')
  await editor.click()
  await page.keyboard.type('The quick brown fox jumps over the lazy dog. Rainbow colors should be vibrant!', { delay: 10 })

  // Wait for rendering to complete
  await page.waitForTimeout(500)

  // Capture screenshot showing the rainbow colors
  const result = await assertScreenshot(page, 'rainbow text with vibrant saturated colors', {
    save: { testFile: import.meta.url, name: 'after' }
  })
  console.log('Assertion:', result)
})
