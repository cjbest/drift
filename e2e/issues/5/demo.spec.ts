import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: cursor blink animation', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click into the editor to focus and show cursor
  await page.locator('.cm-content').click()

  // Wait to show the cursor blinking
  await page.waitForTimeout(3000)

  // Type some text with realistic delay to show cursor during typing
  await page.keyboard.type('The cursor now blinks', { delay: 80 })

  // Pause to show the cursor blinking after typing
  await page.waitForTimeout(2500)

  // Move cursor around to show it blinking at different positions
  await page.keyboard.press('Home')
  await page.waitForTimeout(2000)

  await page.keyboard.press('End')
  await page.waitForTimeout(2000)

  // Add a new line to show cursor in different positions
  await page.keyboard.press('Enter')
  await page.keyboard.type('Blinking helps locate the cursor', { delay: 70 })

  // Final pause to show the blinking
  await page.waitForTimeout(3000)
})
