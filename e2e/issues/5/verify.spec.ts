import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify cursor blink fix', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click into the editor to show the cursor
  await page.locator('.cm-content').click()

  // Wait a moment for cursor to be positioned
  await page.waitForTimeout(200)

  // Capture "after" screenshot showing cursor with blink enabled
  const result = await assertScreenshot(page, 'cursor is visible in the editor', {
    save: { testFile: import.meta.url, name: 'after' }
  })
  console.log('After assertion:', result)
})
