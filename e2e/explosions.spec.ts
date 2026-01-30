import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

// Inject Tauri mocks before each test
test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('explosion particles appear when typing', async ({ page }) => {
  await page.goto('/')

  // Wait for CodeMirror to be ready
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Ensure explosions are enabled
  await page.evaluate(() => {
    localStorage.setItem('explosions-enabled', 'true')
  })

  // Reload to apply the setting
  await page.reload()
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click to focus the editor
  await page.locator('.cm-content').click()

  // Type a character
  await page.keyboard.type('H')

  // Wait a tiny bit for the particle to be created
  await page.waitForTimeout(100)

  // Explosion particles should appear
  const particles = page.locator('.explosion-particle')
  await expect(particles.first()).toBeVisible()

  // Take a screenshot showing the explosion
  await page.screenshot({ path: 'e2e/screenshots/explosion-particles.png' })
})

test('Cmd+E toggles explosions', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Mock the location.reload() function to avoid actual reload during test
  await page.evaluate(() => {
    // @ts-ignore
    window.location.reload = () => {
      console.log('Reload called but mocked')
    }
  })

  // Check initial state (explosions should be enabled by default)
  let explosionsEnabled = await page.evaluate(() => {
    return localStorage.getItem('explosions-enabled') !== 'false'
  })
  expect(explosionsEnabled).toBe(true)

  // Press Cmd+E to toggle explosions
  await page.keyboard.press('Meta+e')

  // Wait for status message
  await page.waitForTimeout(200)

  // Check that the state changed in localStorage
  explosionsEnabled = await page.evaluate(() => {
    return localStorage.getItem('explosions-enabled') !== 'false'
  })
  expect(explosionsEnabled).toBe(false)

  await page.screenshot({ path: 'e2e/screenshots/explosions-toggle.png' })
})

test('no particles appear when explosions are disabled', async ({ page }) => {
  await page.goto('/')

  // Wait for CodeMirror to be ready
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Disable explosions
  await page.evaluate(() => {
    localStorage.setItem('explosions-enabled', 'false')
  })

  // Reload to apply the setting
  await page.reload()
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click to focus the editor
  await page.locator('.cm-content').click()

  // Type several characters
  await page.keyboard.type('Hello')

  // Wait a bit
  await page.waitForTimeout(200)

  // No explosion particles should appear
  const particles = page.locator('.explosion-particle')
  await expect(particles).toHaveCount(0)

  await page.screenshot({ path: 'e2e/screenshots/no-explosions.png' })
})
