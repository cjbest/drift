import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: particle effects when typing', async ({ page }) => {
  test.slow()

  // Use a compact viewport - no sidebar, just the editor
  await page.setViewportSize({ width: 800, height: 500 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Clear the editor
  const editor = page.locator('.cm-editor .cm-content')
  await editor.click()
  await page.keyboard.press('Meta+a')
  await page.keyboard.press('Backspace')

  // Wait a moment for a clean start
  await page.waitForTimeout(500)

  // Type a title with particles appearing
  await page.keyboard.type('Delightful Typing', { delay: 40 })
  await page.waitForTimeout(800)

  // Add a new line
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Type some body text
  await page.keyboard.type('Watch the colorful particles appear as you type!', { delay: 40 })
  await page.waitForTimeout(800)

  // Add another line
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Type more text to show continuous effect
  await page.keyboard.type('Each keystroke creates a burst of particles.', { delay: 40 })
  await page.waitForTimeout(1000)

  // Continue typing
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)
  await page.keyboard.type('They float upward and fade away beautifully.', { delay: 40 })
  await page.waitForTimeout(1000)
})
