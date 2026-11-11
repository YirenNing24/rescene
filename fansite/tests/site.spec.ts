import { test, expect } from "@playwright/test";

// These run against the prerendered assets served by Wrangler, including hydration.
test("complete homepage is readable before JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "Five voices.",
  );
  await expect(page.locator(".member")).toHaveCount(5);
  await expect(page.locator(".album")).toHaveCount(5);
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    "https://remineph.online/",
  );
  const assets = await page
    .locator('script[type="module"][src^="/assets/"]')
    .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("src")));
  expect(assets).toHaveLength(1);
  await context.close();
});

test("members, collection persistence, filtering, search and favorite song", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await page.locator(".member").first().click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("heading", { name: /WONI/ })).toBeVisible();
  await dialog.getByRole("button", { name: "Save this photocard" }).click();
  await expect(
    dialog.getByRole("button", { name: "Saved to your collection" }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(dialog).not.toBeVisible();
  await page.getByRole("button", { name: /My collection/ }).click();
  await expect(dialog.locator(".collection-progress")).toContainText(
    "1 / 5 COLLECTED",
  );
  await page.keyboard.press("Escape");
  await page.reload();
  await page.getByRole("button", { name: /My collection/ }).click();
  await expect(dialog.locator(".collection-progress")).toContainText(
    "1 / 5 COLLECTED",
  );
  await dialog.locator(".collection-grid button").first().click();
  await expect(dialog.locator(".collection-progress")).toContainText(
    "0 / 5 COLLECTED",
  );
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Singles", exact: true }).click();
  await expect(page.locator(".album")).toHaveCount(1);
  await expect(page.locator(".album h3")).toHaveText("Dearest");
  await page.getByRole("button", { name: "Mini albums", exact: true }).click();
  await expect(page.locator(".album")).toHaveCount(4);
  await page.keyboard.press("Control+k");
  const input = page.getByRole("textbox", {
    name: "Search members and albums",
  });
  await expect(input).toBeFocused();
  await input.fill("minami");
  await expect(dialog.locator(".search-results button")).toHaveCount(1);
  await dialog.getByRole("button", { name: /MINAMI/ }).click();
  await expect(dialog.getByRole("heading", { name: /MINAMI/ })).toBeVisible();
  await page.keyboard.press("Escape");
  await page
    .locator(".poll-options")
    .getByRole("button", { name: "Glow Up" })
    .click();
  await expect(page.locator(".poll-note").first()).toContainText(
    "Your pick: Glow Up",
  );
  await page.reload();
  await expect(
    page.locator(".poll-options").getByRole("button", { name: "Glow Up" }),
  ).toHaveAttribute("aria-pressed", "true");
  expect(errors).toEqual([]);
});

test("quiz feedback, scoring and replay", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: /Take the fan quiz/ }).click();
  const dialog = page.getByRole("dialog");
  for (const [index, answer] of [
    "Five",
    "REMINE",
    "LOVE ATTACK",
    "Woni",
  ].entries()) {
    await dialog.getByRole("button", { name: new RegExp(answer) }).click();
    await expect(dialog.locator(".quiz-next")).toContainText(
      "You know your scene!",
    );
    await dialog
      .getByRole("button", {
        name: index === 3 ? "See my result" : "Next question",
      })
      .click();
  }
  await expect(dialog.locator(".quiz-result h2")).toHaveText("4 / 4");
  await dialog.getByRole("button", { name: "Play again" }).click();
  await expect(
    dialog.getByRole("heading", { name: "How many members make up RESCENE?" }),
  ).toBeVisible();
  await dialog.getByRole("button", { name: /Four/ }).click();
  await expect(dialog.locator(".quiz-choices .incorrect")).toContainText(
    "Four",
  );
  await expect(dialog.locator(".quiz-choices .correct")).toContainText("Five");
});

test("existing browser preferences survive migration", async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem("remine-cards", JSON.stringify(["woni", "minami"]));
    localStorage.setItem("remine-pick", "Runaway");
  });
  await page.goto("/");
  await page.getByRole("button", { name: /My collection/ }).click();
  await expect(page.locator(".collection-progress")).toContainText(
    "2 / 5 COLLECTED",
  );
  await page.keyboard.press("Escape");
  await expect(
    page.locator(".poll-options").getByRole("button", { name: "Runaway" }),
  ).toHaveAttribute("aria-pressed", "true");
});

test("desktop and mobile layout, navigation and screenshots", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.locator(".hero-photo img")).toBeVisible();
  await page.locator("img").evaluateAll((images) =>
    images.forEach((image) => {
      if (image instanceof HTMLImageElement) image.loading = "eager";
    }),
  );
  await expect
    .poll(() =>
      page
        .locator("img")
        .evaluateAll((images) =>
          images.every(
            (image) =>
              image instanceof HTMLImageElement &&
              image.complete &&
              image.naturalWidth > 0,
          ),
        ),
    )
    .toBe(true);
  await expect(page.locator("svg:empty")).toHaveCount(0);
  await page.screenshot({
    path: "../previews/fansite-solid-desktop.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    page.getByRole("button", { name: "Open navigation" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Open navigation" }).click();
  await expect(page.getByRole("navigation")).toBeVisible();
  await page
    .getByRole("navigation")
    .getByRole("link", { name: "Members", exact: true })
    .click();
  await expect(page.getByRole("navigation")).not.toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.getByRole("link", { name: "RESCENE home" }).click();
  await page.screenshot({
    path: "../previews/fansite-solid-mobile.png",
    fullPage: true,
  });
});
