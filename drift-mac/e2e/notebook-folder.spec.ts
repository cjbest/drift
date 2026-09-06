import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

const welcome = "Drift\n\nStart writing. Your notes save automatically.\n\n⌘ N — New note\n⌘ P — Find a note\n⌘ / — All shortcuts\n";

test("fresh onboarding presents before folder access and opens the intro ready for typing at its end", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Drift.md": welcome }));
  await page.addInitScript(() => {
    (window as any).__initializeNotebook = true;
    (window as any).__initialNote = "Drift.md";
    (window as any).__initializeDelay = 1200;
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.locator(".cm-content")).toHaveCount(0);
  await page.keyboard.type("Typing during the access decision");
  await page.evaluate(() => (window as any).__emit("menu-new-note"));
  await expect(page.locator(".cm-content")).toContainText("Start writing. Your notes save automatically.");
  await expect.poll(() => page.evaluate(() => (window as any).__initialNoteAcknowledged)).toBe(true);
  const commands = await page.evaluate(() => (window as any).__commands as string[]);
  expect(commands.indexOf("window_ready")).toBeLessThan(commands.indexOf("initialize_notebook"));
  await page.keyboard.type("My first thought");
  await expect.poll(() => page.evaluate(() => (window as any).__mockFS.get("Drift.md"))).toBe(welcome + "My first thought");
});

test("denied first-run folder access keeps retry controls usable and never exposes a replaceable draft", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Drift.md": welcome }));
  await page.addInitScript(() => {
    (window as any).__initializeNotebook = true;
    (window as any).__initialNote = "Drift.md";
    (window as any).__failInitialize = true;
  });
  await page.goto("/");
  await expect(page.getByRole("alert")).toContainText("permission");
  await expect(page.getByRole("button", { name: "Retry opening" })).toBeEnabled();
  await expect(page.locator(".cm-content")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  await page.evaluate(() => { (window as any).__failInitialize = false; });
  await page.getByRole("button", { name: "Retry opening" }).click();
  await expect(page.locator(".cm-content")).toContainText("Start writing.");
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("quitting during first-run access does not activate or save the delayed intro", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Drift.md": welcome }));
  await page.addInitScript(() => {
    (window as any).__initializeNotebook = true;
    (window as any).__initialNote = "Drift.md";
    (window as any).__initializeDelay = 700;
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__commands.includes("initialize_notebook"))).toBe(true);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  await expect(page.locator(".cm-content")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  expect(await page.evaluate(() => (window as any).__initialNoteAcknowledged)).toBeUndefined();
});

test("cancelled quit resumes onboarding after a delayed initialization completed while leaving", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Drift.md": welcome }));
  await page.addInitScript(() => {
    (window as any).__initializeNotebook = true;
    (window as any).__initialNote = "Drift.md";
    (window as any).__initializeDelay = 400;
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__commands.includes("initialize_notebook"))).toBe(true);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__initializeCompletions)).toBe(1);
  await expect(page.locator(".cm-content")).toHaveCount(0);
  await page.evaluate(() => (window as any).__emit("quit-cancelled"));
  await expect(page.locator(".cm-content")).toContainText("Start writing.");
  await expect.poll(() => page.evaluate(() => (window as any).__initialNoteAcknowledged)).toBe(true);
  await expect(page.locator(".app")).not.toHaveAttribute("inert");
});

test("changing notebooks waits for the final save and stops new edits during the switch", async ({ page }) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await expect(editor).toBeVisible();
  await editor.fill("Travel\nKeep these plans in the original notebook.");
  await page.evaluate(() => {
    (window as any).__delay = 900;
    (window as any).__emit("prepare-quit");
  });
  await expect(page.locator(".app")).toHaveAttribute("inert", "");
  expect(await page.evaluate(() => (window as any).__quitAck)).toBe(false);
  await page.keyboard.type("Extra typing");
  await page.evaluate(() => (window as any).__emit("menu-new-note"));
  await expect(editor).toContainText("Keep these plans in the original notebook.");
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  expect(await page.evaluate(() => Object.fromEntries((window as any).__mockFS))).toEqual({
    "Travel.md": "Travel\nKeep these plans in the original notebook.",
  });
});

test("a failed save cancels a notebook switch and makes the existing draft editable again", async ({ page }) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  const editor = page.locator(".cm-content");
  await expect(editor).toBeVisible();
  await editor.fill("Unsaved\nDo not lose this.");
  await page.evaluate(() => {
    (window as any).__failSave = true;
    (window as any).__emit("prepare-quit");
  });
  await expect(page.getByRole("alert")).toContainText("stay open");
  await expect(page.locator(".app")).not.toHaveAttribute("inert");
  expect(await page.evaluate(() => (window as any).__quitAck)).toBe(false);
  await editor.fill("Unsaved\nStill here and editable.");
  await page.evaluate(() => { (window as any).__failSave = false; });
  await page.getByRole("button", { name: "Retry save" }).click();
  await expect.poll(() => page.evaluate(() => (window as any).__mockFS.get("Unsaved.md"))).toBe("Unsaved\nStill here and editable.");
});

test("a folder or configuration error leaves the current notebook open", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Current.md": "Current\nExisting notes" }));
  await page.addInitScript(() => localStorage.setItem(
    "notebook:/isolated/Notebook:window:main",
    JSON.stringify({ path: "Current.md", id: "current" }),
  ));
  await page.goto("/");
  await expect(page.locator(".cm-content")).toContainText("Existing notes");
  await page.evaluate(() => {
    (window as any).__emit("quit-cancelled");
    (window as any).__emit("notebook-switch-failed", "Could not change notebooks. Your current notebook is still open: disk unavailable");
  });
  await expect(page.getByRole("alert")).toContainText("current notebook is still open");
  await expect(page.locator(".cm-content")).toContainText("Existing notes");
  await expect(page.locator(".app")).not.toHaveAttribute("inert");
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});
