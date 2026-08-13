#!/usr/bin/env python3
"""Visual verification v3 — tolerates the slow DDC debug boot by polling
for the login inputs, then enables semantics and drives the picker."""
import os

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOT = "/tmp/drp"
console_log = []


def shot(page, name):
    page.screenshot(path=f"{SHOT}/{name}.png", full_page=True)
    print(f"  📸 {name}.png")


def wait_for(page, locator_spec, timeout_ms=90000, what=""):
    import time
    start = time.time()
    while time.time() - start < timeout_ms / 1000:
        try:
            n = page.locator(locator_spec).count()
            if n > 0:
                return n
        except Exception:
            pass
        page.wait_for_timeout(2000)
    print(f"  !! timeout waiting for {what or locator_spec}")
    return 0


def dump_labels(page, tag, limit=35):
    labels = page.eval_on_selector_all(
        "flt-semantics[aria-label]",
        "els => els.filter(e => e.offsetParent !== null).map(e => "
        "(e.getAttribute('role')||'')+': '+(e.getAttribute('aria-label')||'').slice(0,55))",
    )
    print(f"  [{tag}] {len(labels)} visible labels:")
    for l in labels[:limit]:
        print(f"    - {l}")


def force_click_label(page, needle, timeout=8000):
    loc = page.locator(f'flt-semantics[aria-label*="{needle}"]').first
    loc.click(timeout=timeout, force=True)
    return loc


def nav(page, label):
    force_click_label(page, label)
    page.wait_for_timeout(7000)


def main():
    os.makedirs(SHOT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})

        def on_console(msg):
            t = msg.type
            text = msg.text
            if t in ("error", "warning") or "overflow" in text.lower():
                console_log.append(f"{t}: {text[:240]}")

        page.on("console", on_console)
        page.on("pageerror", lambda e: console_log.append(f"pageerror: {str(e)[:240]}"))

        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)

        # ── poll for the login fields (DDC boot can take ~20s) ───────
        n = wait_for(page, "input", what="login inputs")
        page.wait_for_timeout(4000)  # let both fields render
        n_inputs = page.locator("input").count()
        print(f"inputs after boot wait: {n_inputs}")
        shot(page, "v3-01-login")

        if n_inputs >= 2:
            page.locator("input").nth(0).fill("admin")
            page.locator("input").nth(1).fill("admin123")
            page.locator("input").nth(1).press("Enter")
        elif n_inputs == 1:
            page.locator("input").nth(0).fill("admin")
            page.keyboard.press("Tab")
            page.wait_for_timeout(800)
            page.keyboard.type("admin123")
            page.keyboard.press("Enter")
        else:
            print("!! no inputs found — cannot log in")
            browser.close()
            return

        page.wait_for_timeout(12000)
        shot(page, "v3-02-after-login")

        # ── enable semantics (DOM click, bypasses Playwright checks) ──
        for attempt in range(4):
            page.evaluate(
                "() => { const b = document.querySelector('flt-semantics-placeholder "
                "button') || document.querySelector('flt-semantics-placeholder');"
                " if (b) { b.click(); return true; } return false; }"
            )
            page.wait_for_timeout(2000)
            n_a = page.locator("flt-semantics[aria-label]").count()
            print(f"  semantics attempt {attempt + 1}: {n_a} aria nodes")
            if n_a > 5:
                break

        dump_labels(page, "dashboard")
        shot(page, "v3-03-dashboard")

        # ── open the dashboard pill popover ──────────────────────────
        try:
            force_click_label(page, "Previous period")
            page.wait_for_timeout(3000)
            print("pill opened")
        except Exception as e:
            print(f"pill open failed: {e}")
        dump_labels(page, "popover")
        shot(page, "v3-04-pill-open")

        # ── preset ───────────────────────────────────────────────────
        try:
            force_click_label(page, "Last 30 days")
            page.wait_for_timeout(3000)
            print("Last 30 days clicked")
            shot(page, "v3-05-preset-last30")
        except Exception as e:
            print(f"preset failed: {e}")

        # ── custom two-click range ───────────────────────────────────
        try:
            days = page.locator('flt-semantics[role="button"][aria-label*="August"]')
            print(f"August day nodes: {days.count()}")
            if days.count() > 5:
                days.nth(1).click(force=True)
                page.wait_for_timeout(1000)
                days.nth(days.count() - 1).click(force=True)
                page.wait_for_timeout(3000)
                print("custom range set")
                shot(page, "v3-06-custom-range")
        except Exception as e:
            print(f"custom range failed: {e}")

        # ── Reports > Sales Summary (no All dates) ───────────────────
        try:
            nav(page, "Reports")
            force_click_label(page, "Sales Summary")
            page.wait_for_timeout(8000)
            shot(page, "v3-07-sales-summary")
            try:
                force_click_label(page, "Previous period")
                page.wait_for_timeout(2500)
                n_all = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                print(f"Sales Summary 'All dates' present: {n_all} (want 0)")
                shot(page, "v3-08-sales-summary-popover")
            except Exception as e:
                print(f"sales summary popover failed: {e}")
        except Exception as e:
            print(f"reports nav failed: {e}")

        # ── Sales list (All dates + clear) ───────────────────────────
        try:
            nav(page, "Sales")
            shot(page, "v3-09-sales")
            try:
                force_click_label(page, "Previous period")
                page.wait_for_timeout(2500)
                n_all = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                print(f"Sales 'All dates' present: {n_all} (want ≥1)")
                shot(page, "v3-10-sales-popover")
            except Exception as e:
                print(f"sales popover failed: {e}")
        except Exception as e:
            print(f"sales nav failed: {e}")

        # ── Cash reconciliation (single-date) ────────────────────────
        try:
            nav(page, "Reports")
            force_click_label(page, "Cash Reconcil")
            page.wait_for_timeout(8000)
            shot(page, "v3-11-cash-recon")
            try:
                force_click_label(page, "Previous period")
                page.wait_for_timeout(2500)
                dump_labels(page, "cash-recon-popover")
                shot(page, "v3-12-cash-recon-popover")
            except Exception as e:
                print(f"cash recon popover failed: {e}")
        except Exception as e:
            print(f"cash recon nav failed: {e}")

        browser.close()

    print("\n=== CONSOLE ISSUES ===")
    if not console_log:
        print("(none)")
    for line in console_log:
        print("  " + line)


if __name__ == "__main__":
    main()
