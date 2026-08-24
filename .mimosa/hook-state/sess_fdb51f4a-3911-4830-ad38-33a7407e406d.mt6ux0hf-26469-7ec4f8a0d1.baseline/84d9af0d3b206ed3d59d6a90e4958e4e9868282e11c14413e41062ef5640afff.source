/**
 * useInvoiceV2Keyboard — Spreadsheet-style keyboard navigation for the v2 items grid.
 *
 * Manages a virtual cell pointer and provides:
 * - Arrow key navigation (↑↓←→) in all 4 directions
 * - Enter/Shift+Enter to move down/up between rows
 * - Tab/Shift+Tab for horizontal cell navigation
 * - Auto-scroll to keep focused cell visible
 * - Auto-add row when Enter pressed on last cell of last row
 * - Alt+I to insert row, Ctrl+Delete to delete row
 */

import { useState, useCallback, useRef, useMemo } from 'react';

import type { CellColumn, CellPosition } from '../types/invoiceV2';

/* ── Constants ─────────────────────────────────────────────────── */

const FIELD_ORDER_ITEM: readonly CellColumn[] = [
  'description',
  'quantity',
  'rate',
  'discountValue',
  'tax',
] as const;

const FIELD_ORDER_INVOICE: readonly CellColumn[] = [
  'description',
  'quantity',
  'rate',
  'tax',
] as const;

/* ── Options ────────────────────────────────────────────────────── */

export interface UseInvoiceV2KeyboardOptions {
  /** Current number of items in the grid */
  itemCount: number;
  /** Whether per-item discount columns should appear */
  discountScope: 'item' | 'invoice';
  /** Called when the user wants to add a new row. Returns new item's local id. */
  onAddNewItem: () => number;
  /** Called when the user wants to remove a row. Receives the row index (not item id). */
  onRemoveItem: (itemId: number) => void;
  /** Called whenever the focused cell changes */
  onCellChange?: (pos: CellPosition | null) => void;
  /** Called when a new row should be added at the end (Enter on last row) */
  onAddRowAtEnd?: () => void;
  /** Item IDs for each row (for delete operations) */
  itemIds: number[];
}

/* ── Return type ────────────────────────────────────────────────── */

export interface UseInvoiceV2KeyboardReturn {
  /** The currently focused cell position, or null */
  focusedCell: CellPosition | null;
  /** Programmatically focus a specific cell */
  focusCell: (pos: CellPosition | null) => void;
  /** Handle keyboard events on the grid container */
  handleGridKeyDown: (e: React.KeyboardEvent) => void;
  /** Get the ordered field columns for the current discount scope */
  getFieldOrder: () => readonly CellColumn[];
  /** Check if a position is the last cell in the grid */
  isLastCell: (pos: CellPosition) => boolean;
  /** Get item id for a given row index */
  getItemId: (rowIndex: number) => number | undefined;
}

/* ── DOM helpers ────────────────────────────────────────────────── */

/**
 * Focus a cell element identified by data-cell-id.
 * Uses requestAnimationFrame for reliable DOM selection after state updates.
 */
function focusCellElement(row: number, col: CellColumn): HTMLElement | null {
  const selector = `[data-cell-id="${row}-${col}"]`;
  const el = document.querySelector<HTMLElement>(selector);

  if (!el) {
    // Try again on next frame — the DOM may not have rendered yet
    requestAnimationFrame(() => {
      const retry = document.querySelector<HTMLElement>(selector);
      if (retry) {
        retry.focus({ preventScroll: false });
        retry.scrollIntoView({ block: 'nearest', behavior: 'smooth' });

        // If the element contains an input, select its text
        const input = retry.querySelector('input, textarea, select');
        if (input) {
          (input as HTMLElement).focus();
          if (input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement) {
            input.select();
          }
        }
      }
    });
    return null;
  }

  el.focus({ preventScroll: false });
  el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });

  // If element contains an input, focus and select its text
  const input = el.querySelector('input, textarea, select');
  if (input) {
    (input as HTMLElement).focus();
    if (input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement) {
      input.select();
    }
  }

  return el;
}

/* ── Hook ────────────────────────────────────────────────────────── */

export function useInvoiceV2Keyboard({
  itemCount,
  discountScope,
  onAddNewItem,
  onRemoveItem,
  onCellChange,
  onAddRowAtEnd,
  itemIds,
}: UseInvoiceV2KeyboardOptions): UseInvoiceV2KeyboardReturn {
  const [focusedCell, setFocusedCellState] = useState<CellPosition | null>(null);
  const fieldOrderRef = useRef(getFieldOrderForScope(discountScope));
  fieldOrderRef.current = getFieldOrderForScope(discountScope);

  // Keep a ref for the latest values so keyboard handler doesn't stale-close
  const itemCountRef = useRef(itemCount);
  itemCountRef.current = itemCount;
  const itemIdsRef = useRef(itemIds);
  itemIdsRef.current = itemIds;

  /* ── Get field order ─────────────────────────────────────────── */

  function getFieldOrderForScope(scope: 'item' | 'invoice'): readonly CellColumn[] {
    return scope === 'item' ? FIELD_ORDER_ITEM : FIELD_ORDER_INVOICE;
  }

  const getFieldOrder = useCallback((): readonly CellColumn[] => {
    return fieldOrderRef.current;
  }, []);

  /* ── Focus cell (public) ─────────────────────────────────────── */

  const focusCell = useCallback(
    (pos: CellPosition | null) => {
      setFocusedCellState(pos);
      onCellChange?.(pos);

      if (pos === null) return;

      // Clamp row to valid range
      const clampedRow = Math.max(0, Math.min(pos.row, itemCountRef.current - 1));
      focusCellElement(clampedRow, pos.col);
    },
    [onCellChange],
  );

  /* ── Cell navigation helpers ─────────────────────────────────── */

  const isLastCell = useCallback(
    (pos: CellPosition): boolean => {
      const fields = fieldOrderRef.current;
      return pos.row >= itemCountRef.current - 1 && pos.col === fields[fields.length - 1];
    },
    [],
  );

  const getItemId = useCallback(
    (rowIndex: number): number | undefined => {
      return itemIdsRef.current[rowIndex];
    },
    [],
  );

  /* ── Navigate to a new cell ──────────────────────────────────── */

  const navigateTo = useCallback(
    (row: number, col: CellColumn) => {
      const clampedRow = Math.max(0, Math.min(row, itemCountRef.current - 1));
      focusCell({ row: clampedRow, col });
    },
    [focusCell],
  );

  /* ── Keyboard handler ────────────────────────────────────────── */

  const handleGridKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const current = focusedCell;
      if (!current) return;

      const fields = fieldOrderRef.current;
      const currentColIndex = fields.indexOf(current.col);
      const maxRow = itemCountRef.current - 1;

      switch (e.key) {
        /* ── Arrow Down ──────────────────────────────────────── */
        case 'ArrowDown': {
          e.preventDefault();
          if (current.row < maxRow) {
            navigateTo(current.row + 1, current.col);
          }
          // No wrap-around — stay at last row
          break;
        }

        /* ── Arrow Up ────────────────────────────────────────── */
        case 'ArrowUp': {
          e.preventDefault();
          if (current.row > 0) {
            navigateTo(current.row - 1, current.col);
          }
          // No wrap-around — stay at first row
          break;
        }

        /* ── Arrow Left ──────────────────────────────────────── */
        case 'ArrowLeft': {
          e.preventDefault();
          if (currentColIndex > 0) {
            navigateTo(current.row, fields[currentColIndex - 1]);
          } else if (current.row > 0) {
            // Wrap to last column of previous row
            navigateTo(current.row - 1, fields[fields.length - 1]);
          }
          break;
        }

        /* ── Arrow Right ─────────────────────────────────────── */
        case 'ArrowRight': {
          e.preventDefault();
          if (currentColIndex < fields.length - 1) {
            navigateTo(current.row, fields[currentColIndex + 1]);
          } else if (current.row < maxRow) {
            // Wrap to first column of next row
            navigateTo(current.row + 1, fields[0]);
          } else {
            // At last column of last row — add a new row and focus its first cell
            onAddNewItem();
            onAddRowAtEnd?.();
            // Focus first cell of new row on next render
            requestAnimationFrame(() => {
              focusCellElement(itemCountRef.current, fields[0]);
            });
          }
          break;
        }

        /* ── Enter / Shift+Enter ──────────────────────────────── */
        case 'Enter': {
          e.preventDefault();

          if (e.shiftKey) {
            // Shift+Enter — move up
            if (current.row > 0) {
              navigateTo(current.row - 1, current.col);
            }
          } else if (current.row < maxRow) {
            // Enter — move down same column
            navigateTo(current.row + 1, current.col);
          } else {
            // Enter on last row — add a new row and focus same column
            onAddNewItem();
            onAddRowAtEnd?.();
            requestAnimationFrame(() => {
              focusCellElement(itemCountRef.current, current.col);
            });
            setFocusedCellState((prev) =>
              prev ? { row: itemCountRef.current, col: prev.col } : null,
            );
          }
          break;
        }

        /* ── Tab ──────────────────────────────────────────────── */
        case 'Tab': {
          if (e.shiftKey) {
            // Shift+Tab — previous cell
            e.preventDefault();
            if (currentColIndex > 0) {
              navigateTo(current.row, fields[currentColIndex - 1]);
            } else if (current.row > 0) {
              navigateTo(current.row - 1, fields[fields.length - 1]);
            }
          } else {
            // Tab — next cell
            e.preventDefault();
            if (currentColIndex < fields.length - 1) {
              navigateTo(current.row, fields[currentColIndex + 1]);
            } else if (current.row < maxRow) {
              navigateTo(current.row + 1, fields[0]);
            } else {
              // Last cell of last row — add a new row
              onAddNewItem();
              onAddRowAtEnd?.();
              requestAnimationFrame(() => {
                focusCellElement(itemCountRef.current, fields[0]);
              });
            }
          }
          break;
        }

        /* ── Alt+I — Insert row ──────────────────────────────── */
        case 'i':
        case 'I': {
          if (e.altKey) {
            e.preventDefault();
            onAddNewItem();
            onAddRowAtEnd?.();
            requestAnimationFrame(() => {
              focusCellElement(itemCountRef.current, fields[0]);
            });
          }
          break;
        }

        /* ── Ctrl+Delete — Remove row ────────────────────────── */
        case 'Delete': {
          if (e.ctrlKey) {
            e.preventDefault();
            const itemId = itemIdsRef.current[current.row];
            if (itemId !== undefined) {
              onRemoveItem(itemId);

              // If there are still items after removal, focus a nearby cell
              const remaining = itemCountRef.current - 1;
              if (remaining > 0) {
                const newRow = Math.min(current.row, remaining - 1);
                const newCol = current.col;
                // Update will happen via the parent re-render
                setFocusedCellState({ row: newRow, col: newCol });
              } else {
                setFocusedCellState(null);
              }
            }
          }
          break;
        }

        default:
          break;
      }
    },
    [focusedCell, navigateTo, onAddNewItem, onAddRowAtEnd, onRemoveItem],
  );

  /* ── API ──────────────────────────────────────────────────────── */

  // Memoize the returned object to avoid unnecessary re-renders
  const api = useMemo(
    () => ({
      focusedCell,
      focusCell,
      handleGridKeyDown,
      getFieldOrder,
      isLastCell,
      getItemId,
    }),
    [focusedCell, focusCell, handleGridKeyDown, getFieldOrder, isLastCell, getItemId],
  );

  return api;
}

export default useInvoiceV2Keyboard;
