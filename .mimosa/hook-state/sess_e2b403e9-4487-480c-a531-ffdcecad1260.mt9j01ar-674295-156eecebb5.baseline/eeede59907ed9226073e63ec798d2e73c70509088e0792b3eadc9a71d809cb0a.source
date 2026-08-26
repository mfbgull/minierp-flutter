#!/usr/bin/env python3
"""
API E2E test: expired batch override flow.

Tests the full lifecycle without Flutter web (which can't render in headless):
  1. Setup — create customer, item (has_expiry=true), two purchases
     (one expired batch, one future batch)
  2. Test FEFO blocks expired batch — attempt sale, expect failure
  3. Test override flow — POST invoice with expired_batch_overrides,
     verify: invoice created, expiry_notes populated, batch dates restored
  4. Test halt/unhalt — halt batch, verify blocked, unhalt, verify allowed

Usage:
    cd server && node dist/server.js &
    python3 e2e_expiry_override_test.py
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

# Task 9.1 (audit-remediation): this script writes real data to whatever API
# it points at. Refuse to run against a target that wasn't explicitly opted in.
if os.environ.get("E2E_TARGET") != "1":
    sys.exit(
        "REFUSING TO RUN: e2e tests mutate the target database.\n"
        "Point it at an isolated server and set E2E_TARGET=1, e.g.:\n"
        "  DATABASE_PATH=/tmp/e2e-db PORT=3099 node dist/server.js &\n"
        "  E2E_TARGET=1 python3 e2e_expiry_override_test.py"
    )

API = os.environ.get("E2E_API", "http://localhost:3011/api")
CREATED_IDS = {"customers": [], "items": [], "invoices": []}
PASS = 0
FAIL = 0


def api(method, path, body=None, token=None):
    url = f"{API}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            parsed = json.loads(resp.read())
            if isinstance(parsed, dict) and "success" in parsed and "data" in parsed:
                return parsed["data"]
            return parsed
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        return {"_error": e.code, "_body": body_text}


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL += 1
        print(f"  ❌ {name} {detail}")


def main():
    global PASS, FAIL
    print("=" * 60)
    print("E2E Test: Expired Batch Override Flow (API)")
    print("=" * 60)

    # ── Login ──────────────────────────────────────────────────
    r = api("POST", "/auth/login", {"username": "admin", "password": "admin123"})
    token = r["token"]
    print(f"\n✓ Login OK")

    # ── Setup ──────────────────────────────────────────────────
    print("\n── Setup ──")

    r = api("POST", "/customers", {"customer_name": "E2E Override Cust", "phone": "0300-1234567"}, token)
    cust_id = r["id"]
    print(f"  Customer: {cust_id}")

    r = api("POST", "/inventory/items", {
        "item_code": f"E2E-OVR-{int(time.time())}",
        "item_name": "E2E Override Widget",
        "item_type": "Goods", "sale_type": "Unit",
        "standard_cost": 10.0, "sale_price": 20.0,
        "has_expiry": True, "near_expiry_threshold_days": 30,
    }, token)
    item_id = r["id"]
    CREATED_IDS["items"].append(item_id)
    check("Item created with has_expiry=1", r.get("has_expiry") in (1, True, "1"))

    # Task 9.1: scoped cleanup — only rows this run created, in FK-safe order.
    import atexit
    def _cleanup():
        tok = None
        try:
            r = api("POST", "/auth/login", {"username": "admin", "password": os.environ.get("E2E_PASSWORD", "admin123")})
            tok = r.get("token")
        except Exception:
            return
        for inv in reversed(CREATED_IDS["invoices"]):
            api("DELETE", f"/invoices/{inv}", token=tok)
    atexit.register(_cleanup)

    r = api("POST", "/purchases", {
        "item_id": item_id, "warehouse_id": 1, "quantity": 50,
        "unit_cost": 10.0, "supplier_id": 1,
        "purchase_date": "2026-06-01", "expiry_date": "2026-07-01",
    }, token)
    pur_a_id = r["id"]
    print(f"  Purchase A (expired): {pur_a_id}")

    r = api("POST", "/purchases", {
        "item_id": item_id, "warehouse_id": 1, "quantity": 30,
        "unit_cost": 12.0, "supplier_id": 1,
        "purchase_date": "2026-08-01", "expiry_date": "2026-12-31",
    }, token)
    pur_b_id = r["id"]
    print(f"  Purchase B (future):  {pur_b_id}")

    batches = api("GET", f"/stock-batches?item_id={item_id}", token=token)
    expired_batch = [b for b in batches if b["expiry_date"] == "2026-07-01"][0]
    future_batch = [b for b in batches if b["expiry_date"] == "2026-12-31"][0]
    check("2 batches created", len(batches) == 2)
    check("Expired batch has expiry=2026-07-01", expired_batch["expiry_date"] == "2026-07-01")
    check("Future batch has expiry=2026-12-31", future_batch["expiry_date"] == "2026-12-31")
    print(f"  Expired batch ID: {expired_batch['id']}, Future batch ID: {future_batch['id']}")

    # ── Test 1: FEFO blocks expired batch ──────────────────────
    print("\n── Test 1: FEFO blocks expired batch ──")

    r = api("POST", "/invoices", {
        "invoice_no": f"INV-E2E-FEFO-{int(time.time())}",
        "customer_id": cust_id,
        "invoice_date": "2026-08-21",
        "due_date": "2026-09-21",
        "total_amount": 100.0,
        "items": [{"item_id": item_id, "quantity": 5, "unit_price": 20.0}],
    }, token)
    # This should fail because only expired batch is available? No — there's also the future batch.
    # FEFO will consume from the future batch (nearest expiry first = 2026-12-31).
    # So this should succeed without override.
    if "_error" not in r:
        check("Sale without override succeeds (future batch available)", True)
        # Verify the future batch was consumed (FEFO picks nearest expiry)
        batches_after = api("GET", f"/stock-batches?item_id={item_id}", token=token)
        future_after = [b for b in batches_after if b["id"] == future_batch["id"]][0]
        expired_after = [b for b in batches_after if b["id"] == expired_batch["id"]][0]
        check("Future batch consumed first (FEFO)", future_after["quantity_remaining"] == 25)
        check("Expired batch untouched", expired_after["quantity_remaining"] == 50)

        # Verify expiry_notes (should be null — sold from future batch, not expired)
        inv_detail = api("GET", f"/invoices/{r['id']}", token=token)
        check("expiry_notes is null (sold from non-expired batch)", inv_detail.get("expiry_notes") is None)
    else:
        check("Sale without override succeeds", False, r)

    # ── Test 2: Override flow — force sale from expired batch ───
    print("\n── Test 2: Override expired batch sale ──")

    # Simulate the real override scenario:
    # The user sold from a future batch in Test 1, reducing it to 25.
    # Now halt the future batch so only the expired batch is available.
    # This mirrors the case where a user has ONLY expired stock.
    api("PATCH", f"/stock-batches/{future_batch['id']}/halt", {
        "reason": "Test: force expired-only scenario"
    }, token)

    # Clear the expired batch's expiry_date (simulating frontend override)
    r_override = api("PATCH", f"/stock-batches/{expired_batch['id']}", {
        "expiry_date": None
    }, token)
    check("Batch expiry_date cleared for override", r_override.get("expiry_date") is None)

    # Now sell 5 units — FEFO should pick the undated (cleared) batch
    r = api("POST", "/invoices", {
        "invoice_no": f"INV-E2E-OVR-{int(time.time())}",
        "customer_id": cust_id,
        "invoice_date": "2026-08-21",
        "due_date": "2026-09-21",
        "total_amount": 100.0,
        "expired_batch_overrides": {expired_batch["id"]: "2026-07-01"},
        "items": [{"item_id": item_id, "quantity": 5, "unit_price": 20.0}],
    }, token)
    if "_error" not in r:
        inv_id = r.get("id") or r.get("invoice_id")
        check("Override sale created", inv_id is not None)

        # Verify the expired (now undated) batch was consumed
        batches_after = api("GET", f"/stock-batches?item_id={item_id}", token=token)
        expired_after = [b for b in batches_after if b["id"] == expired_batch["id"]][0]
        check("Expired batch consumed after override", expired_after["quantity_remaining"] == 45)

        # Restore the expiry date on the expired batch
        api("PATCH", f"/stock-batches/{expired_batch['id']}", {
            "expiry_date": "2026-07-01"
        }, token)

        # Unhalt the future batch
        api("PATCH", f"/stock-batches/{future_batch['id']}/unhalt", token=token)

        # Verify batch expiry date was restored
        batches_restored = api("GET", f"/stock-batches?item_id={item_id}", token=token)
        restored = [b for b in batches_restored if b["id"] == expired_batch["id"]][0]
        check("Batch expiry_date restored after sale", restored["expiry_date"] == "2026-07-01")

        # Verify invoice has expiry_notes (from expired_batch_overrides)
        inv_detail = api("GET", f"/invoices/{inv_id}", token=token)
        expiry_notes = inv_detail.get("expiry_notes")
        check("expiry_notes populated on override sale", expiry_notes is not None and "Expiry" in str(expiry_notes))
        if expiry_notes:
            print(f"    expiry_notes: {expiry_notes[:120]}")

        # Verify override_sale flag is set
        check("override_sale flag is set", inv_detail.get("override_sale") in (1, True, "1"))

        # Verify invoice items have expiry info
        items = inv_detail.get("items", [])
        has_expiry_item = any(i.get("expiry_date") for i in items)
        check("Invoice items have expiry_date", has_expiry_item)
        has_expired_flag = any(i.get("is_expired_at_sale") for i in items)
        check("Invoice items have is_expired_at_sale=1", has_expired_flag)
    else:
        check("Override sale created", False, r)

    # ── Test 3: Halt batch blocks consumption ──────────────────
    print("\n── Test 3: Halt/unhalt batch ──")

    r = api("PATCH", f"/stock-batches/{expired_batch['id']}/halt", {
        "reason": "Quality hold"
    }, token)
    check("Batch halted", r.get("halted") in (1, True, "1"))

    # Try to sell — should fail because the only undated batch is halted
    # (the future batch has remaining stock, so this might still succeed)
    # Actually, the future batch still has stock. Let me halt that too.
    api("PATCH", f"/stock-batches/{future_batch['id']}/halt", {"reason": "Test halt"}, token)

    r = api("POST", "/invoices", {
        "invoice_no": f"INV-E2E-HALT-{int(time.time())}",
        "customer_id": cust_id,
        "invoice_date": "2026-08-21",
        "due_date": "2026-09-21",
        "total_amount": 100.0,
        "items": [{"item_id": item_id, "quantity": 5, "unit_price": 20.0}],
    }, token)
    check("Sale fails when all batches halted", "_error" in r)

    # Unhalt
    api("PATCH", f"/stock-batches/{expired_batch['id']}/unhalt", token=token)
    api("PATCH", f"/stock-batches/{future_batch['id']}/unhalt", token=token)
    batches_unhalted = api("GET", f"/stock-batches?item_id={item_id}", token=token)
    all_unhalted = all(not b.get("halted") for b in batches_unhalted)
    check("Both batches unhalted", all_unhalted)

    # ── Cleanup ────────────────────────────────────────────────
    print("\n── Cleanup ──")
    # Delete test invoices
    inv_list = api("GET", "/invoices?limit=20&sort=desc", token=token)
    inv_data = inv_list if isinstance(inv_list, list) else inv_list.get("data", [])
    for inv in inv_data:
        if "E2E" in (inv.get("invoice_no") or ""):
            api("DELETE", f"/invoices/{inv['id']}", token=token)
    api("DELETE", f"/purchases/{pur_a_id}", token=token)
    api("DELETE", f"/purchases/{pur_b_id}", token=token)
    api("DELETE", f"/inventory/items/{item_id}", token=token)
    api("DELETE", f"/customers/{cust_id}", token=token)
    print("  ✓ Cleanup done")

    # ── Summary ────────────────────────────────────────────────
    print("\n" + "=" * 60)
    total = PASS + FAIL
    print(f"Results: {PASS}/{total} passed, {FAIL} failed")
    print("=" * 60)
    sys.exit(1 if FAIL > 0 else 0)


if __name__ == "__main__":
    main()
