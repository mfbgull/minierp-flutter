#!/usr/bin/env python3
"""Visual verification v5 — handles DDC cold reloads after each goto by
waiting long, re-enabling semantics per page, and dumping full labels."""
import os

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOT = "/tmp/drp"
OUT = "/tmp/drp/dumps.txt"
errors = []
dump_lines = []


def log(msg):
    dump_lines.append(msg)
    print(msg)


def shot(page, name):
    page.screenshot(path=f"{SHOT}/{name}.png", full_page=True)
    print(f"  📸 {name}.png")


def enable_semantics(page):
    for _ in range(4):
        page.evaluate(
            "() => { const b = document.querySelector('flt-semantics-placeholder "
            "button') || document.querySelector('flt-semantics-placeholder');"
            " if (b) { b.click(); return true; } return false; }"
        )
        page.wait_for_timeout(2000)
        if page.locator("flt-semantics[aria-label]").count() > 5:
            return True
    return False


def wait_and_boot(page, path, wait_s=26):
    page.goto(f"{BASE}{path}", wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(wait_s * 1000)
    ok = enable_semantics(page)
    if not ok:
        log(f"  !! semantics not enabled on {path}")
    return ok


def dump_labels(page, tag, limit=80):
    labels = page.eval_on_selector_all(
        "flt-semantics[aria-label]",
        "els => els.filter(e => e.offsetParent !== null).map(e => "
        "(e.getAttribute('role')||'')+': '+(e.getAttribute('aria-label')||'').slice(0,55))",
    )
    log(f"[{tag}] {len(labels)} visible labels:")
    for l in labels[:limit]:
        log(f"  - {l}")
    return labels


def click_label(page, needle, timeout=8000):
    page.locator(f'flt-semantics[aria-label*="{needle}"]').first.click(
        timeout=timeout, force=True
    )


def main():
    os.makedirs(SHOT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1900, "height": 1050})

        def on_console(msg):
            t = msg.type
            text = msg.text
            if t in ("error", "warning") or "overflow" in text.lower():
                errors.append(f"{t}: {text[:300]}")

        page.on("console", on_console)
        page.on("pageerror", lambda e: errors.append(f"pageerror: {str(e)[:300]}"))

        # ── login ────────────────────────────────────────────────────
        page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
        import time
        start = time.time()
        while time.time() - start < 100:
            if page.locator("input").count() >= 1:
                break
            page.wait_for_timeout(2000)
        page.wait_for_timeout(4000)
        n = page.locator("input").count()
        log(f"login inputs: {n}")
        if n >= 1:
            page.locator("input").nth(0).fill("admin")
            page.keyboard.press("Tab")
            page.wait_for_timeout(800)
            page.keyboard.type("admin123")
            page.keyboard.press("Enter")
        page.wait_for_timeout(15000)

        enable_semantics(page)
        dump_labels(page, "dashboard")
        shot(page, "v5-01-dashboard")

        # ── dashboard pill open ──────────────────────────────────────
        try:
            click_label(page, "Aug 10")
            page.wait_for_timeout(3000)
            log("dashboard pill opened")
        except Exception as e:
            log(f"pill open failed: {e}")
        dump_labels(page, "dash-popover")
        shot(page, "v5-02-dash-popover")

        # ── preset ───────────────────────────────────────────────────
        try:
            click_label(page, "Last 30 days")
            page.wait_for_timeout(3000)
            log("Last 30 days clicked")
            shot(page, "v5-03-preset-last30")
        except Exception as e:
            log(f"preset failed: {e}")

        # ── reopen + custom 2-day range ──────────────────────────────
        try:
            click_label(page, "Jul 15")
            page.wait_for_timeout(2000)
            log("reopened pill (Jul 15 range)")
        except Exception as e:
            log(f"reopen failed: {e}")
        try:
            days = page.locator('flt-semantics[role="button"][aria-label*="August"]')
            log(f"August day nodes: {days.count()}")
            if days.count() > 5:
                days.nth(1).click(force=True)
                page.wait_for_timeout(900)
                days.nth(days.count() - 1).click(force=True)
                page.wait_for_timeout(3000)
                log("custom range set")
                shot(page, "v5-04-custom")
        except Exception as e:
            log(f"custom range failed: {e}")

        # ── per-screen checks via direct URLs ────────────────────────
        for path, tag, expect_all_dates in [
            ("/reports/sales-summary", "sales-summary", False),
            ("/sales", "sales", True),
            ("/reports/cash-reconciliation", "cash-recon", False),
        ]:
            try:
                wait_and_boot(page, path)
                dump_labels(page, f"{tag}-screen", limit=30)
                shot(page, f"v5-05-{tag}")
                # open the pill (its label is a range like 'Aug 10–16, 2026'
                # or the single date 'Aug 13, 2026' on cash recon)
                try:
                    click_label(page, "Aug 1")
                    page.wait_for_timeout(3000)
                    log(f"{tag}: pill opened")
                except Exception:
                    try:
                        click_label(page, "Jul 1")
                        page.wait_for_timeout(3000)
                        log(f"{tag}: pill opened (Jul label)")
                    except Exception as e:
                        log(f"{tag}: pill open failed: {e}")
                n_all = page.locator(
                    'flt-semantics[role="button"][aria-label*="All dates"]'
                ).count()
                log(f"{tag}: 'All dates' preset present = {n_all} (expect "
                    f"{1 if expect_all_dates else 0})")
                dump_labels(page, f"{tag}-popover", limit=40)
                shot(page, f"v5-06-{tag}-popover")
            except Exception as e:
                log(f"{tag}: FAILED {e}")

        browser.close()

    log("\n=== CONSOLE ISSUES ===")
    if not errors:
        log("(none)")
    seen = set()
    for e in errors:
        key = e[:90]
        if key in seen:
            continue
        seen.add(key)
        log("-----")
        log(e)

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(dump_lines))
    print(f"\n(dump written to {OUT})")


if __name__ == "__main__":
    main()
