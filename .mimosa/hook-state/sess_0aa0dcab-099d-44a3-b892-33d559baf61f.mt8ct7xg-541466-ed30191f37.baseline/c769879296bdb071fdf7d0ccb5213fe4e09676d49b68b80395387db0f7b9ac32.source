import { forwardRef } from 'react';
import type {
  ColDef,
  GridOptions,
  RowSelectionOptions,
  GridReadyEvent,
  CellClickedEvent,
  RowDoubleClickedEvent,
} from 'ag-grid-community';
import { AgGridReact } from 'ag-grid-react';
import '../../utils/agGridIntegration';

export interface MiniERPGridProps<TData = any> {
  // Required
  columnDefs: ColDef<TData>[];
  rowData: TData[];

  /**
   * Auto-sizing strategy.
   * - `true` (default) → `{ type: 'fitGridWidth', defaultMinWidth: 80 }`
   * - `false` → no auto-sizing (e.g. report grids with horizontal scroll)
   * - object → explicit strategy config
   */
  autoSize?: boolean | {
    type: 'fitGridWidth' | 'fitCellContents';
    defaultMinWidth?: number;
  };

  /** Fully replaces MiniERPGrid's defaultColDef.
   *  Spread `{ resizable: true, sortable: true, filter: true }` to base on defaults. */
  defaultColDef?: ColDef;

  // Pagination
  pagination?: boolean;
  paginationPageSize?: number;
  paginationPageSizeSelector?: number[];

  // Row selection — default: { mode: 'singleRow' }; pass null to disable
  rowSelection?: RowSelectionOptions | null;

  // Display
  animateRows?: boolean;
  loading?: boolean;
  overlayNoRowsTemplate?: string;

  // Layout — pages manage their own height
  containerStyle?: React.CSSProperties;
  wrapperClassName?: string;

  // Events
  onGridReady?: (event: GridReadyEvent<TData>) => void;
  onCellClicked?: (event: CellClickedEvent<TData>) => void;
  onRowDoubleClicked?: (event: RowDoubleClickedEvent<TData>) => void;

  // Type-safe passthrough for advanced AG Grid config
  gridOptions?: GridOptions<TData>;

  // Unknown AG Grid props for edge cases (getRowId, suppressMaxRenderedRowRestriction, etc.)
  [key: string]: any;
}

const MiniERPGrid = forwardRef<AgGridReact, MiniERPGridProps>((props, ref) => {
  const {
    columnDefs,
    rowData,
    autoSize = true,
    defaultColDef: customDefaultColDef,
    pagination = true,
    paginationPageSize = 20,
    paginationPageSizeSelector = [10, 20, 50, 100],
    rowSelection = { mode: 'singleRow' } as RowSelectionOptions,
    animateRows = true,
    loading,
    overlayNoRowsTemplate,
    containerStyle,
    wrapperClassName,
    onGridReady,
    onCellClicked,
    onRowDoubleClicked,
    gridOptions,
    ...passthrough
  } = props;

  // Resolve auto-size strategy
  // AG Grid: colDef.flex and autoSizeStrategy are mutually exclusive.
  // If any column uses flex, skip autoSizeStrategy.
  const hasFlexColumns = columnDefs?.some((col) => (col as any).flex != null);
  const shouldAutoSize = autoSize !== false && !hasFlexColumns;
  const autoSizeStrategy = !shouldAutoSize
    ? undefined
    : typeof autoSize === 'object'
      ? autoSize
      : { type: 'fitGridWidth' as const, defaultMinWidth: 80 };

  // Default column definitions
  const defaultColDef: ColDef = customDefaultColDef ?? {
    resizable: true,
    sortable: true,
    filter: true,
  };

  return (
    <div
      className={`ag-theme-quartz mini-erp-grid${wrapperClassName ? ` ${wrapperClassName}` : ''}`}
      style={containerStyle}
    >
      <AgGridReact
        ref={ref}
        rowData={rowData}
        columnDefs={columnDefs}
        defaultColDef={defaultColDef}
        autoSizeStrategy={autoSizeStrategy}
        pagination={pagination}
        paginationPageSize={paginationPageSize}
        paginationPageSizeSelector={paginationPageSizeSelector}
        {...(rowSelection != null ? { rowSelection } : {})}
        animateRows={animateRows}
        loading={loading}
        overlayNoRowsTemplate={overlayNoRowsTemplate}
        onGridReady={onGridReady}
        onCellClicked={onCellClicked}
        onRowDoubleClicked={onRowDoubleClicked}
        {...gridOptions}
        {...passthrough}
      />
    </div>
  );
});

MiniERPGrid.displayName = 'MiniERPGrid';

export default MiniERPGrid;
