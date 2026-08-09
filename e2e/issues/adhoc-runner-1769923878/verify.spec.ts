import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify rainbow colors are more vibrant', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some text to see the rainbow effect
  await page.locator('.cm-content').click()
  await page.keyboard.type('Rainbow colors make text more vibrant and fun to read! The quick brown fox jumps over the lazy dog. ABCDEFGHIJKLMNOPQRSTUVWXYZ 1234567890', { delay: 0 })

  // Wait for rainbow decorations to apply
  await page.waitForTimeout(200)

  // Capture screenshot showing rainbow colors
  const result = await assertScreenshot(page, 'rainbow text with vibrant saturated colors', {
    save: { testFile: import.meta.url, name: 'after' }
  })
  console.log('Assertion:', result)
})
