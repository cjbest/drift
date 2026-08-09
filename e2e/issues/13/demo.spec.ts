import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: title with subtle underline', async ({ page }) => {
  test.slow()

  // Use a compact viewport - no sidebar, just the editor
  await page.setViewportSize({ width: 700, height: 500 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Wait a moment for the editor to be fully ready
  await page.waitForTimeout(800)

  // Focus on the editor
  await page.locator('.cm-content').click()
  await page.waitForTimeout(500)

  // Type a title with human-like speed
  await page.keyboard.type('Meeting Notes - Q1 Planning', { delay: 40 })
  await page.waitForTimeout(800)

  // Move to body content
  await page.keyboard.press('Enter')
  await page.waitForTimeout(600)

  // Type body content
  await page.keyboard.type('Key discussion points:', { delay: 40 })
  await page.waitForTimeout(500)
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Product roadmap for Q1', { delay: 40 })
  await page.waitForTimeout(500)
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Resource allocation', { delay: 40 })
  await page.waitForTimeout(500)
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Budget review', { delay: 40 })
  await page.waitForTimeout(1000)

  // Move cursor back to title to show the underline
  await page.keyboard.press('Control+Home')
  await page.waitForTimeout(1200)
})
