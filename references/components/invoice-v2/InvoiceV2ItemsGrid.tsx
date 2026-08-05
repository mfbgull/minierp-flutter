/**
 * InvoiceV2ItemsGrid — Spreadsheet-style editable items grid with keyboard navigation.
 *
 * Uses useInvoiceV2Keyboard internally for cell navigation.
 * Each cell renders as an input when active, or a clickable display value when inactive.
 * Input cells stopPropagation so the grid-level keyboard handler only fires for display cells.
 */

import { useState, useCallback, useRef, useEffect, useMemo, memo } from 'react';
import { Plus, Trash2 } from 'lucide-react';

import { useInvoiceV2Keyboard } from '../../hooks/useInvoiceV2Keyboard';
import type {
  InvoiceV2FormItem,
  CellColumn,
  InvoiceV2ItemsGridProps,
} from '../../types/invoiceV2';
import { applyLineFieldUpdate, lineIssue } from '../../utils/invoiceLineCalc';



/* ── Shared display cell wrapper ──────────────────────────────── */
interface DisplayCellProps {
  row: number;
  col: CellColumn;
  className?: string;
  children: React.ReactNode;
  onActivate: () => void;
}

const DisplayCell = memo(function DisplayCell({
  row,
  col,
  className = '',
  children,
  onActivate,
}: DisplayCellProps) {
  return (
    <div
      className={`iv2-editable ${className}`}
      data-cell-id={`${row}-${col}`}
      tabIndex={-1}
      onClick={onActivate}
      onFocus={onActivate}
      onKeyDown={(e) => {
        // Enter/Tab triggers edit mode — stop so grid handler doesn't navigate
        if (e.key === 'Enter') {
          e.preventDefault();
          e.stopPropagation();
          onActivate();
        }
      }}
    >
      {children}
    </div>
  );
});

/* ── Searchable description cell (with dropdown) ───────────────── */
interface SearchCellProps {
  row: number;
  item: InvoiceV2FormItem;
  inventoryItems: InvoiceV2ItemsGridProps['inventoryItems'];
  isEditing: boolean;
  isLastRow: boolean;
  onUpdate: (field: string, value: unknown) => void;
  onActivate: () => void;
  onNavigate: (row: number, col: CellColumn) => void;
  onAddRow: () => void;
  fieldOrder: readonly CellColumn[];
  formatCurrency: (amount: number | string | null | undefined) => string;
}

const SearchableDescCell = memo(function SearchableDescCell({
  row,
  item,
  inventoryItems,
  isEditing,
  isLastRow,
  onUpdate,
  onActivate,
  onNavigate,
  onAddRow,
  fieldOrder,
  formatCurrency,
}: SearchCellProps) {
  const [tempValue, setTempValue] = useState(item.description);
  const [filtered, setFiltered] = useState<typeof inventoryItems>([]);
  const [showDropdown, setShowDropdown] = useState(false);
  const [selectedIdx, setSelectedIdx] = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);

  // Sync temp value when not editing
  useEffect(() => {
    if (!isEditing) setTempValue(item.description);
  }, [item.description, isEditing]);

  const availableItems = inventoryItems.filter((inv) => {
    // Only show sellable items (not raw materials)
    if (inv.is_raw_material) return false;
    if (!inv.is_finished_good && !inv.is_purchased) return false;
    // Exclude the currently selected item
    if (item.itemId && inv.id === Number(item.itemId)) return false;
    return true;
  });

  const filterItems = useCallback(
    (query: string) => {
      if (!query.trim()) {
        setFiltered(availableItems.slice(0, 10));
        setSelectedIdx(0);
        setShowDropdown(availableItems.length > 0);
        return;
      }
      const q = query.toLowerCase();
      const matches = availableItems.filter(
        (inv) =>
          inv.item_name.toLowerCase().includes(q) ||
          inv.item_code.toLowerCase().includes(q),
      );
      setFiltered(matches.slice(0, 10));
      setSelectedIdx(matches.length > 0 ? 0 : -1);
      setShowDropdown(matches.length > 0);
    },
    [availableItems],
  );

  const selectItem = useCallback(
    (inv: (typeof inventoryItems)[number]) => {
      // Single atomic patch: identity + pricing + loose-item calculation settings
      onUpdate('patch', {
        itemId: inv.id,
        description: inv.item_name,
        rate: inv.standard_selling_price || 0,
        sale_type: inv.sale_type || 'packed',
        qty_decimal_precision: inv.qty_decimal_precision || 0,
        rounding_step: inv.rounding_step ?? null,
        amount: 0,
        lastEditedField: null,
      });
      setTempValue(inv.item_name);
      setShowDropdown(false);
      setFiltered([]);
      // Move to quantity column
      onNavigate(row, 'quantity');
    },
    [onUpdate, onNavigate, row],
  );

  const handleSave = useCallback(() => {
    if (tempValue !== item.description) {
      onUpdate('description', tempValue);
    }
    setShowDropdown(false);
    setFiltered([]);
  }, [tempValue, item.description, onUpdate]);

  const closeDropdown = useCallback(() => {
    setShowDropdown(false);
    setFiltered([]);
    setSelectedIdx(-1);
  }, []);

  if (isEditing) {
    return (
      <div className="searchable-cell-container" data-cell-id={`${row}-description`}>
        <input
          ref={inputRef}
          type="text"
          className="iv2-editable-input"
          value={tempValue}
          placeholder="Type to search items..."
          onChange={(e) => {
            const v = e.target.value;
            setTempValue(v);
            filterItems(v);
          }}
          onFocus={(e) => {
            e.target.select();
            filterItems(tempValue);
          }}
          onBlur={() => {
            setTimeout(() => {
              if (!showDropdown) {
                handleSave();
              }
            }, 180);
          }}
          onKeyDown={(e) => {
            // Dropdown navigation
            if (showDropdown && filtered.length > 0) {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                e.stopPropagation();
                setSelectedIdx((p) => (p < filtered.length - 1 ? p + 1 : 0));
                return;
              }
              if (e.key === 'ArrowUp') {
                e.preventDefault();
                e.stopPropagation();
                if (selectedIdx === 0) {
                  closeDropdown();
                  return;
                }
                setSelectedIdx((p) => (p > 0 ? p - 1 : filtered.length - 1));
                return;
              }
              if (e.key === 'Enter' && selectedIdx >= 0 && filtered[selectedIdx]) {
                e.preventDefault();
                e.stopPropagation();
                selectItem(filtered[selectedIdx]);
                return;
              }
              if (e.key === 'Escape') {
                e.preventDefault();
                e.stopPropagation();
                closeDropdown();
                return;
              }
            }

            // Stop propagation for navigation keys so the grid handler doesn't interfere
            if (
              e.key === 'ArrowDown' ||
              e.key === 'ArrowUp' ||
              e.key === 'ArrowLeft' ||
              e.key === 'ArrowRight'
            ) {            if (e.key === 'ArrowDown' &&
                !showDropdown &&
                selectedIdx < 0
              ) {
                e.preventDefault();
                e.stopPropagation();
                handleSave();
                if (isLastRow) {
                  onAddRow();
                } else {
                  onNavigate(row + 1, 'description');
                }
                return;
              }
              if (e.key === 'ArrowUp' && row > 0) {
                e.preventDefault();
                e.stopPropagation();
                handleSave();
                onNavigate(row - 1, 'description');
                return;
              }
              // For left/right, let cursor move within input but stop grid handler
              e.stopPropagation();
              return;
            }

            if (e.key === 'Enter') {
              e.preventDefault();
              e.stopPropagation();
              if (!showDropdown) {
                handleSave();
                if (isLastRow) {
                  onAddRow();
                } else {
                  onNavigate(row + 1, 'quantity');
                }
              }
              return;
            }

            if (e.key === 'Tab') {
              e.preventDefault();
              e.stopPropagation();
              if (!showDropdown) {
                handleSave();
                if (fieldOrder.length > 1) {
                  if (isLastRow) {
                    // Tab from last desc cell — skip to next row's qty via add
                    onAddRow();
                  } else {
                    onNavigate(row, fieldOrder[1]);
                  }
                } else {
                  if (isLastRow) {
                    onAddRow();
                  } else {
                    onNavigate(row + 1, 'description');
                  }
                }
              }
              return;
            }

            if (e.key === 'Escape') {
              e.preventDefault();
              e.stopPropagation();
              setTempValue(item.description);
              closeDropdown();
              return;
            }
          }}
        />

        {/* Dropdown */}
        {showDropdown && (
          <div className="item-dropdown" style={{ position: 'absolute', zIndex: 999 }}>
            {filtered.length > 0 ? (
              filtered.map((inv, idx) => (
                <div
                  key={inv.id}
                  className={`item-dropdown-option ${idx === selectedIdx ? 'selected' : ''}`}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    selectItem(inv);
                  }}
                  onMouseEnter={() => setSelectedIdx(idx)}
                >
                  <div className="item-dropdown-main">
                    <span className="item-dropdown-name">{inv.item_name}</span>
                    <span className="item-dropdown-code">{inv.item_code}</span>
                  </div>
                  <div className="item-dropdown-details">
                    <span className="item-dropdown-stock">
                      Stock: {inv.current_stock || 0}
                    </span>
                    <span className="item-dropdown-price">
                      {formatCurrency(inv.standard_selling_price || 0)}
                    </span>
                  </div>
                </div>
              ))
            ) : tempValue.trim() ? (
              <div className="item-dropdown-no-results">No products found</div>
            ) : null}
          </div>
        )}
      </div>
    );
  }

  return (
    <DisplayCell row={row} col="description" onActivate={onActivate}>
      {item.description || (
        <span style={{ color: 'var(--iv2-text-tertiary)' }}>Click to add item...</span>
      )}
    </DisplayCell>
  );
});

/* ── Editable number cell ──────────────────────────────────────── */
interface NumberCellProps {
  row: number;
  col: CellColumn;
  value: number;
  isEditing: boolean;
  isLastRow: boolean;
  onUpdate: (field: string, value: unknown) => void;
  onActivate: () => void;
  onNavigate: (row: number, col: CellColumn) => void;
  onAddRow: () => void;
  fieldOrder: readonly CellColumn[];
  /** Decimal places to display (from item master qty_decimal_precision) */
  decimals?: number;
}

const EditableNumberCell = memo(function EditableNumberCell({
  row,
  col,
  value,
  isEditing,
  isLastRow,
  onUpdate,
  onActivate,
  onNavigate,
  onAddRow,
  fieldOrder,
  decimals = 0,
}: NumberCellProps) {
  const [tempValue, setTempValue] = useState(String(value));

  useEffect(() => {
    if (!isEditing) setTempValue(String(value));
  }, [value, isEditing]);

  const handleSave = useCallback(() => {
    const parsed = parseFloat(tempValue);
    if (!isNaN(parsed) && parsed !== value) {
      onUpdate(col, parsed);
    } else if (isNaN(parsed)) {
      setTempValue(String(value));
    }
  }, [tempValue, value, col, onUpdate]);

  const colIndex = fieldOrder.indexOf(col);

  if (isEditing) {
    return (
      <input
        type="number"
        className="iv2-editable-input"
        data-cell-id={`${row}-${col}`}
        value={tempValue}
        onChange={(e) => setTempValue(e.target.value)}
        onFocus={(e) => e.target.select()}
        onBlur={handleSave}
        onKeyDown={(e) => {
          // Ctrl+ArrowUp/Down to increment/decrement
          if (e.ctrlKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
            e.preventDefault();
            e.stopPropagation();
            const step = e.key === 'ArrowUp' ? 1 : -1;
            const current = parseFloat(tempValue) || 0;
            const newVal = Math.max(0, current + step);
            setTempValue(String(newVal));
            onUpdate(col, newVal);
            return;
          }

          // Arrow keys — stop propagation for cursor but navigate at boundaries
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            e.stopPropagation();
            handleSave();
            if (isLastRow) {
              onAddRow();
            } else {
              onNavigate(row + 1, col);
            }
            return;
          }
          if (e.key === 'ArrowUp') {
            e.preventDefault();
            e.stopPropagation();
            handleSave();
            if (row > 0) onNavigate(row - 1, col);
            return;
          }
          if (e.key === 'ArrowLeft') {
            e.stopPropagation();
            // Let cursor move left within input
            return;
          }
          if (e.key === 'ArrowRight') {
            e.stopPropagation();
            // Let cursor move right within input
            return;
          }
          if (e.key === 'Enter') {
            e.preventDefault();
            e.stopPropagation();
            handleSave();
            if (isLastRow) {
              onAddRow();
            } else {
              onNavigate(row + 1, col);
            }
            return;
          }

          if (e.key === 'Tab') {
            e.preventDefault();
            e.stopPropagation();
            handleSave();
            if (colIndex < fieldOrder.length - 1) {
              onNavigate(row, fieldOrder[colIndex + 1]);
            } else if (isLastRow) {
              onAddRow();
            } else {
              onNavigate(row + 1, fieldOrder[0]);
            }
            return;
          }

          if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            setTempValue(String(value));
            return;
          }
        }}
        step="any"
        min="0"
      />
    );
  }

  return (
    <DisplayCell row={row} col={col} onActivate={onActivate}>
      {decimals > 0 ? (value || 0).toFixed(decimals) : value || 0}
    </DisplayCell>
  );
});

/* ── Discount cell (type selector + value input) ───────────────── */
interface DiscountCellProps {
  row: number;
  item: InvoiceV2FormItem;
  isEditing: boolean;
  isLastRow: boolean;
  onUpdate: (field: string, value: unknown) => void;
  onActivate: () => void;
  onNavigate: (row: number, col: CellColumn) => void;
  onAddRow: () => void;
  fieldOrder: readonly CellColumn[];
  getCurrencySymbol: () => string;
}

const EditableDiscountCell = memo(function EditableDiscountCell({
  row,
  item,
  isEditing,
  isLastRow,
  onUpdate,
  onActivate,
  onNavigate,
  onAddRow,
  fieldOrder,
  getCurrencySymbol,
}: DiscountCellProps) {
  const discountColIndex = fieldOrder.indexOf('discountValue');
  const [tempValue, setTempValue] = useState(String(item.discount.value));

  useEffect(() => {
    if (!isEditing) setTempValue(String(item.discount.value));
  }, [item.discount.value, isEditing]);

  const handleSave = useCallback(() => {
    const parsed = parseFloat(tempValue);
    if (!isNaN(parsed) && parsed !== item.discount.value) {
      onUpdate('discountValue', parsed);
    } else if (isNaN(parsed)) {
      setTempValue(String(item.discount.value));
    }
  }, [tempValue, item.discount.value, onUpdate]);

  if (isEditing) {
    return (
      <div className="iv2-discount-controls">
        <select
          value={item.discount.type}
          onChange={(e) =>
            onUpdate('discountType', e.target.value as 'percentage' | 'flat')
          }
          className="discount-type-select-modern"
          onMouseDown={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
          <option value="percentage">%</option>
          <option value="flat">{getCurrencySymbol()}</option>
        </select>
        <input
          type="number"
          className="iv2-editable-input"
          data-cell-id={`${row}-discountValue`}
          value={tempValue}
          onChange={(e) => setTempValue(e.target.value)}
          onFocus={(e) => e.target.select()}
          onBlur={handleSave}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              e.stopPropagation();
              handleSave();
              if (isLastRow) {
                onAddRow();
              } else {
                onNavigate(row + 1, 'discountValue');
              }
              return;
            }
            if (e.key === 'ArrowUp') {
              e.preventDefault();
              e.stopPropagation();
              handleSave();
              if (row > 0) onNavigate(row - 1, 'discountValue');
              return;
            }
            if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
              e.stopPropagation();
              return;
            }
            if (e.key === 'Enter') {
              e.preventDefault();
              e.stopPropagation();
              handleSave();
              if (isLastRow) {
                onAddRow();
              } else {
                onNavigate(row + 1, 'discountValue');
              }
              return;
            }
            if (e.key === 'Tab') {
              e.preventDefault();
              e.stopPropagation();
              handleSave();
              if (discountColIndex < fieldOrder.length - 1) {
                onNavigate(row, fieldOrder[discountColIndex + 1]);
              } else if (isLastRow) {
                onAddRow();
              } else {
                onNavigate(row + 1, fieldOrder[0]);
              }
              return;
            }
            if (e.key === 'Escape') {
              e.preventDefault();
              e.stopPropagation();
              setTempValue(String(item.discount.value));
              return;
            }
          }}
          step="any"
          min="0"
        />
      </div>
    );
  }

  const colIndex = fieldOrder.indexOf('discountValue');

  return (
    <DisplayCell row={row} col="discountValue" onActivate={onActivate}>
      <span style={{ marginRight: '0.25rem', color: 'var(--iv2-text-tertiary)' }}>
        {item.discount.type === 'percentage' ? '%' : getCurrencySymbol()}
      </span>
      {item.discount.value || 0}
    </DisplayCell>
  );
});

/* ── Main InvoiceV2ItemsGrid ────────────────────────────────────── */
export default function InvoiceV2ItemsGrid({
  items,
  discountScope,
  inventoryItems,
  onUpdateItem,
  onRemoveItem,
  onAddNewItem,
  onUpdateDiscountScope,
  formatCurrency,
  calculateItemTotal,
  getCurrencySymbol,
}: InvoiceV2ItemsGridProps) {
  /* ── Internal keyboard hook ───────────────────────────────── */
  const {
    focusedCell,
    focusCell,
    handleGridKeyDown,
    getFieldOrder,
  } = useInvoiceV2Keyboard({
    itemCount: items.length,
    discountScope,
    onAddNewItem,
    onRemoveItem,
    itemIds: items.map((i) => i.id),
  });

  const fieldOrder = getFieldOrder();
  const amountFieldOrder = useMemo<readonly CellColumn[]>(
    () => [...fieldOrder, 'amount'],
    [fieldOrder],
  );

  /* ── Item row-level update wrapper ─────────────────────────── */
  const handleUpdateItemField = useCallback(
    (itemId: number, field: string, value: unknown) => {
      const item = items.find((i) => i.id === itemId);

      // quantity/rate/amount all route through the shared calculation so packed
      // and loose lines stay consistent and the driver field is preserved.
      if (item && (field === 'quantity' || field === 'rate' || field === 'amount')) {
        onUpdateItem(itemId, 'patch', applyLineFieldUpdate(item, field, Number(value) || 0));
        return;
      }

      onUpdateItem(itemId, field, value);
    },
    [items, onUpdateItem],
  );

  /* ── Navigate helper (wraps focusCell with row clamping) ──── */
  const navigate = useCallback(
    (row: number, col: CellColumn) => {
      const clamped = Math.max(0, Math.min(row, items.length - 1));
      focusCell({ row: clamped, col });
    },
    [focusCell, items.length],
  );

  /* ── Activate edit for a cell ──────────────────────────────── */
  const activate = useCallback(
    (row: number, col: CellColumn) => {
      focusCell({ row, col });
    },
    [focusCell],
  );

  /* ── Add new row at end ────────────────────────────────────── */
  const handleAddRow = useCallback(() => {
    const newId = onAddNewItem();
    // Focus the description cell of the new row after render
    requestAnimationFrame(() => {
      const newRow = items.length; // after add, new item is at this index
      focusCell({ row: newRow, col: 'description' });
    });
    return newId;
  }, [onAddNewItem, focusCell, items.length]);

  /* ── Add row from keyboard (Enter on last row) ─────────────── */
  const handleAddRowFromKeyboard = useCallback(() => {
    onAddNewItem();
    requestAnimationFrame(() => {
      const newRow = items.length;
      focusCell({ row: newRow, col: 'description' });
    });
  }, [onAddNewItem, focusCell, items.length]);

  /* ── Delete row handler ────────────────────────────────────── */
  const handleRemoveItem = useCallback(
    (itemId: number, index: number) => {
      if (items.length <= 1) return; // Keep at least 1 row
      onRemoveItem(itemId);
      // Focus nearby cell after removal
      const remaining = items.length - 1;
      const newRow = Math.min(index, remaining - 1);
      if (newRow >= 0) {
        requestAnimationFrame(() => {
          focusCell({ row: newRow, col: 'description' });
        });
      }
    },
    [items.length, onRemoveItem, focusCell],
  );

  /* ── Discount scope toggle ─────────────────────────────────── */
  const handleDiscountScopeChange = useCallback(
    (scope: 'item' | 'invoice') => {
      onUpdateDiscountScope?.(scope);
    },
    [onUpdateDiscountScope],
  );

  return (
    <>
      {/* Grid Header */}
      <div className="iv2-items-header">
        <div className="iv2-items-header-left">
          <h3 style={{ margin: 0, fontSize: '0.8125rem', fontWeight: 600, color: 'var(--iv2-text)' }}>
            Line Items
          </h3>
          <div className="iv2-discount-toggle">
            <span style={{ fontSize: '0.6875rem', color: 'var(--iv2-text-tertiary)', textTransform: 'uppercase' }}>
              Discount:
            </span>
            <label>
              <input
                type="radio"
                name="iv2-discount-scope"
                value="invoice"
                checked={discountScope === 'invoice'}
                onChange={() => handleDiscountScopeChange('invoice')}
              />
              <span style={{ fontSize: '0.75rem' }}>Invoice Level</span>
            </label>
            <label>
              <input
                type="radio"
                name="iv2-discount-scope"
                value="item"
                checked={discountScope === 'item'}
                onChange={() => handleDiscountScopeChange('item')}
              />
              <span style={{ fontSize: '0.75rem' }}>Per Item</span>
            </label>
          </div>
        </div>
        <button
          onClick={handleAddRow}
          className="iv2-btn"
          style={{ padding: '0.25rem 0.625rem', fontSize: '0.75rem' }}
        >
          <Plus size={14} />
          Add Item
        </button>
      </div>

      {/* Grid */}
      <div
        className="iv2-grid-wrapper"
        tabIndex={0}
        onKeyDown={handleGridKeyDown}
      >
        <table className="iv2-grid">
          <thead>
            <tr>
              <th className="text-center" style={{ width: '2.25rem' }}>#</th>
              <th className="text-left iv2-cell-desc">Description</th>
              <th className="text-right iv2-cell-qty">Qty</th>
              <th className="text-right iv2-cell-rate">Rate</th>
              {discountScope === 'item' && (
                <th className="text-right iv2-cell-disc">Discount</th>
              )}
              <th className="text-right iv2-cell-tax">Tax %</th>
              <th className="text-right iv2-cell-amount">Amount</th>
              <th className="text-center iv2-cell-delete"></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item, idx) => {
              const isEditing = focusedCell?.row === idx;
              return (
                <tr key={item.id}>
                  {/* Row number */}
                  <td className="iv2-cell-row">{idx + 1}</td>

                  {/* Description (searchable) */}
                  <td className="iv2-cell-desc" style={{ position: 'relative' }}>
                    <SearchableDescCell
                      row={idx}
                      item={item}
                      inventoryItems={inventoryItems}
                      isEditing={isEditing && focusedCell?.col === 'description'}
                      isLastRow={idx === items.length - 1}
                      onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                      onActivate={() => activate(idx, 'description')}
                      onNavigate={navigate}
                      onAddRow={handleAddRowFromKeyboard}
                      fieldOrder={fieldOrder}
                      formatCurrency={formatCurrency}
                    />
                  </td>

                  {/* Quantity */}
                  <td className="iv2-cell-qty">
                    <EditableNumberCell
                      row={idx}
                      col="quantity"
                      value={item.quantity}
                      isEditing={isEditing && focusedCell?.col === 'quantity'}
                      isLastRow={idx === items.length - 1}
                      onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                      onActivate={() => activate(idx, 'quantity')}
                      onNavigate={navigate}
                      onAddRow={handleAddRowFromKeyboard}
                      fieldOrder={fieldOrder}
                      decimals={item.qty_decimal_precision || 0}
                    />
                  </td>

                  {/* Rate */}
                  <td className="iv2-cell-rate">
                    <EditableNumberCell
                      row={idx}
                      col="rate"
                      value={item.rate}
                      isEditing={isEditing && focusedCell?.col === 'rate'}
                      isLastRow={idx === items.length - 1}
                      onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                      onActivate={() => activate(idx, 'rate')}
                      onNavigate={navigate}
                      onAddRow={handleAddRowFromKeyboard}
                      fieldOrder={fieldOrder}
                    />
                  </td>

                  {/* Discount (per item mode only) */}
                  {discountScope === 'item' && (
                    <td className="iv2-cell-disc">
                      <EditableDiscountCell
                        row={idx}
                        item={item}
                        isEditing={isEditing && focusedCell?.col === 'discountValue'}
                        isLastRow={idx === items.length - 1}
                        onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                        onActivate={() => activate(idx, 'discountValue')}
                        onNavigate={navigate}
                        onAddRow={handleAddRowFromKeyboard}
                        fieldOrder={fieldOrder}
                        getCurrencySymbol={getCurrencySymbol}
                      />
                    </td>
                  )}

                  {/* Tax */}
                  <td className="iv2-cell-tax">
                    <EditableNumberCell
                      row={idx}
                      col="tax"
                      value={item.tax}
                      isEditing={isEditing && focusedCell?.col === 'tax'}
                      isLastRow={idx === items.length - 1}
                      onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                      onActivate={() => activate(idx, 'tax')}
                      onNavigate={navigate}
                      onAddRow={handleAddRowFromKeyboard}
                      fieldOrder={fieldOrder}
                    />
                  </td>

                  {/* Amount — editable for loose items, calculated display for packed */}
                  <td className="iv2-cell-amount">
                    {item.sale_type === 'loose' ? (
                      <>
                        <EditableNumberCell
                          row={idx}
                          col="amount"
                          value={item.amount || 0}
                          isEditing={isEditing && focusedCell?.col === 'amount'}
                          isLastRow={idx === items.length - 1}
                          onUpdate={(field, value) => handleUpdateItemField(item.id, field, value)}
                          onActivate={() => activate(idx, 'amount')}
                          onNavigate={navigate}
                          onAddRow={handleAddRowFromKeyboard}
                          // Amount is last in the row's tab sequence for loose items;
                          // it is not in the grid-level field order (packed rows have no input there).
                          fieldOrder={amountFieldOrder}
                          decimals={2}
                        />
                        {lineIssue(item) && (
                          <div
                            className="iv2-line-issue"
                            style={{
                              fontSize: '0.6875rem',
                              color:
                                lineIssue(item)!.severity === 'error' ? '#dc2626' : '#d97706',
                            }}
                          >
                            {lineIssue(item)!.message}
                          </div>
                        )}
                      </>
                    ) : (
                      formatCurrency(calculateItemTotal(item))
                    )}
                  </td>

                  {/* Delete */}
                  <td className="iv2-cell-delete">
                    <button
                      onClick={() => handleRemoveItem(item.id, idx)}
                      title="Remove item"
                      disabled={items.length <= 1}
                      style={{
                        opacity: items.length <= 1 ? 0.2 : undefined,
                        cursor: items.length <= 1 ? 'not-allowed' : undefined,
                      }}
                    >
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}
