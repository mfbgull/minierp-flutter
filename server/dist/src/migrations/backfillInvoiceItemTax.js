"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.runBackfillInvoiceItemTax = runBackfillInvoiceItemTax;
const logger_1 = __importDefault(require("../utils/logger"));
const r2 = (v) => Math.round(v * 100) / 100;
const tol = (amount) => Math.max(0.01, Math.abs(amount) * 0.001);
function runBackfillInvoiceItemTax(db) {
    const lines = db.prepare(`
    SELECT id, quantity, unit_price, amount, tax_rate, discount_type, COALESCE(discount_value, 0) as discount_value
    FROM invoice_items WHERE tax_amount = 0 AND net_amount = 0
  `).all();
    const update = db.prepare(`UPDATE invoice_items SET net_amount = ?, tax_amount = ? WHERE id = ?`);
    const review = [];
    let updated = 0;
    const run = () => {
        for (const l of lines) {
            const gross = r2(l.quantity * l.unit_price);
            const dv = r2(l.discount_value || 0);
            let afterDiscount = gross;
            if (dv > 0) {
                const disc = l.discount_type === 'flat' ? r2(dv) : r2(gross * (dv / 100));
                afterDiscount = r2(gross - Math.min(disc, gross));
            }
            const rate = l.tax_rate || 0;
            // Zero-amount lines have nothing to decompose.
            if (r2(l.amount) === 0) {
                update.run(0, 0, l.id);
                continue;
            }
            const predictedInclusive = r2(afterDiscount * (1 + rate / 100));
            if (Math.abs(r2(l.amount) - predictedInclusive) <= tol(l.amount)) {
                const tax = r2(afterDiscount * (rate / 100));
                update.run(r2(l.amount - tax), tax, l.id);
                updated += 1;
                continue;
            }
            // Legacy exclusive/gross-stored row: amount never contained tax.
            const taxExclusive = r2(r2(l.amount) * (rate / 100));
            update.run(r2(l.amount), taxExclusive, l.id);
            updated += 1;
            review.push(`invoice_item #${l.id}: stored ${l.amount} matches neither inclusive ` +
                `${predictedInclusive} nor gross ${gross} — treated as tax-exclusive base`);
        }
    };
    db.transaction(run)();
    logger_1.default.info(`[backfill-item-tax] decomposed ${updated} line(s); ${review.length} need review`);
    for (const item of review)
        logger_1.default.warn(`[backfill-item-tax] review: ${item}`);
}
