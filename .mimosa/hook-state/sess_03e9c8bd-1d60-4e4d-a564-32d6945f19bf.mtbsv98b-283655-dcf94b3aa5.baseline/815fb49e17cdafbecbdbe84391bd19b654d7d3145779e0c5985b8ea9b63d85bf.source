#!/usr/bin/env python3
"""Visual verification of the date-range pill picker — v2.

Fixes from v1: the flt-semantics-placeholder is zero-sized, so Playwright
refuses its click; we force-enable the semantics tree with a DOM click,
and use force clicks on flt-semantics nodes (they report their own
positions). Also prints the on-screen semantics labels after each step so
failures are diagnosable."""
import os
import sys

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOT = "/tmp/drp"
console_log = []


def shot(page, name):
    page.screenshot(path=f"{SHOT}/{name}.png", full_page=True)
    print(f"  📸 {name}.png")


def dump_labels(page, tag):
    """Print up to 40 visible aria-labels — helps diagnose the DOM state."""
    labels = page.eval_on_selector_all(
        "flt-semantics[aria-label]",
        "els => els.filter(e => e.offsetParent !== null).map(e => "
        "(e.getAttribute('role')||'')+': '+(e.getAttribute('aria-label')||'').slice(0,60))",
    )
    print(f"  [{tag}] {len(labels)} visible labels:")
    for l in labels[:40]:
        print(f"    - {l}")


def force_click(page, needle, timeout=6000, role=None):
    """Force-click the first flt-semantics node whose label contains needle."""
    role_sel = f'[role="{role}"]' if role else ""
    loc = page.locator(f'flt-semantics{role_sel}[aria-label*="{needle}"]').first
    loc.click(timeout=timeout, force=True)
    return loc


def enable_semantics(page):
    for attempt in range(3):
        page.evaluate(
            "() => { const b = document.querySelector('flt-semantics-placeholder button')"
            " || document.querySelector('flt-semantics-placeholder');"
            " if (b) { b.click(); return true; } return false; }"
        )
        page.wait_for_timeout(1500)
        n = page.locator("flt-semantics[aria-label]").count()
        print(f"  semantics attempt {attempt + 1}: {n} aria-label nodes")
        if n > 5:
            return True
    return False


def main():
    os.makedirs(SHOT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})

        def on_console(msg):
            t = msg.type
            text = msg.text
            if t in ("error", "warning") or "overflow" in text.lower():
                console_log.append(f"{t}: {text[:260]}")

        page.on("console", on_console)
        page.on("pageerror", lambda e: console_log.append(f"pageerror: {str(e)[:260]}"))

        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(9000)
        shot(page, "v2-01-login")

        inputs = page.locator("input")
        print(f"login inputs: {inputs.count()}")
        if inputs.count() >= 2:
            inputs.nth(0).fill("admin")
            inputs.nth(1).fill("admin123")
            inputs.nth(1).press("Enter")
        page.wait_for_timeout(9000)
        shot(page, "v2-02-after-login")

        if not enable_semantics(page):
            print("!! semantics could not be enabled — aborting label flow")
            browser.close()
            return

        dump_labels(page, "dashboard")
        shot(page, "v2-03-dashboard")

        # ── open the dashboard pill popover ──────────────────────────
        try:
            force_click(page, "Previous period", role="button")
            page.wait_for_timeout(2500)
            print("pill opened")
        except Exception as e:
            print(f"pill open failed: {e}")
        dump_labels(page, "popover-open")
        shot(page, "v2-04-pill-open")

        # ── preset click ─────────────────────────────────────────────
        try:
            force_click(page, "Last 30 days", role="button")
            page.wait_for_timeout(2500)
            print("Last 30 days clicked")
            shot(page, "v2-05-preset-last30")
        except Exception as e:
            print(f"preset click failed: {e}")

        # ── custom two-click range ───────────────────────────────────
        try:
            days = page.locator(
                'flt-semantics[role="button"][aria-label*="August"]'
            )
            print(f"August day nodes: {days.count()}")
            if days.count() > 5:
                days.nth(1).click(force=True)
                page.wait_for_timeout(800)
                days.nth(days.count() - 1).click(force=True)
                page.wait_for_timeout(2500)
                print("custom range set")
                shot(page, "v2-06-custom-range")
        except Exception as e:
            print(f"custom range failed: {e}")

        # ── Reports > Sales Summary ──────────────────────────────────
        try:
            force_click(page, "Reports", role="button")
            page.wait_for_timeout(6000)
            force_click(page, "Sales Summary", role="button")
            page.wait_for_timeout(7000)
            shot(page, "v2-07-sales-summary")
            try:
                force_click(page, "Previous period", role="button")
                page.wait_for_timeout(2000)
                n_all = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                print(f"Sales Summary popover 'All dates' present: {n_all} (want 0)")
                shot(page, "v2-08-sales-summary-popover")
            except Exception as e:
                print(f"sales summary popover failed: {e}")
        except Exception as e:
            print(f"reports nav failed: {e}")

        # ── Sales list screen ────────────────────────────────────────
        try:
            force_click(page, "Sales", role="button")
            page.wait_for_timeout(6000)
            shot(page, "v2-09-sales")
            try:
                force_click(page, "Previous period", role="button")
                page.wait_for_timeout(2000)
                n_all = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                print(f"Sales popover 'All dates' present: {n_all} (want ≥1)")
                shot(page, "v2-10-sales-popover")
            except Exception as e:
                print(f"sales popover failed: {e}")
        except Exception as e:
            print(f"sales nav failed: {e}")

        # ── Cash reconciliation (single-date) ────────────────────────
        try:
            force_click(page, "Reports", role="button")
            page.wait_for_timeout(6000)
            force_click(page, "Cash Reconcil", role="button")
            page.wait_for_timeout(7000)
            shot(page, "v2-11-cash-recon")
            try:
                force_click(page, "Previous period", role="button")
                page.wait_for_timeout(2000)
                dump_labels(page, "cash-recon-popover")
                shot(page, "v2-12-cash-recon-popover")
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
