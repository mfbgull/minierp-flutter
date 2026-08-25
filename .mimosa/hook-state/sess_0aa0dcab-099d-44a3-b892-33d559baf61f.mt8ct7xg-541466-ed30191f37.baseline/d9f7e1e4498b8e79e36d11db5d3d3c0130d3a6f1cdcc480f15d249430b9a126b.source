import { useState, useEffect, useCallback, memo } from 'react';
import { Edit2 } from 'lucide-react';
import { useFocusCell } from '../../utils/focusCell';

export interface GenericEditableCellProps {
  value: string | number;
  displayValue?: string | number;
  itemId: number;
  field: string;
  type?: string;
  isLastItem: boolean;
  items: Array<{ id: number }>;
  fieldOrder: readonly string[];
  editingCell: string | null;
  onEditingCell: (cellId: string | null) => void;
  onUpdateItem: (itemId: number, field: string, value: unknown) => void;
  onAddNewItem: () => number;
  onSetPendingFocus?: (itemId: number) => void;
  getNextField: (field: string) => string | undefined;
}

const GenericEditableCell = memo(function GenericEditableCell({
  value,
  displayValue,
  itemId,
  field,
  type = 'text',
  isLastItem,
  items,
  fieldOrder,
  editingCell,
  onEditingCell,
  onUpdateItem,
  onAddNewItem,
  onSetPendingFocus,
  getNextField,
}: GenericEditableCellProps) {
  const isEditing = editingCell === `${itemId}-${field}`;
  const [tempValue, setTempValue] = useState(value);
  const { focusTargetCell, isNavigatingRef } = useFocusCell(onEditingCell);

  // Sync tempValue when value changes externally (e.g. item auto-populated) or when entering edit mode
  useEffect(() => {
    if (!isEditing || value !== tempValue) {
      setTempValue(value);
    }
  }, [value, isEditing]);

  const handleSave = useCallback(() => {
    onUpdateItem(itemId, field, tempValue);
    onEditingCell(null);
  }, [itemId, field, tempValue, onUpdateItem, onEditingCell]);



  const moveToCell = useCallback((rowOffset: number, colOffset: number) => {
    const currentItemIndex = items.findIndex((item) => item.id === itemId);
    const currentFieldIndex = fieldOrder.indexOf(field);

    if (rowOffset !== 0) {
      const newItemIndex = currentItemIndex + rowOffset;
      if (newItemIndex >= 0 && newItemIndex < items.length) {
        handleSave();
        const targetId = items[newItemIndex].id;
        // Try the same field first, then walk through fields to find a navigable one
        if (document.querySelector(`[data-cell-id="${targetId}-${field}"]`)) {
          focusTargetCell(targetId, field);
        } else {
          // Field doesn't exist in target row (e.g. amount in packed item) — find first navigable field
          for (const candidateField of fieldOrder) {
            if (document.querySelector(`[data-cell-id="${targetId}-${candidateField}"]`)) {
              focusTargetCell(targetId, candidateField);
              return;
            }
          }
        }
      }
      // ArrowDown at last row — do nothing, only Enter creates new row
    }

    if (colOffset !== 0) {
      // Walk forward/backward through fields, skipping any that don't have a DOM cell (e.g. amount for packed items)
      let newFieldIndex = currentFieldIndex + colOffset;
      while (newFieldIndex >= 0 && newFieldIndex < fieldOrder.length) {
        const candidateField = fieldOrder[newFieldIndex];
        if (document.querySelector(`[data-cell-id="${itemId}-${candidateField}"]`)) {
          handleSave();
          focusTargetCell(itemId, candidateField);
          return;
        }
        newFieldIndex += colOffset;
      }
      // No navigable column found in this direction
      if (colOffset < 0) {
        // ArrowLeft at first field — save and move to previous row
        handleSave();
        moveToCell(-1, 0);
      }
      // ArrowRight at last field — do nothing, stay in edit mode
    }
  }, [items, itemId, field, fieldOrder, handleSave, onAddNewItem, onSetPendingFocus, focusTargetCell]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.ctrlKey && e.key === 'ArrowUp') {
      e.preventDefault();
      if (['quantity', 'rate', 'tax', 'discountValue', 'unit_price'].includes(field)) {
        let newValue = (parseFloat(String(tempValue)) || 0) + 1;
        if (field === 'tax' && newValue > 100) newValue = 100;
        if (field === 'quantity' && newValue < 0) newValue = 0;
        setTempValue(newValue);
      }
      return;
    } else if (e.ctrlKey && e.key === 'ArrowDown') {
      e.preventDefault();
      if (['quantity', 'rate', 'tax', 'discountValue', 'unit_price'].includes(field)) {
        const currentVal = parseFloat(String(tempValue)) || 0;
        let newValue = currentVal - 1;
        if (newValue < 0) newValue = 0;
        setTempValue(newValue);
      }
      return;
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault();
      moveToCell(-1, 0);
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      moveToCell(1, 0);
    } else if (e.key === 'ArrowLeft') {
      const target = e.target as HTMLInputElement;
      const shouldNavigate = type === 'number' || target.selectionStart === 0;
      if (shouldNavigate) {
        e.preventDefault();
        moveToCell(0, -1);
      }
    } else if (e.key === 'ArrowRight') {
      const target = e.target as HTMLInputElement;
      const shouldNavigate = type === 'number' || target.selectionStart === target.value.length;
      if (shouldNavigate) {
        e.preventDefault();
        moveToCell(0, 1);
      }
    } else if (e.key === 'Enter') {
      e.preventDefault();
      handleSave();
      if (isLastItem) {
        // Enter at last row — always add new row
        const newId = onAddNewItem();
        if (onSetPendingFocus) {
          onSetPendingFocus(newId);
        }
      } else {
        moveToCell(1, 0);
      }
    } else if (e.key === 'Tab') {
      e.preventDefault();
      handleSave();
      const nextField = getNextField(field);
      if (nextField) {
        focusTargetCell(itemId, nextField);
      } else if (isLastItem) {
        const newId = onAddNewItem();
        if (onSetPendingFocus) {
          onSetPendingFocus(newId);
        }
      } else {
        moveToCell(1, 0);
      }
    } else if (e.key === 'Escape') {
      setTempValue(value);
      onEditingCell(null);
    }
  }, [tempValue, field, type, itemId, isLastItem, items, fieldOrder, moveToCell, handleSave, focusTargetCell, getNextField, onAddNewItem, onSetPendingFocus, onEditingCell, value]);

  if (isEditing) {
    return (
      <input
        type={type}
        value={tempValue}
        onChange={(e) => setTempValue(e.target.value)}
        onBlur={() => {
          // Skip save if keyboard navigation is in progress (prevents race condition)
          if (!isNavigatingRef.current) {
            handleSave();
          }
        }}
        onKeyDown={handleKeyDown}
        onFocus={(e) => e.target.select()}
        className="editable-input"
        data-cell-id={`${itemId}-${field}`}
      />
    );
  }

  return (
    <div
      data-cell-id={`${itemId}-${field}`}
      onClick={() => {
        setTempValue(value);
        onEditingCell(`${itemId}-${field}`);
      }}
      onFocus={() => {
        setTempValue(value);
        onEditingCell(`${itemId}-${field}`);
      }}
      className="editable-cell"
      tabIndex={0}
    >
      {displayValue ?? value}
      <Edit2 className="edit-icon" />
    </div>
  );
});

export default GenericEditableCell;
