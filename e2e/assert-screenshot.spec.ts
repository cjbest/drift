/**
 * Tests for the assertScreenshot visual assertion system.
 *
 * These tests validate that assertScreenshot correctly identifies
 * both true positives and true negatives - catching both false
 * positives (saying yes when it should say no) and false negatives
 * (saying no when it should say yes).
 */
import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'
import { assertScreenshot } from './helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test.describe('assertScreenshot reliability', () => {

  test.describe('true positives - should pass', () => {

    test('detects visible text that exists', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()
      await page.locator('.cm-content').click()
      await page.keyboard.type('Hello World')

      const result = await assertScreenshot(page, 'the text "Hello World" is visible')
      expect(result.passed).toBe(true)
    })

    test('detects the editor is present', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()

      const result = await assertScreenshot(page, 'there is a text editor visible')
      expect(result.passed).toBe(true)
    })

    test('detects light theme (white background)', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()

      const result = await assertScreenshot(page, 'the background is white/light colored')
      expect(result.passed).toBe(true)
    })
  })

  test.describe('true negatives - should fail', () => {

    test('rejects text that does not exist', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()
      await page.locator('.cm-content').click()
      await page.keyboard.type('Hello World')

      const result = await assertScreenshot(page, 'the text "Goodbye Universe" is visible')
      expect(result.passed).toBe(false)
    })

    test('rejects Comic Sans when using system font', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()
      await page.locator('.cm-content').click()
      await page.keyboard.type('This is some sample text')

      const result = await assertScreenshot(page, 'the text is rendered in Comic Sans font')
      expect(result.passed).toBe(false)
    })

    test('rejects dark theme when in light theme', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()

      const result = await assertScreenshot(page, 'the background is dark/black colored')
      expect(result.passed).toBe(false)
    })

    test('rejects presence of non-existent UI elements', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()

      const result = await assertScreenshot(page, 'there is a red error banner at the top of the screen')
      expect(result.passed).toBe(false)
    })
  })

  test.describe('edge cases', () => {

    test('handles ambiguous assertions appropriately', async ({ page }) => {
      await page.goto('/')
      await expect(page.locator('.cm-editor')).toBeVisible()
      await page.locator('.cm-content').click()
      await page.keyboard.type('# Title')

      // This is somewhat ambiguous - "large" is subjective
      const result = await assertScreenshot(page, 'there is large bold text visible')
      // We expect this to pass since titles are larger and bold
      console.log(`Ambiguous assertion result: passed=${result.passed}, confidence=${result.confidence}, explanation=${result.explanation}`)
    })
  })
})
