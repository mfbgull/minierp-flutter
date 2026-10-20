# Invoice retry-key migration telemetry

D13 preserves compatibility for invoice clients without retry keys. Both
`POST /api/invoices` and `POST /api/mobile-invoices/submit` emit one structured
`invoice_idempotency_observation` event after authentication, body validation and
retry-key parsing. This counts submission attempts, including retries and later
business-rule rejections; it does not count committed invoices.

From `server/`, run:

```sh
node scripts/invoice-idempotency-report.cjs logs/combined.log
```

Pass archived combined JSON log files as additional arguments to include the
whole observation window. Each route reports `keyed` and `keyless` attempt counts.
Archive logs before rotation discards them; counts cover only the supplied files.
Keep the default info log level during observation. Malformed JSON and unrelated
events are ignored. Events contain route and key presence, never keys or invoice
payloads. Existing keyless warnings retain limited client-identification metadata.

Confirm all external mobile consumers have migrated over a representative usage
window before making a separate decision to enforce keys. Zero observed keyless
attempts alone does not prove that a dormant external consumer has migrated.
