import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify particle effects when typing', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Clear the editor first
  const editor = page.locator('.cm-editor .cm-content')
  await editor.click()
  await page.keyboard.press('Meta+a')
  await page.keyboard.press('Backspace')

  // Type text and capture during typing to see particles
  await page.keyboard.type('Typing', { delay: 50 })

  // Wait briefly to catch particles mid-animation
  await page.waitForTimeout(100)

  // Save screenshot showing the after state (with particle effects)
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png') })

  // Verify particles are visible using visual assertion
  const result = await assertScreenshot(page, 'colorful particles visible near the cursor or text')
  console.log('After state assertion:', result)

  // Visual assertion should confirm particles are present
  expect(result.passed).toBe(true)
})
