import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify DOOM face feature', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Wait for editor to be ready
  await page.waitForTimeout(500)

  // Type some content to have something in the editor
  await page.locator('.cm-content').click()
  await page.keyboard.type('# Test Note\n\nThis is a test note to verify the DOOM face feature.')

  // Wait for content to render
  await page.waitForTimeout(500)

  // Wait for the DOOM face to appear
  await expect(page.locator('.doom-face-container')).toBeVisible()

  // Capture screenshot showing the DOOM face in the bottom right corner
  const result = await assertScreenshot(page, 'shows DOOM face in bottom right corner with healthy face and word count', {
    save: { testFile: import.meta.url, name: 'after' }
  })
  console.log('After screenshot assertion:', result)
})
