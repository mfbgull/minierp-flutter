/**
 * Shared layout constants for the dashboard grid system.
 *
 * Used by DashboardLayout.tsx for positioning blocks and
 * DashboardBlock.tsx for computing resize snap deltas.
 *
 * If you change these values, update the CSS variable fallbacks
 * in the component CSS files accordingly.
 *
 * @see dashboard-customization-spec.md §2 — Layout System
 */

/** Number of columns in the dashboard grid */
export const GRID_COLUMNS = 3;

/** Gap between blocks in pixels */
export const GRID_GAP = 16;

/** Height of each grid row in pixels */
export const ROW_HEIGHT = 180;

/** Maximum number of cascade shifts when resolving block overlap during drag */
export const CASCADE_CAP = 10;
