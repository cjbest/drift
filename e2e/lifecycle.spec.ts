import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

for (const failure of [false, true]) {
  test(`Quit during startup ${
    failure
      ? "shows the recovered draft if saving fails"
      : "saves the recovered draft without showing a window"
  }`, async ({ page }) => {
    await page.addInitScript(
      previewMocks({ "Recovered.md": "Recovered\nold" }),
    );
    await page.addInitScript((failure) => {
      const w = window as any;
      w.__bootDelay = 500;
      w.__failSave = failure;
      const draft = {
        id: "recovered-id",
        path: "Recovered.md",
        baseline: "Recovered\nold",
        text: "Recovered\nnew",
      };
      localStorage.setItem(
        "notebook:/isolated/Notebook:draft:recovered-id",
        JSON.stringify(draft),
      );
      localStorage.setItem(
        "notebook:/isolated/Notebook:window:main",
        JSON.stringify({ id: draft.id, path: draft.path }),
      );
    }, failure);
    await page.goto("/");
    await expect
      .poll(() =>
        page.evaluate(() => (window as any).__events.has("prepare-quit")),
      )
      .toBe(true);
    await page.evaluate(() => (window as any).__emit("prepare-quit"));
    expect(await page.evaluate(() => (window as any).__quitAck)).toBe(false);
    if (failure) {
      await expect(page.getByRole("alert")).toContainText("stay open");
      await expect
        .poll(() => page.evaluate(() => (window as any).__presented))
        .toBe(true);
      expect(await page.evaluate(() => (window as any).__quitAck)).toBe(false);
      await expect(page.locator(".cm-content")).toContainText("new");
    } else {
      await expect
        .poll(() => page.evaluate(() => (window as any).__quitAck))
        .toBe(true);
      expect(
        await page.evaluate(() => (window as any).__mockFS.get("Recovered.md")),
      ).toBe("Recovered\nnew");
      expect(await page.evaluate(() => (window as any).__presented)).toBe(
        false,
      );
    }
  });
}

test("saved appearance paints before the application module and indexing starts after presentation", async ({
  page,
}) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(previewMocks());
  await page.addInitScript(() =>
    localStorage.setItem("appearance", JSON.stringify("light")),
  );
  let unblock!: () => void;
  const blocked = new Promise<void>((r) => (unblock = r));
  await page.route("**/src/index.tsx", async (route) => {
    await blocked;
    await route.continue();
  });
  await page.goto("/", { waitUntil: "commit" });
  await expect
    .poll(() =>
      page.evaluate(
        () => getComputedStyle(document.documentElement).backgroundColor,
      ),
    )
    .toBe("rgb(250, 247, 240)");
  expect(await page.locator(".cm-editor").count()).toBe(0);
  unblock();
  await expect
    .poll(() => page.evaluate(() => (window as any).__presented))
    .toBe(true);
  await expect
    .poll(() =>
      page.evaluate(() => (window as any).__commands.includes("list_notes")),
    )
    .toBe(true);
  const commands = await page.evaluate(
    () => (window as any).__commands as string[],
  );
  expect(commands.indexOf("window_ready")).toBeLessThan(
    commands.indexOf("list_notes"),
  );
});

test("a quit cancelled by another window allows a later quit", async ({
  page,
}) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  await expect
    .poll(() => page.evaluate(() => (window as any).__presented))
    .toBe(true);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect
    .poll(() => page.evaluate(() => (window as any).__quitAck))
    .toBe(true);
  await page.evaluate(() => {
    (window as any).__emit("quit-cancelled");
    (window as any).__quitAck = false;
  });
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect
    .poll(() => page.evaluate(() => (window as any).__quitAck))
    .toBe(true);
});

test("permission denied while restoring a note presents a useful retry and opens after access returns", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nKeep this writing intact." }));
  await page.addInitScript(() => {
    (window as any).__failRead = true;
    localStorage.setItem(
      "notebook:/isolated/Notebook:window:main",
      JSON.stringify({ path: "Work.md", id: "remembered-work" }),
    );
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.getByRole("alert")).toContainText("permission");
  await expect(page.getByRole("button", { name: "Retry opening" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Retry save" })).toHaveCount(0);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem("notebook:/isolated/Notebook:window:main")!))).toEqual({ path: "Work.md", id: "remembered-work" });
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);

  await page.evaluate(() => { (window as any).__failRead = false; });
  await page.getByRole("button", { name: "Retry opening" }).click();
  await expect(page.locator(".cm-content")).toContainText("Keep this writing intact.");
  await expect(page.getByRole("alert")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  expect(await page.evaluate(() => Object.fromEntries((window as any).__mockFS))).toEqual({ "Work.md": "Work\nKeep this writing intact." });
});

test("quitting after permission denial preserves the remembered note for the next launch", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nKeep this writing intact." }));
  await page.addInitScript(() => {
    (window as any).__failRead = true;
    const remembered = JSON.stringify({ path: "Work.md", id: "remembered-work" });
    localStorage.setItem("notebook:/isolated/Notebook:window:main", remembered);
    localStorage.setItem("notebook:/isolated/Notebook:last-note", remembered);
  });
  await page.goto("/");
  await expect(page.getByRole("button", { name: "Retry opening" })).toBeVisible();
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  for (const key of ["window:main", "last-note"]) {
    expect(await page.evaluate((key) => JSON.parse(localStorage.getItem("notebook:/isolated/Notebook:" + key)!), key)).toEqual({ path: "Work.md", id: "remembered-work" });
  }
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("a denied catalogue refresh retains known notes and retries reading without saving", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nImportant writing", "Other.md": "Other\nAnother thought" }));
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await page.evaluate(() => (window as any).__emit("menu-open-note"));
  await expect(page.getByRole("option")).toHaveCount(2);
  await page.evaluate(() => {
    (window as any).__failList = true;
    window.dispatchEvent(new Event("focus"));
  });
  await expect(page.getByRole("alert")).toContainText("permission");
  await expect(page.getByRole("option")).toHaveCount(2);
  await expect(page.getByRole("button", { name: "Retry save" })).toHaveCount(0);
  await page.evaluate(() => { (window as any).__failList = false; });
  await page.getByRole("button", { name: "Retry opening" }).click();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.getByRole("option")).toHaveCount(2);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("initial catalogue permission denial is not presented as an empty notebook", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nImportant writing" }));
  await page.addInitScript(() => { (window as any).__failList = true; });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.getByRole("alert")).toContainText("permission");
  await page.evaluate(() => (window as any).__emit("menu-open-note"));
  await expect(page.getByRole("dialog", { name: "Open a note" })).toBeVisible();
  await expect(page.getByText("Your next thought starts here.", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Retry save" })).toHaveCount(0);
  await page.evaluate(() => { (window as any).__failList = false; });
  await page.getByRole("button", { name: "Retry opening" }).click();
  await expect(page.getByRole("option")).toHaveCount(1);
  await expect(page.getByRole("alert")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("a slow access decision presents the window before the saved note finishes opening", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nKeep this writing intact." }));
  await page.addInitScript(() => {
    (window as any).__readDelay = 2000;
    localStorage.setItem(
      "notebook:/isolated/Notebook:window:main",
      JSON.stringify({ path: "Work.md", id: "remembered-work" }),
    );
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.getByText("Opening your notebook…", { exact: true })).toBeVisible();
  await expect(page.locator(".cm-editor")).toHaveCount(0);
  await expect(page.locator(".cm-content")).toContainText("Keep this writing intact.");
  await expect(page.getByText("Opening your notebook…", { exact: true })).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("background refresh does not change the note being retried after a failed open", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nCurrent writing", "Other.md": "Other\nThe requested note" }));
  await page.addInitScript(() => {
    localStorage.setItem(
      "notebook:/isolated/Notebook:window:main",
      JSON.stringify({ path: "Work.md", id: "remembered-work" }),
    );
  });
  await page.goto("/");
  await expect(page.locator(".cm-content")).toContainText("Current writing");
  await page.evaluate(() => (window as any).__emit("menu-open-note"));
  await expect(page.getByRole("option")).toHaveCount(1);
  await page.evaluate(() => { (window as any).__failRead = true; });
  await page.locator('.quick-open-item[data-path="Other.md"]').click();
  await expect(page.getByRole("button", { name: "Retry opening" })).toBeVisible();
  const readCount = await page.evaluate(() => (window as any).__commands.filter((cmd: string) => cmd === "read_note").length);
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await expect.poll(() => page.evaluate(() => (window as any).__commands.filter((cmd: string) => cmd === "read_note").length)).toBeGreaterThan(readCount);
  await page.evaluate(() => { (window as any).__failRead = false; });
  await page.getByRole("button", { name: "Retry opening" }).click();
  await expect(page.locator(".cm-content")).toContainText("The requested note");
  await expect(page.getByRole("alert")).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("new windows do not recover or save another live window's drafts", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nSaved writing" }));
  await page.addInitScript(() => {
    const w = window as any;
    w.__TAURI_INTERNALS__.metadata.currentWindow.label = "drift-new-window";
    w.__TAURI_INTERNALS__.metadata.currentWebview.label = "drift-new-window";
    const draft = {
      id: "live-window-draft",
      path: "Work.md",
      baseline: "Work\nSaved writing",
      text: "Work\nWriting still in another window",
    };
    w.__recoveryDrafts = [{ ...draft, text: "Work\nOlder disk draft" }];
    localStorage.setItem("notebook:/isolated/Notebook:draft:" + draft.id, JSON.stringify(draft));
    localStorage.setItem("notebook:/isolated/Notebook:window:main", JSON.stringify({ id: draft.id, path: draft.path }));
    localStorage.setItem("notebook:/isolated/Notebook:last-note", JSON.stringify({ id: draft.id, path: draft.path }));
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.locator(".cm-content")).toHaveText("");
  await expect(page.getByText("Recovered unfinished writing from your last session.", { exact: true })).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  expect(await page.evaluate(() => (window as any).__mockFS.get("Work.md"))).toBe("Work\nSaved writing");
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem("notebook:/isolated/Notebook:draft:live-window-draft")!).text)).toBe("Work\nWriting still in another window");
});

test("main startup still recovers browser and disk drafts from previous windows", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nSaved writing", "Other.md": "Other\nSaved writing" }));
  await page.addInitScript(() => {
    const w = window as any;
    const work = { id: "work-draft", path: "Work.md", baseline: "Work\nSaved writing", text: "Work\nOlder disk draft" };
    const other = { id: "other-draft", path: "Other.md", baseline: "Other\nSaved writing", text: "Other\nRecovered from disk" };
    w.__recoveryDrafts = [work, other];
    localStorage.setItem("notebook:/isolated/Notebook:draft:" + work.id, JSON.stringify({ ...work, text: "Work\nLatest browser draft" }));
    localStorage.setItem("notebook:/isolated/Notebook:window:main", JSON.stringify({ id: work.id, path: work.path }));
  });
  await page.goto("/");
  await expect(page.locator(".cm-content")).toContainText("Latest browser draft");
  await expect(page.getByText("Recovered unfinished writing from your last session.", { exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => (window as any).__mockFS.get("Other.md"))).toBe("Other\nRecovered from disk");
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  expect(await page.evaluate(() => Object.fromEntries((window as any).__mockFS))).toEqual({ "Work.md": "Work\nLatest browser draft", "Other.md": "Other\nRecovered from disk" });
});

test("a recreated main window does not import live drafts after recovery was already claimed", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nSaved writing", "Other.md": "Other\nSaved writing" }));
  await page.addInitScript(() => {
    const w = window as any;
    w.__restoreDrafts = false;
    const draft = { id: "live-secondary-draft", path: "Other.md", baseline: "Other\nSaved writing", text: "Other\nWriting in a minimized window" };
    w.__recoveryDrafts = [draft];
    localStorage.setItem("notebook:/isolated/Notebook:draft:" + draft.id, JSON.stringify(draft));
    localStorage.setItem("notebook:/isolated/Notebook:window:main", JSON.stringify({ id: "closed-main-session", path: "Work.md" }));
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.locator(".cm-content")).toContainText("Work");
  await expect(page.locator(".cm-content")).toContainText("Saved writing");
  await expect(page.getByText("Recovered unfinished writing from your last session.", { exact: true })).toHaveCount(0);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect.poll(() => page.evaluate(() => (window as any).__quitAck)).toBe(true);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem("notebook:/isolated/Notebook:draft:live-secondary-draft")!).text)).toBe("Other\nWriting in a minimized window");
  expect(await page.evaluate(() => Object.fromEntries((window as any).__mockFS))).toEqual({ "Work.md": "Work\nSaved writing", "Other.md": "Other\nSaved writing" });
});

test("granting access restores the catalogue without waiting for an unavailable previous note", async ({ page }) => {
  await page.addInitScript(previewMocks({ "Work.md": "Work\nExisting writing" }));
  await page.addInitScript(() => {
    (window as any).__failList = true;
    localStorage.setItem("notebook:/isolated/Notebook:window:main", JSON.stringify({ id: "old-session", path: "Missing.md" }));
  });
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await expect(page.getByRole("alert")).toContainText("permission");
  await page.evaluate(() => (window as any).__emit("menu-open-note"));
  await expect(page.getByRole("dialog", { name: "Open a note" })).toBeVisible();
  await page.evaluate(() => {
    const w = window as any;
    w.__failList = false;
    w.__readDelay = 2000;
    w.__emit("notebook-access-granted");
  });
  await expect(page.getByRole("option")).toHaveCount(1, { timeout: 1000 });
  await expect(page.getByRole("option")).toContainText("Work");
  await expect(page.getByRole("alert")).toContainText("Missing file");
  await expect(page.getByRole("option")).toHaveCount(1);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});
