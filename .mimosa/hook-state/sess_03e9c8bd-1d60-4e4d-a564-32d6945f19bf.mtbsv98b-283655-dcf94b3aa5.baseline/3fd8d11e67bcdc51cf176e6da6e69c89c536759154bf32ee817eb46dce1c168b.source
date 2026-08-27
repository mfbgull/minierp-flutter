#!/usr/bin/env python3
"""Visual verification v4 — captures FULL console error text (to locate
the 217px RenderFlex overflow), interacts with the pill via its date
label, and navigates via direct GoRouter URLs."""
import os
import re

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOT = "/tmp/drp"
errors = []


def shot(page, name):
    page.screenshot(path=f"{SHOT}/{name}.png", full_page=True)
    print(f"  📸 {name}.png")


def wait_for_inputs(page, want=1, timeout_ms=90000):
    import time
    start = time.time()
    while time.time() - start < timeout_ms / 1000:
        n = page.locator("input").count()
        if n >= want:
            return n
        page.wait_for_timeout(2000)
    return 0


def dump_labels(page, tag, limit=45):
    labels = page.eval_on_selector_all(
        "flt-semantics[aria-label]",
        "els => els.filter(e => e.offsetParent !== null).map(e => "
        "(e.getAttribute('role')||'')+': '+(e.getAttribute('aria-label')||'').slice(0,55))",
    )
    print(f"  [{tag}] {len(labels)} visible labels:")
    for l in labels[:limit]:
        print(f"    - {l}")


def click_label(page, needle, timeout=8000):
    page.locator(f'flt-semantics[aria-label*="{needle}"]').first.click(
        timeout=timeout, force=True
    )


def open_pill(page):
    """Open the popover by clicking the pill's date label."""
    click_label(page, "Aug 10")
    page.wait_for_timeout(3000)


def main():
    os.makedirs(SHOT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})

        def on_console(msg):
            t = msg.type
            text = msg.text
            if t in ("error", "warning") or "overflow" in text.lower():
                errors.append(f"{t}: {text}")

        page.on("console", on_console)
        page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))

        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
        wait_for_inputs(page)
        page.wait_for_timeout(4000)
        n = page.locator("input").count()
        print(f"login inputs: {n}")
        if n >= 1:
            page.locator("input").nth(0).fill("admin")
            page.keyboard.press("Tab")
            page.wait_for_timeout(800)
            page.keyboard.type("admin123")
            page.keyboard.press("Enter")
        page.wait_for_timeout(12000)

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

        dump_labels(page, "dashboard")
        shot(page, "v4-01-dashboard")

        # ── open pill on the dashboard ───────────────────────────────
        try:
            open_pill(page)
            print("dashboard pill opened")
        except Exception as e:
            print(f"pill open failed: {e}")
        dump_labels(page, "dash-popover")
        shot(page, "v4-02-dash-pill-open")

        # ── preset click ─────────────────────────────────────────────
        try:
            click_label(page, "Last 30 days")
            page.wait_for_timeout(2500)
            print("Last 30 days clicked")
            shot(page, "v4-03-preset")
        except Exception as e:
            print(f"preset failed: {e}")

        # ── reopen + custom two-day range ────────────────────────────
        try:
            open_pill(page)
            days = page.locator('flt-semantics[role="button"][aria-label*="August"]')
            print(f"August day nodes: {days.count()}")
            if days.count() > 5:
                days.nth(1).click(force=True)
                page.wait_for_timeout(900)
                days.nth(days.count() - 1).click(force=True)
                page.wait_for_timeout(2500)
                print("custom range set")
                shot(page, "v4-04-custom")
        except Exception as e:
            print(f"custom range failed: {e}")

        # ── Sales Summary (direct URL; showAllDates false) ───────────
        for path, tag in [
            ("/reports/sales-summary", "sales-summary"),
            ("/sales", "sales"),
            ("/reports/cash-reconciliation", "cash-recon"),
        ]:
            try:
                page.goto(f"{BASE}{path}", wait_until="domcontentloaded", timeout=60000)
                page.wait_for_timeout(9000)
                shot(page, f"v4-05-{tag}")
                try:
                    open_pill(page)
                    n_all = page.locator(
                        'flt-semantics[role="button"][aria-label*="All dates"]'
                    ).count()
                    print(f"{tag}: 'All dates' preset present = {n_all}")
                    dump_labels(page, f"{tag}-popover", limit=18)
                    shot(page, f"v4-06-{tag}-popover")
                except Exception as e:
                    print(f"{tag} popover failed: {e}")
            except Exception as e:
                print(f"{tag} navigation failed: {e}")

        browser.close()

    print("\n=== FULL CONSOLE ISSUES ===")
    if not errors:
        print("(none)")
    seen = set()
    for e in errors:
        key = e[:120]
        if key in seen:
            continue
        seen.add(key)
        print("-----")
        print(e)
    print("-----")


if __name__ == "__main__":
    main()
