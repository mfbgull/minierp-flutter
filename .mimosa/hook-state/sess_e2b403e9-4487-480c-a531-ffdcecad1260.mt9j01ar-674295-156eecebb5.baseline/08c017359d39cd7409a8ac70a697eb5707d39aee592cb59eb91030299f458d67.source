/**
 * Dashboard Block Registry
 *
 * Central registry mapping all dashboard block types to their component,
 * icon, default size, description, required permissions, and default config.
 *
 * Uses React.lazy for code-splitting — each block component is loaded on demand.
 *
 * @see dashboard-customization-spec.md §1 — Block Catalog
 * @see dashboard-customization-spec.md §6 — Frontend Architecture
 */

import { lazy, type ComponentType } from 'react';
import type { LucideIcon } from 'lucide-react';
import {
  LayoutDashboard, TrendingUp, PieChart, AlertTriangle, Zap,
  Activity, Wallet, Award, BarChart3, DollarSign, CreditCard,
  Factory, ArrowUpDown, Type, Gauge,
} from 'lucide-react';

// ═══════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════

export type DashboardBlockType =
  | 'stat_cards'
  | 'sales_vs_purchases_chart'
  | 'stock_by_category_chart'
  | 'low_stock_alerts'
  | 'quick_actions'
  | 'recent_activity'
  | 'ar_summary'
  | 'top_customers'
  | 'forecast_snapshot'
  | 'sales_summary'
  | 'expense_summary'
  | 'production_status'
  | 'stock_movement_summary'
  | 'custom_text'
  | 'kpi_gauge'
  | 'deprecated_block';

export interface BlockSize {
  width: number;  // in grid columns (1-3)
  height: number; // in grid rows (1-3)
}

export interface BlockRegistryEntry {
  /** Unique block type key — matches the `type` field in the JSON schema */
  type: DashboardBlockType;
  /** i18n key for the block's display name */
  labelKey: string;
  /** i18n key for the block's short description */
  descriptionKey: string;
  /** Lucide icon component for the palette */
  icon: LucideIcon;
  /** default size when first added to a dashboard */
  defaultSize: BlockSize;
  /** Minimum size in grid units */
  minSize: BlockSize;
  /** Maximum size in grid units */
  maxSize: BlockSize;
  /** Allowable width values (for preset size buttons) */
  allowedWidths: number[];
  /** Allowable height values (for preset size buttons) */
  allowedHeights: number[];
  /** Default block-level configuration */
  defaultConfig: Record<string, unknown>;
  /** Permission required to see this block type in the palette.
   *  Format: `'module:action'` matching the permission seed data.
   *  null means no permission check needed. */
  requiredPermission: string | null;
  /** Lazy-loaded React component to render the block content.
   *  null for `deprecated_block` (which is always available). */
  component: React.LazyExoticComponent<ComponentType<any>> | null;
  /** API endpoint to fetch data for this block (null for static blocks) */
  apiEndpoint: string | null;
}

// ═══════════════════════════════════════════════════════════════
//  LAZY LOADED COMPONENTS
// ═══════════════════════════════════════════════════════════════

const StatCardsBlock = lazy(() => import('../components/dashboard/blocks/StatCardsBlock'));
const SalesPurchasesChartBlock = lazy(() => import('../components/dashboard/blocks/SalesPurchasesChartBlock'));
const StockByCategoryBlock = lazy(() => import('../components/dashboard/blocks/StockByCategoryBlock'));
const LowStockAlertsBlock = lazy(() => import('../components/dashboard/blocks/LowStockAlertsBlock'));
const QuickActionsBlock = lazy(() => import('../components/dashboard/blocks/QuickActionsBlock'));
const RecentActivityBlock = lazy(() => import('../components/dashboard/blocks/RecentActivityBlock'));
const ARSummaryBlock = lazy(() => import('../components/dashboard/blocks/ARSummaryBlock'));
const TopCustomersBlock = lazy(() => import('../components/dashboard/blocks/TopCustomersBlock'));
const ForecastSnapshotBlock = lazy(() => import('../components/dashboard/blocks/ForecastSnapshotBlock'));
const SalesSummaryBlock = lazy(() => import('../components/dashboard/blocks/SalesSummaryBlock'));
const ExpenseSummaryBlock = lazy(() => import('../components/dashboard/blocks/ExpenseSummaryBlock'));
const ProductionStatusBlock = lazy(() => import('../components/dashboard/blocks/ProductionStatusBlock'));
const StockMovementSummaryBlock = lazy(() => import('../components/dashboard/blocks/StockMovementSummaryBlock'));
const CustomTextBlock = lazy(() => import('../components/dashboard/blocks/CustomTextBlock'));
const KPIGaugeBlock = lazy(() => import('../components/dashboard/blocks/KPIGaugeBlock'));

// ═══════════════════════════════════════════════════════════════
//  REGISTRY
// ═══════════════════════════════════════════════════════════════

/**
 * The master block registry. Maps every DashboardBlockType to its metadata.
 *
 * Used by:
 * - DashboardBlockPalette — to list available blocks the user can add
 * - DashboardBlock — to resolve the component and default config for a saved block
 * - DashboardLayout — to compute initial positions for default layout
 */
const blockRegistry: Record<string, BlockRegistryEntry> = {
  stat_cards: {
    type: 'stat_cards',
    labelKey: 'dashboardCustomization.blockStatCards',
    descriptionKey: 'dashboardCustomization.blockStatCardsDesc',
    icon: LayoutDashboard,
    defaultSize: { width: 3, height: 1 },
    minSize: { width: 2, height: 1 },
    maxSize: { width: 3, height: 2 },
    allowedWidths: [2, 3],
    allowedHeights: [1],
    defaultConfig: {},
    requiredPermission: 'dashboard:read',
    component: StatCardsBlock,
    apiEndpoint: '/dashboard/summary',
  },

  sales_vs_purchases_chart: {
    type: 'sales_vs_purchases_chart',
    labelKey: 'dashboardCustomization.blockSalesPurchases',
    descriptionKey: 'dashboardCustomization.blockSalesPurchasesDesc',
    icon: TrendingUp,
    defaultSize: { width: 2, height: 2 },
    minSize: { width: 1, height: 2 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [2, 3],
    defaultConfig: {},
    requiredPermission: 'dashboard:read',
    component: SalesPurchasesChartBlock,
    apiEndpoint: '/dashboard/summary',
  },

  stock_by_category_chart: {
    type: 'stock_by_category_chart',
    labelKey: 'dashboardCustomization.blockStockByCategory',
    descriptionKey: 'dashboardCustomization.blockStockByCategoryDesc',
    icon: PieChart,
    defaultSize: { width: 1, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 3 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2, 3],
    defaultConfig: {},
    requiredPermission: 'dashboard:read',
    component: StockByCategoryBlock,
    apiEndpoint: '/dashboard/summary',
  },

  low_stock_alerts: {
    type: 'low_stock_alerts',
    labelKey: 'dashboardCustomization.blockLowStock',
    descriptionKey: 'dashboardCustomization.blockLowStockDesc',
    icon: AlertTriangle,
    defaultSize: { width: 1, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 3 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2, 3],
    defaultConfig: { limit: 10 },
    requiredPermission: 'inventory:read',
    component: LowStockAlertsBlock,
    apiEndpoint: '/dashboard/summary',
  },

  quick_actions: {
    type: 'quick_actions',
    labelKey: 'dashboardCustomization.blockQuickActions',
    descriptionKey: 'dashboardCustomization.blockQuickActionsDesc',
    icon: Zap,
    defaultSize: { width: 1, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 2 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2],
    defaultConfig: {},
    requiredPermission: 'dashboard:read',
    component: QuickActionsBlock,
    apiEndpoint: null, // Static — hardcoded links
  },

  recent_activity: {
    type: 'recent_activity',
    labelKey: 'dashboardCustomization.blockRecentActivity',
    descriptionKey: 'dashboardCustomization.blockRecentActivityDesc',
    icon: Activity,
    defaultSize: { width: 2, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2, 3],
    defaultConfig: { limit: 20 },
    requiredPermission: 'activity_log:read',
    component: RecentActivityBlock,
    apiEndpoint: '/activity-logs/recent',
  },

  ar_summary: {
    type: 'ar_summary',
    labelKey: 'dashboardCustomization.blockARSummary',
    descriptionKey: 'dashboardCustomization.blockARSummaryDesc',
    icon: Wallet,
    defaultSize: { width: 2, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2, 3],
    defaultConfig: {},
    requiredPermission: 'reports:read',
    component: ARSummaryBlock,
    apiEndpoint: '/dashboard/ar-summary',
  },

  top_customers: {
    type: 'top_customers',
    labelKey: 'dashboardCustomization.blockTopCustomers',
    descriptionKey: 'dashboardCustomization.blockTopCustomersDesc',
    icon: Award,
    defaultSize: { width: 1, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2, 3],
    defaultConfig: { limit: 5 },
    requiredPermission: 'reports:read',
    component: TopCustomersBlock,
    apiEndpoint: '/dashboard/top-customers',
  },

  forecast_snapshot: {
    type: 'forecast_snapshot',
    labelKey: 'dashboardCustomization.blockForecastSnapshot',
    descriptionKey: 'dashboardCustomization.blockForecastSnapshotDesc',
    icon: BarChart3,
    defaultSize: { width: 1, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 2 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2],
    defaultConfig: {},
    requiredPermission: 'forecasts:read',
    component: ForecastSnapshotBlock,
    apiEndpoint: '/forecasts/dashboard',
  },

  sales_summary: {
    type: 'sales_summary',
    labelKey: 'dashboardCustomization.blockSalesSummary',
    descriptionKey: 'dashboardCustomization.blockSalesSummaryDesc',
    icon: DollarSign,
    defaultSize: { width: 1, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 2 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2],
    defaultConfig: { period: 'today' },
    requiredPermission: 'sales:read',
    component: SalesSummaryBlock,
    apiEndpoint: '/dashboard/sales-summary',
  },

  expense_summary: {
    type: 'expense_summary',
    labelKey: 'dashboardCustomization.blockExpenseSummary',
    descriptionKey: 'dashboardCustomization.blockExpenseSummaryDesc',
    icon: CreditCard,
    defaultSize: { width: 1, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 2 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2],
    defaultConfig: { period: 'week' },
    requiredPermission: 'expenses:read',
    component: ExpenseSummaryBlock,
    apiEndpoint: '/dashboard/expense-summary',
  },

  production_status: {
    type: 'production_status',
    labelKey: 'dashboardCustomization.blockProductionStatus',
    descriptionKey: 'dashboardCustomization.blockProductionStatusDesc',
    icon: Factory,
    defaultSize: { width: 1, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2, 3],
    defaultConfig: {},
    requiredPermission: 'production:read',
    component: ProductionStatusBlock,
    apiEndpoint: '/dashboard/production-status',
  },

  stock_movement_summary: {
    type: 'stock_movement_summary',
    labelKey: 'dashboardCustomization.blockStockMovements',
    descriptionKey: 'dashboardCustomization.blockStockMovementsDesc',
    icon: ArrowUpDown,
    defaultSize: { width: 2, height: 2 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 3 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2, 3],
    defaultConfig: { days: 7 },
    requiredPermission: 'inventory:read',
    component: StockMovementSummaryBlock,
    apiEndpoint: '/dashboard/stock-movement-summary',
  },

  custom_text: {
    type: 'custom_text',
    labelKey: 'dashboardCustomization.blockCustomText',
    descriptionKey: 'dashboardCustomization.blockCustomTextDesc',
    icon: Type,
    defaultSize: { width: 2, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 2 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2],
    defaultConfig: { text: 'Your heading or notes here' },
    requiredPermission: null, // Available to everyone
    component: CustomTextBlock,
    apiEndpoint: null, // Static — text saved in block config
  },

  kpi_gauge: {
    type: 'kpi_gauge',
    labelKey: 'dashboardCustomization.blockKPIGauge',
    descriptionKey: 'dashboardCustomization.blockKPIGaugeDesc',
    icon: Gauge,
    defaultSize: { width: 1, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 2, height: 2 },
    allowedWidths: [1, 2],
    allowedHeights: [1, 2],
    defaultConfig: { metric: 'stock_health' },
    requiredPermission: 'dashboard:read',
    component: KPIGaugeBlock,
    apiEndpoint: '/dashboard/kpi',
  },

  deprecated_block: {
    type: 'deprecated_block',
    labelKey: 'dashboardCustomization.deprecatedBlock',
    descriptionKey: 'dashboardCustomization.deprecatedBlock',
    icon: AlertTriangle,
    defaultSize: { width: 2, height: 1 },
    minSize: { width: 1, height: 1 },
    maxSize: { width: 3, height: 2 },
    allowedWidths: [1, 2, 3],
    allowedHeights: [1, 2],
    defaultConfig: {},
    requiredPermission: null,
    component: null, // DeprecatedBlock is rendered inline by DashboardBlock
    apiEndpoint: null,
  },
};

// ═══════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════

/**
 * Get the registry entry for a given block type.
 * Falls back to `deprecated_block` for unknown types (forward compatibility).
 */
export function getBlockEntry(type: string): BlockRegistryEntry {
  return blockRegistry[type] || blockRegistry.deprecated_block;
}

/**
 * Get all block types that are available in the palette, optionally filtered
 * by user permissions. The `hasPermission` callback checks whether the
 * current user has a given permission string.
 *
 * Block types with `requiredPermission: null` are always available.
 * `deprecated_block` is never shown in the palette.
 */
export function getPaletteBlocks(
  hasPermission: (permission: string) => boolean
): BlockRegistryEntry[] {
  return Object.values(blockRegistry)
    .filter((entry) => entry.type !== 'deprecated_block')
    .filter((entry) => {
      if (entry.requiredPermission === null) return true;
      return hasPermission(entry.requiredPermission);
    });
}

/**
 * Default layout used when a user has no saved layout.
 * Mimics the current hardcoded Dashboard.tsx layout.
 */
export const DEFAULT_LAYOUT_BLOCKS: Array<{
  type: DashboardBlockType;
  x: number;
  y: number;
}> = [
  // Row 1
  { type: 'stat_cards', x: 0, y: 0 },
  // Row 2
  { type: 'sales_vs_purchases_chart', x: 0, y: 1 },
  { type: 'stock_by_category_chart', x: 2, y: 1 },
  // Row 3
  { type: 'low_stock_alerts', x: 0, y: 3 },
  { type: 'quick_actions', x: 1, y: 3 },
  { type: 'forecast_snapshot', x: 2, y: 3 },
  // Row 4
  { type: 'top_customers', x: 2, y: 4 },
];

export default blockRegistry;
