/**
 * AG-Grid integration utilities.
 * Registers AG-Grid modules and provides helper functions.
 */
import { ModuleRegistry, AllCommunityModule, GridApi } from 'ag-grid-community';
import type { ColDef } from 'ag-grid-community';

ModuleRegistry.registerModules([AllCommunityModule]);

function isAGGridEditing(api: GridApi | null): boolean {
  if (!api) return false;
  return api.getEditingCells().length > 0;
}

function isAGGridCellFocused(api: GridApi | null): boolean {
  if (!api) return false;
  const focusedCell = api.getFocusedCell();
  return focusedCell !== null;
}

function shouldIgnoreForAGGrid(api: GridApi | null): boolean {
  if (!api) return false;
  return isAGGridEditing(api) || isAGGridCellFocused(api);
}

export interface CreateActionColDefOptions {
  /** Required: cell renderer that renders the dropdown menu */
  cellRenderer: (params: any) => any;
  /** Column header name. Default 'Actions' */
  headerName?: string;
  /** Column field name. Default 'actions' */
  field?: string;
  /** Column ID (use instead of field when no field binding is needed) */
  colId?: string;
  /** Column width in px. Default 70 */
  width?: number;
}

/**
 * Create a standard AG-Grid action column definition pinned to the right.
 * Use this in all grid column definitions to keep action columns consistent.
 *
 * @example
 * ```tsx
 * createActionColDef({
 *   headerName: t('common.actions'),
 *   cellRenderer: (params) => (
 *     <DropdownMenu trigger=... items={...} />
 *   ),
 * })
 * ```
 */
export function createActionColDef(options: CreateActionColDefOptions): ColDef {
  const {
    cellRenderer,
    headerName = 'Actions',
    field = 'actions',
    colId,
    width = 50,
  } = options;

  return {
    headerName,
    ...(colId ? { colId } : { field }),
    width,
    minWidth: 50,
    maxWidth: 80,
    pinned: 'right' as const,
    sortable: false,
    filter: false,
    suppressSizeToFit: true,
    cellRenderer,
  };
}
