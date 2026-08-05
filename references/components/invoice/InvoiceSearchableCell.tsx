import GenericSearchableCell from '../shared/GenericSearchableCell';
import type { SearchableCellProps } from '../../types';

export default function InvoiceSearchableCell({
  value,
  itemId,
  items,
  invoiceItems,
  isLastItem,
  editingCell,
  onSetEditingCell,
  onUpdateItem,
  onAddNewItem,
  onSetPendingFocus,
  formatCurrency,
  getNextField,
}: SearchableCellProps) {
  return (
    <GenericSearchableCell
      value={value}
      itemId={itemId}
      items={items}
      allItems={invoiceItems}
      isLastItem={isLastItem}
      editingCell={editingCell}
      cellField="description"
      onEditingCell={onSetEditingCell}
      onUpdateItem={onUpdateItem}
      onAddNewItem={onAddNewItem}
      onSetPendingFocus={onSetPendingFocus}
      formatCurrency={formatCurrency}
      getNextField={getNextField}
      saveField="description"
    />
  );
}
