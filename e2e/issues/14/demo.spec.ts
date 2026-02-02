import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: checkbox green color on check', async ({ page }) => {
  test.slow()

  // Compact viewport - no sidebar, just the editor
  await page.setViewportSize({ width: 600, height: 450 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Create a task list
  await page.locator('.cm-content').click()
  await page.keyboard.type('My Tasks', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Add first task
  await page.keyboard.type('- [ ] Review pull requests', { delay: 40 })
  await page.waitForTimeout(800)

  await page.keyboard.press('Enter')
  await page.keyboard.type('Write documentation', { delay: 40 })
  await page.waitForTimeout(800)

  await page.keyboard.press('Enter')
  await page.keyboard.type('Fix bug in checkbox styling', { delay: 40 })
  await page.waitForTimeout(1000)

  // Check off the first task - watch it turn green!
  const checkboxes = page.locator('.checkbox-marker')
  await checkboxes.nth(0).click()
  await page.waitForTimeout(1200)

  // Check off the third task
  await checkboxes.nth(2).click()
  await page.waitForTimeout(1200)

  // Uncheck the first task
  await checkboxes.nth(0).click()
  await page.waitForTimeout(1000)

  // Check it again to show the green feedback
  await checkboxes.nth(0).click()
  await page.waitForTimeout(1500)
})
