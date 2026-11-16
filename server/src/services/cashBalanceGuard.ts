/**
 * cashBalanceGuard — historical home of the chronological cash guard.
 *
 * D21 moved the implementation to `services/cashTimeline.ts`, a leaf module
 * that neither `accountingService` nor this file owns, so the lazy
 * `require` inside `AccountingService.assertCashTimelineAfterOutflow` could
 * become a normal top-level import. This file stays as a re-export so every
 * existing import path (models, services, controllers, tests) keeps
 * resolving unchanged, and the source-scan tripwire in
 * `cashOutflowEditTimeline.test.ts` keeps seeing `assertCashTimeline` here.
 */
export { assertCashTimeline } from './cashTimeline';
export type { CashOrBankCode } from './cashTimeline';
