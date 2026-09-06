import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

test.beforeEach(async ({ page }) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
});

test("a fresh page starts with the title caret and stays steady as writing begins", async ({
  page,
}) => {
  const cursor = page.locator(".cm-cursor-primary");
  const firstLine = page.locator(".cm-line").first();
  await page.evaluate(() => document.fonts.ready);
  await expect(cursor).toBeVisible();
  await expect(firstLine).toHaveCSS("font-size", "32px");
  const emptyCursor = await cursor.boundingBox();
  const emptyLine = await firstLine.boundingBox();
  expect(emptyCursor!.height).toBeGreaterThanOrEqual(32);
  await page.keyboard.type("A");
  // The first character must not grow the caret from body size to title size.
  // WebKit measures an empty BR a few pixels taller than the actual glyph.
  await expect
    .poll(async () => (await cursor.boundingBox())?.height)
    .toBeLessThanOrEqual(emptyCursor!.height);
  expect((await firstLine.boundingBox())!.height).toBe(emptyLine!.height);
  await page.keyboard.press("Enter");
  await expect(page.locator(".cm-line").nth(1)).toHaveCSS("font-size", "18px");
  await expect
    .poll(async () => (await cursor.boundingBox())?.height)
    .toBeLessThan(emptyCursor!.height);
  await page.keyboard.press("Meta+n");
  await expect(firstLine).toHaveText("");
  await expect
    .poll(async () => (await cursor.boundingBox())?.height)
    .toBeGreaterThanOrEqual(32);
});

test("shortcut reference opens from the keyboard and menu, then restores the selection", async ({
  page,
}, info) => {
  await page.keyboard.insertText("A quiet notebook\n\nKeep writing here");
  await page.keyboard.press("Shift+ArrowLeft");
  await page.keyboard.press("Meta+/");
  const dialog = page.getByRole("dialog", { name: "Keyboard shortcuts" });
  await expect(dialog).toBeVisible();
  await expect(page.locator(".cm-content")).toHaveText(
    "A quiet notebookKeep writing here",
  );
  await expect(dialog.getByText("New window", { exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("shortcuts.png") });
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await page.keyboard.insertText("!");
  await expect(page.locator(".cm-content")).toContainText("Keep writing her!");
  await page.evaluate(() => (window as any).__emit("menu-shortcuts"));
  await expect(dialog).toBeVisible();
  await page.keyboard.press("Meta+/");
  await expect(dialog).toHaveCount(0);
  await page.setViewportSize({ width: 400, height: 400 });
  await page.keyboard.press("Meta+/");
  await expect(dialog).toBeVisible();
  expect(await dialog.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(
    true,
  );
});

for (const kind of ["body", "title", "wrapped bullet"]) {
  test(`selection height stays steady across ${kind} line endings`, async ({
    page,
  }, info) => {
    if (kind === "wrapped bullet")
      await page.setViewportSize({ width: 480, height: 700 });
    const body =
      kind === "wrapped bullet"
        ? "* " + "A long thought with breathing room. ".repeat(8)
        : "I am the very model of a modern major general";
    await page.keyboard.insertText(
      "This rules\n\n" + body + "\n\nNext thought",
    );
    await page.keyboard.press("Meta+Home");
    if (kind !== "title") {
      await page.keyboard.press("ArrowDown");
      await page.keyboard.press("ArrowDown");
    }
    for (let i = 0; i < 5; i++) await page.keyboard.press("ArrowRight");
    for (let i = 0; i < 4; i++) await page.keyboard.press("Shift+ArrowRight");
    const first = page
      .locator(".drift-selectionLayer .cm-selectionBackground")
      .first();
    await expect(first).toBeVisible();
    const before = await first.boundingBox();
    // Include the newline or soft wrap, then part of the following row.
    await page.keyboard.press("Meta+Shift+ArrowRight");
    await page.keyboard.press("Shift+ArrowRight");
    await page.keyboard.press("Shift+ArrowRight");
    await expect
      .poll(async () => (await first.boundingBox())?.height)
      .toBe(before!.height);
    expect((await first.boundingBox())!.y).toBe(before!.y);
    await page.screenshot({ path: info.outputPath(`selection-${kind}.png`) });
    expect(await page.locator(".cm-content").innerText()).toContain(
      "This rules",
    );
  });
}

for (const indent of ["", "  "]) {
  test(`checklist shortcut puts new writing after the marker (${indent.length} spaces)`, async ({
    page,
  }) => {
    await page.keyboard.insertText("Checklist cursor\n\n" + indent);
    await page.keyboard.press("Meta+Shift+l");
    await page.keyboard.insertText("First task");
    await expect
      .poll(() =>
        page.evaluate(() =>
          (window as any).__mockFS.get("Checklist cursor.md"),
        ),
      )
      .toBe("Checklist cursor\n\n" + indent + "- [ ] First task");
    // Removing the marker should keep the cursor attached to the same text.
    await page.keyboard.press("Meta+Shift+l");
    await page.keyboard.insertText("!");
    await expect
      .poll(() =>
        page.evaluate(() =>
          (window as any).__mockFS.get("Checklist cursor.md"),
        ),
      )
      .toBe("Checklist cursor\n\n" + indent + "First task!");
  });
}

async function selectList(page: import("@playwright/test").Page, body: string) {
  await page.keyboard.insertText("List conversion\n\n" + body);
  await page.keyboard.press("Meta+Home");
  for (let i = 0; i < "List conversion\n\n".length; i++)
    await page.keyboard.press("ArrowRight");
  await page.keyboard.press("Meta+Shift+End");
}

const savedList = (page: import("@playwright/test").Page) =>
  page.evaluate(() => (window as any).__mockFS.get("List conversion.md"));

test("selected bullets convert to checklists and back without stacking markers", async ({
  page,
}) => {
  await selectList(page, "* First\n  - Nested\n+ Last");
  await page.keyboard.press("Meta+Shift+l");
  await expect
    .poll(() => savedList(page))
    .toBe("List conversion\n\n- [ ] First\n  - [ ] Nested\n- [ ] Last");
  await page.keyboard.press("Meta+Shift+8");
  await expect
    .poll(() => savedList(page))
    .toBe("List conversion\n\n* First\n  * Nested\n* Last");
  await page.keyboard.press("Meta+Shift+8");
  await expect
    .poll(() => savedList(page))
    .toBe("List conversion\n\nFirst\n  Nested\nLast");
});

test("mixed selected lists preserve checked items while converting other prefixes", async ({
  page,
}) => {
  await selectList(page, "- [x] Done\n  * Bullet\nPlain\n1. Numbered");
  await page.keyboard.press("Meta+Shift+l");
  await expect
    .poll(() => savedList(page))
    .toBe(
      "List conversion\n\n- [x] Done\n  - [ ] Bullet\n- [ ] Plain\n- [ ] Numbered",
    );
  await page.keyboard.press("Meta+Shift+l");
  await expect
    .poll(() => savedList(page))
    .toBe("List conversion\n\nDone\n  Bullet\nPlain\nNumbered");
});

test("Command Return checks the whole mixed selection and then unchecks it", async ({
  page,
}) => {
  await selectList(page, "- [ ] First\n  * [x] Done\nPlain text\n+ [ ] Last");
  await page.keyboard.press("Meta+Enter");
  await expect
    .poll(() => savedList(page))
    .toBe(
      "List conversion\n\n- [x] First\n  * [x] Done\nPlain text\n+ [x] Last",
    );
  // The native menu uses the same selection, including indented checkboxes.
  await page.evaluate(() => (window as any).__emit("menu-check"));
  await expect
    .poll(() => savedList(page))
    .toBe(
      "List conversion\n\n- [ ] First\n  * [ ] Done\nPlain text\n+ [ ] Last",
    );
  await page.keyboard.press("Meta+z");
  await expect
    .poll(() => savedList(page))
    .toBe(
      "List conversion\n\n- [x] First\n  * [x] Done\nPlain text\n+ [x] Last",
    );
});

test("checking a selection that ends at a line start leaves that next item alone", async ({
  page,
}) => {
  const selected = "- [ ] First\n  - [X] Second\n";
  await page.keyboard.insertText(
    "List conversion\n\n" + selected + "- [ ] Outside",
  );
  await page.keyboard.press("Meta+Home");
  for (let i = 0; i < "List conversion\n\n".length; i++)
    await page.keyboard.press("ArrowRight");
  for (let i = 0; i < selected.length; i++)
    await page.keyboard.press("Shift+ArrowRight");
  await page.keyboard.press("Meta+Enter");
  await expect
    .poll(() => savedList(page))
    .toBe("List conversion\n\n- [x] First\n  - [X] Second\n- [ ] Outside");
});
