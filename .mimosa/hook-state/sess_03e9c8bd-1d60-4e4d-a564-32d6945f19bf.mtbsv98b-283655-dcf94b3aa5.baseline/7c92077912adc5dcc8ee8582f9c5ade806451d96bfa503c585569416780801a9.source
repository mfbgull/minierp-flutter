#!/usr/bin/env python3
"""Capture EVERY console message (full text, unfiltered) while opening the
pill popover — to surface the exception behind the red error screen."""
import os
import time

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
all_console = []


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})
        page.on(
            "console",
            lambda m: all_console.append(f"[{m.type}] {m.text}"),
        )
        page.on("pageerror", lambda e: all_console.append(f"[pageerror] {e}"))

        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
        start = time.time()
        while time.time() - start < 100 and page.locator("input").count() < 1:
            page.wait_for_timeout(2000)
        page.wait_for_timeout(4000)
        if page.locator("input").count() >= 1:
            page.locator("input").nth(0).fill("admin")
            page.keyboard.press("Tab")
            page.wait_for_timeout(800)
            page.keyboard.type("admin123")
            page.keyboard.press("Enter")
        page.wait_for_timeout(15000)

        # enable semantics
        for _ in range(4):
            page.evaluate(
                "() => { const b = document.querySelector('flt-semantics-placeholder "
                "button') || document.querySelector('flt-semantics-placeholder');"
                " if (b) { b.click(); return true; } return false; }"
            )
            page.wait_for_timeout(2000)
            if page.locator("flt-semantics[aria-label]").count() > 5:
                break

        n_before = len(all_console)
        print("console msgs before pill open:", n_before)

        # open the pill
        page.locator('flt-semantics[aria-label*="Aug 10"]').first.click(
            timeout=8000, force=True
        )
        page.wait_for_timeout(4000)
        page.screenshot(path="/tmp/drp/crash-01.png")

        page.wait_for_timeout(3000)
        n_after = len(all_console)
        print("console msgs after pill open:", n_after)
        print("\n===== NEW CONSOLE OUTPUT =====")
        for msg in all_console[n_before:]:
            print(msg)
        print("===== END =====")
        browser.close()


if __name__ == "__main__":
    main()
