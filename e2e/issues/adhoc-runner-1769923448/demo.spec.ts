import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: vibrant rainbow text in action', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click to focus the editor
  const editor = page.locator('.cm-content')
  await editor.click()
  await page.waitForTimeout(500)

  // Type a sentence showcasing the vibrant rainbow colors
  await page.keyboard.type('Rainbow colors are now more vibrant and saturated!', { delay: 40 })
  await page.waitForTimeout(1000)

  // Type another line to show the color gradient across multiple lines
  await page.keyboard.press('Enter')
  await page.keyboard.type('Every character gets its own unique color in the spectrum.', { delay: 40 })
  await page.waitForTimeout(1000)

  // Type a final line
  await page.keyboard.press('Enter')
  await page.keyboard.type('The colors really pop off the page now! 🌈', { delay: 40 })
  await page.waitForTimeout(2000)
})
