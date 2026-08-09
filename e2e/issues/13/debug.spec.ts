import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('debug: check if first-line-title class and styles are applied', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type a title
  await page.locator('.cm-content').click()
  await page.keyboard.type('My Important Note')
  await page.keyboard.press('Enter')
  await page.keyboard.type('Body content')

  await page.waitForTimeout(500)

  // Check if the first-line-title class exists
  const titleElement = page.locator('.first-line-title').first()
  await expect(titleElement).toBeVisible()

  // Get computed styles
  const textDecoration = await titleElement.evaluate((el) => {
    const styles = window.getComputedStyle(el)
    return {
      textDecoration: styles.textDecoration,
      textDecorationLine: styles.textDecorationLine,
      textDecorationColor: styles.textDecorationColor,
      textDecorationThickness: styles.textDecorationThickness,
      textUnderlineOffset: styles.textUnderlineOffset,
      fontSize: styles.fontSize,
      fontWeight: styles.fontWeight,
    }
  })

  console.log('Computed styles for .first-line-title:', textDecoration)
})
