#!/usr/bin/env python3
"""Visual verification of the date-range pill picker in the running
Flutter web app (http://127.0.0.1:8765). Logs in, enables the Flutter
semantics tree, then drives the pill across the dashboard, a report
screen, a list screen, and the cash-reconciliation single-date mode,
capturing screenshots and console errors at each step."""
import sys
from PIL import Image

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOT = "/tmp/drp"
console_log = []


def shot(page, name):
    page.screenshot(path=f"{SHOT}/{name}.png", full_page=True)
    print(f"  📸 {name}.png")


def click_label(page, needle, timeout=6000, role="button"):
    """Click the first semantics node whose aria-label contains needle."""
    loc = page.locator(
        f'flt-semantics[role="{role}"][aria-label*="{needle}"], '
        f'[aria-label*="{needle}"]'
    ).first
    loc.click(timeout=timeout)
    return loc


def nav_to(page, label):
    """Click a navigation rail item by its semantics label."""
    click_label(page, label, timeout=8000)
    page.wait_for_timeout(6000)


def main():
    import os
    os.makedirs(SHOT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})

        def on_console(msg):
            t = msg.type
            text = msg.text
            if t in ("error", "warning") or "overflow" in text.lower():
                console_log.append(f"{t}: {text[:280]}")

        page.on("console", on_console)
        page.on("pageerror", lambda e: console_log.append(f"pageerror: {str(e)[:280]}"))

        # ── 1. boot + login ──────────────────────────────────────────
        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(9000)
        shot(page, "01-login")

        inputs = page.locator("input")
        print(f"login inputs found: {inputs.count()}")
        if inputs.count() >= 2:
            inputs.nth(0).fill("admin")
            inputs.nth(1).fill("admin123")
            inputs.nth(1).press("Enter")
        page.wait_for_timeout(9000)
        shot(page, "02-after-login")

        # ── 2. enable Flutter semantics tree ─────────────────────────
        try:
            ph = page.locator("flt-semantics-placeholder")
            if ph.count():
                ph.first.click(timeout=5000)
                page.wait_for_timeout(2000)
                print("semantics enabled")
        except Exception as e:
            print(f"semantics enable skipped: {e}")

        labels = page.locator("flt-semantics[aria-label]").count()
        print(f"semantics nodes with aria-label: {labels}")
        shot(page, "03-dashboard")

        # ── 3. open the dashboard pill popover ───────────────────────
        try:
            click_label(page, "Previous period", timeout=8000)
            print("found pill (Previous period chevron)")
        except Exception as e:
            print(f"pill chevron not found by label: {e}")
            # fall back: click the first aria button with a date-like label
            try:
                page.locator(
                    'flt-semantics[role="button"][aria-label*="–"]'
                ).first.click(timeout=5000)
                print("pill clicked via date-label fallback")
            except Exception as e2:
                print(f"fallback click failed: {e2}")

        page.wait_for_timeout(2500)
        shot(page, "04-pill-open")

        # ── 4. pick a preset ─────────────────────────────────────────
        try:
            click_label(page, "Last 30 days", timeout=5000)
            print("Last 30 days preset clicked")
            page.wait_for_timeout(2500)
            shot(page, "05-preset-last30")
        except Exception as e:
            print(f"preset click failed: {e}")

        # ── 5. custom two-click range via day cells ──────────────────
        try:
            # Day cells carry labels from the Semantics builder
            # (e.g. "Thursday, August 13"). Click a day in the left
            # month, then a later day.
            days = page.locator('flt-semantics[role="button"][aria-label*="August"]')
            if days.count() > 5:
                days.nth(0).click(timeout=5000)
                page.wait_for_timeout(800)
                days.nth(days.count() - 1).click(timeout=5000)
                page.wait_for_timeout(2500)
                print(f"custom range clicked ({days.count()} Aug day nodes)")
                shot(page, "06-custom-range")
            else:
                print("not enough August day nodes for custom range")
        except Exception as e:
            print(f"custom range failed: {e}")

        # ── 6. Reports > Sales Summary (showAllDates: false) ─────────
        try:
            nav_to(page, "Reports")
            click_label(page, "Sales Summary", timeout=8000)
            page.wait_for_timeout(7000)
            shot(page, "07-sales-summary")
            # open the pill and verify no "All dates" preset
            try:
                click_label(page, "Previous period", timeout=6000)
                page.wait_for_timeout(2000)
                has_all_dates = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                print(f"Sales Summary popover 'All dates' present: {has_all_dates}")
                shot(page, "08-sales-summary-popover")
            except Exception as e:
                print(f"sales summary popover open failed: {e}")
        except Exception as e:
            print(f"reports nav failed: {e}")

        # ── 7. Sales list screen (showAllDates: true + clear) ────────
        try:
            nav_to(page, "Sales")
            page.wait_for_timeout(5000)
            shot(page, "09-sales")
        except Exception as e:
            print(f"sales nav failed: {e}")

        # ── 8. Cash reconciliation (single-date mode) ────────────────
        try:
            nav_to(page, "Reports")
            click_label(page, "Cash Reconcil", timeout=8000)
            page.wait_for_timeout(7000)
            shot(page, "10-cash-recon")
            try:
                click_label(page, "Previous period", timeout=6000)
                page.wait_for_timeout(2000)
                shot(page, "11-cash-recon-popover")
            except Exception as e:
                print(f"cash recon popover open failed: {e}")
        except Exception as e:
            print(f"cash recon nav failed: {e}")

        browser.close()

    print("\n=== CONSOLE ISSUES ===")
    if not console_log:
        print("(none)")
    for line in console_log:
        print("  " + line)


def detect_overflow_stripes():
    """Scan screenshots for Flutter's yellow/black overflow stripes."""
    import glob
    print("\n=== OVERFLOW STRIPE SCAN ===")
    any_hit = False
    for path in sorted(glob.glob(f"{SHOT}/*.png")):
        img = Image.open(path).convert("RGB")
        w, h = img.size
        # Sample pixels; overflow stripes are yellow (~R>200,G>170,B<90).
        hits = 0
        for y in range(0, h, 3):
            for x in range(0, w, 3):
                r, g, b = img.getpixel((x, y))
                if r > 200 and g > 150 and b < 100:
                    hits += 1
        if hits > 40:  # ignore tiny yellow accents (icons, chips)
            any_hit = True
            print(f"  {path}: {hits} yellow pixels (possible overflow)")
    if not any_hit:
        print("  no overflow stripes detected")


if __name__ == "__main__":
    main()
    detect_overflow_stripes()
