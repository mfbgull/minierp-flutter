#!/usr/bin/env python3
"""Diagnose why the Flutter web app isn't rendering inputs/semantics."""
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1900, "height": 1050})
    console_msgs = []
    page.on("console", lambda m: console_msgs.append(f"{m.type}: {m.text[:200]}"))
    page.on("pageerror", lambda e: console_msgs.append(f"pageerror: {str(e)[:200]}"))

    page.goto(BASE, wait_until="domcontentloaded", timeout=60000)
    for wait in (3, 5, 10):
        page.wait_for_timeout(wait * 1000)
        print(f"\n--- after +{wait}s ---")
        print("title:", page.title())
        print(
            "canvas count:",
            page.locator("canvas").count(),
            "| flt-view:",
            page.locator("flt-view, flutter-view, flt-glass-pane").count(),
        )
        print(
            "inputs:",
            page.locator("input").count(),
            "| buttons:",
            page.locator("button").count(),
        )
        print(
            "placeholder:",
            page.locator("flt-semantics-placeholder").count(),
            "| aria nodes:",
            page.locator("flt-semantics[aria-label]").count(),
        )
        body_len = page.evaluate("() => document.body ? document.body.innerHTML.length : -1")
        print("body innerHTML length:", body_len)

    page.screenshot(path="/tmp/drp/probe-final.png", full_page=True)
    print("\n=== console (first 25) ===")
    for m in console_msgs[:25]:
        print(" ", m)
    print("=== console count:", len(console_msgs), "===")
    browser.close()
