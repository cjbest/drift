import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('bullet indent is consistent on wrapped lines', async ({ page }) => {
  await page.setViewportSize({ width: 600, height: 800 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  // Type a title
  await page.keyboard.type('Meeting Notes')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Type a long bullet that will wrap multiple times
  await page.keyboard.type('- ')
  const longText = 'This is a long bullet point that spans multiple lines. We need enough text here to ensure it wraps to at least three or four lines in the editor window to test the indent behavior.'
  await page.keyboard.type(longText)

  // Get the bullet line element
  const bulletLine = page.locator('.cm-line').filter({ hasText: 'This is a long bullet' })
  await expect(bulletLine).toBeVisible()

  // Verify the line has margin-left style applied (our fix uses margin-left)
  const style = await bulletLine.getAttribute('style')
  expect(style).toContain('margin-left')
})
