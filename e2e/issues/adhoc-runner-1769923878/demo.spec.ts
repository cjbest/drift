import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: vibrant rainbow colors in action', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click in the editor
  await page.locator('.cm-content').click()
  await page.waitForTimeout(500)

  // Type a colorful message
  await page.keyboard.type('Welcome to Drift! ', { delay: 40 })
  await page.waitForTimeout(300)

  await page.keyboard.type('Rainbow colors make text vibrant and fun to read. ', { delay: 40 })
  await page.waitForTimeout(300)

  await page.keyboard.type('The quick brown fox jumps over the lazy dog. ', { delay: 40 })
  await page.waitForTimeout(300)

  await page.keyboard.type('ABCDEFGHIJKLMNOPQRSTUVWXYZ ', { delay: 40 })
  await page.waitForTimeout(300)

  await page.keyboard.type('0123456789', { delay: 40 })
  await page.waitForTimeout(800)

  // Add a new line with more colorful content
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  await page.keyboard.type('Each character gets its own unique color from the rainbow spectrum! ', { delay: 40 })
  await page.waitForTimeout(800)

  // Show scrolling through the colorful text
  await page.keyboard.press('Home')
  await page.waitForTimeout(400)

  await page.keyboard.press('End')
  await page.waitForTimeout(800)
})
