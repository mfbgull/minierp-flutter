/**
 * One-time GL unification migration (Phase 3 of the delete &
 * transaction-reversal audit).
 *
 * journal_lines is now the canonical GL. This migration repairs two
 * historical inconsistencies in one transaction:
 *
 *  1. Re-link pass: journal_lines groups whose header row is missing
 *     (or whose header reference_type mismatches the line reference_type)
 *     get a fresh journal_entries header with the group's own
 *     reference_type/reference_id, and the lines are re-pointed at it.
 *     Mis-linked groups never touch the stock_adjustment headers they
 *     previously (and wrongly) pointed at.
 *
 *  2. Legacy migration pass: every legacy journal_entries row that has
 *     no journal_lines after the re-link gets debit + credit canonical
 *     lines resolved via chart_of_accounts (text_code with code fallback),
 *     copying date, description, reference_type/id and the voided flag.
 *
 * Idempotent: a second run finds no orphan/mis-linked groups and no
 * line-less legacy entries, so all passes are no-ops.
 */
import type Database from 'better-sqlite3';
import logger from '../utils/logger';

export function runBackfillGlUnification(db: Database.Database): void {
  const run = (): void => {
    // Pass 1: re-link orphaned / mis-linked journal_lines
    const brokenGroups = db.prepare(`
      SELECT jl.reference_type, jl.reference_id,
             MIN(jl.line_date) AS entry_date,
             MIN(jl.id) AS first_line_id
      FROM journal_lines jl
      LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE je.id IS NULL OR je.reference_type <> jl.reference_type
      GROUP BY jl.reference_type, jl.reference_id
    `).all() as Array<{
      reference_type: string;
      reference_id: number;
      entry_date: string;
      first_line_id: number;
    }>;

    let relinkedGroups = 0;
    let relinkedLines = 0;

    for (const group of brokenGroups) {
      const lines = db.prepare(`
        SELECT jl.id, jl.account_id, jl.debit, jl.credit, jl.description,
               jl.line_date, jl.voided
        FROM journal_lines jl
        LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
        WHERE jl.reference_type = ? AND jl.reference_id = ?
          AND (je.id IS NULL OR je.reference_type <> jl.reference_type)
        ORDER BY jl.id
      `).all(group.reference_type, group.reference_id) as Array<{
        id: number;
        account_id: number;
        debit: number;
        credit: number;
        description: string;
        line_date: string;
        voided: number;
      }>;

      if (lines.length === 0) continue;

      const firstDebit = lines.find(l => l.debit > 0);
      const firstCredit = lines.find(l => l.credit > 0);
      const debitAccountId = firstDebit ? String(firstDebit.account_id) : String(lines[0].account_id);
      const creditAccountId = firstCredit ? String(firstCredit.account_id) : String(lines[lines.length - 1].account_id);
      const amount = lines.reduce((sum, l) => sum + l.debit, 0);

      const headerResult = db.prepare(`
        INSERT INTO journal_entries
          (reference_type, reference_id, entry_date, description,
           debit_account, credit_account, amount, voided)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        group.reference_type,
        group.reference_id,
        lines[0].line_date,
        lines[0].description,
        debitAccountId,
        creditAccountId,
        amount,
        lines.some(l => l.voided === 1) ? 1 : 0
      );
      const newHeaderId = Number(headerResult.lastInsertRowid);

      const repoint = db.prepare(`
        UPDATE journal_lines SET journal_entry_id = ?
        WHERE id = ?
      `);
      for (const line of lines) {
        repoint.run(newHeaderId, line.id);
        relinkedLines += 1;
      }
      relinkedGroups += 1;
    }

    // Pass 2: give line-less legacy journal_entries rows lines
    const accountByCode = new Map(
      (db.prepare(`SELECT id, code, text_code FROM chart_of_accounts`).all() as Array<{
        id: number;
        code: string;
        text_code: string | null;
      }>).map(a => [a.text_code || a.code, a.id])
    );

    const legacyEntries = db.prepare(`
      SELECT je.id, je.reference_type, je.reference_id, je.entry_date,
             je.description, je.debit_account, je.credit_account,
             je.amount, je.voided
      FROM journal_entries je
      WHERE NOT EXISTS (
        SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = je.id
      )
    `).all() as Array<{
      id: number;
      reference_type: string;
      reference_id: number;
      entry_date: string;
      description: string;
      debit_account: string;
      credit_account: string;
      amount: number;
      voided: number;
    }>;

    let migratedEntries = 0;
    let migratedLines = 0;

    const insertLine = db.prepare(`
      INSERT INTO journal_lines (
        journal_entry_id, account_id, debit, credit, description,
        line_date, reference_type, reference_id, voided
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    for (const entry of legacyEntries) {
      const debitId = accountByCode.get(entry.debit_account);
      const creditId = accountByCode.get(entry.credit_account);
      if (debitId === undefined || creditId === undefined) {
        logger.warn(`[gl-unify] skipping legacy entry #${entry.id} - unresolvable account code(s)`);
        continue;
      }
      const voidedFlag = entry.voided === 1 ? 1 : 0;
      insertLine.run(
        entry.id, debitId, entry.amount, 0, entry.description,
        entry.entry_date, entry.reference_type, entry.reference_id, voidedFlag
      );
      insertLine.run(
        entry.id, creditId, 0, entry.amount, entry.description,
        entry.entry_date, entry.reference_type, entry.reference_id, voidedFlag
      );
      migratedEntries += 1;
      migratedLines += 2;
    }

    // Post-conditions
    const orphans = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines jl
      LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE je.id IS NULL OR je.reference_type <> jl.reference_type
    `).get() as { n: number };

    const footing = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c
      FROM journal_lines WHERE voided = 0
    `).get() as { d: number; c: number };

    if (orphans.n > 0) {
      throw new Error(`[gl-unify] ${orphans.n} journal_lines remain orphaned/mis-linked after re-link`);
    }
    if (Math.abs(footing.d - footing.c) > 0.01) {
      throw new Error(`[gl-unify] journal_lines do not foot after unification: D ${footing.d} vs C ${footing.c}`);
    }

    if (relinkedGroups > 0 || migratedEntries > 0) {
      logger.info(
        `[gl-unify] re-linked ${relinkedGroups} group(s) / ${relinkedLines} line(s); migrated ${migratedEntries} legacy entr(ies) / ${migratedLines} line(s); footing ${footing.d.toFixed(2)} == ${footing.c.toFixed(2)}`
      );
    }
  };

  db.transaction(run)();
}
