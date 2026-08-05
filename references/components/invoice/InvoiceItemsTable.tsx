import { memo } from 'react';
import { Plus, Trash2 } from 'lucide-react';

import InvoiceSearchableCell from './InvoiceSearchableCell';
import InvoiceEditableCell from './InvoiceEditableCell';
import PriceHistoryHint from './PriceHistoryHint';
import KeyboardShortcutsHelp from './KeyboardShortcutsHelp';
import type { ItemsTableProps } from '../../types';
import { getFieldOrder } from '../../utils/invoiceCalculations';
import { lineIssue } from '../../utils/invoiceLineCalc';

const InvoiceItemsTable = memo(function InvoiceItemsTable({
  invoice,
  items,
  editingCell,
  errors,
  priceHint,
  onSetEditingCell,
  onUpdateItem,
  onRemoveItem,
  onAddNewItem,
  onSetPendingFocus,
  onSetPriceHint,
  onUpdateInvoice,
  onSetNewItemId,
  formatCurrency,
  getCurrencySymbol,
  calculateItemTotal,
  calculateSubtotal,
  calculateTax,
  calculateDiscount,
  calculateTotal,
  getNextField,
}: ItemsTableProps) {
  const fieldOrder = getFieldOrder(invoice.discountScope);

  return (
    <>
      {/* Items Header — Row 2: Discount + Dates + Add Item */}
      <div className="items-header-modern">
        <div className="items-header-left">
          <h3 className="items-title-modern">Line Items</h3>
          <KeyboardShortcutsHelp />
          <div className="discount-scope-controls-modern">
            <span className="discount-label-modern">Discount:</span>
            <label className="discount-scope-option-modern">
              <input
                type="radio"
                name="discountScope"
                value="invoice"
                checked={invoice.discountScope === 'invoice'}
                onChange={(e) => onUpdateInvoice({ discountScope: e.target.value as 'item' | 'invoice' })}
              />
              <span>Invoice Level</span>
            </label>
            <label className="discount-scope-option-modern">
              <input
                type="radio"
                name="discountScope"
                value="item"
                checked={invoice.discountScope === 'item'}
                onChange={(e) => onUpdateInvoice({ discountScope: e.target.value as 'item' | 'invoice' })}
              />
              <span>Per Item</span>
            </label>
          </div>
        </div>
        <div className="items-header-center">
          <div className="items-date-field">
            <label className="date-label">Invoice Date</label>
            <input
              type="date"
              className="date-input"
              value={invoice.invoice_date}
              onChange={(e) => onUpdateInvoice({ invoice_date: e.target.value })}
            />
          </div>
          <div className="items-date-field">
            <label className="date-label">Due Date</label>
            <input
              type="date"
              className="date-input"
              value={invoice.due_date}
              onChange={(e) => onUpdateInvoice({ due_date: e.target.value })}
            />
          </div>
        </div>
        <button
          onClick={() => {
            const newId = onAddNewItem();
            onSetNewItemId(newId);
          }}
          className="add-item-btn-modern"
        >
          <Plus className="action-icon" />
          Add Item
        </button>
      </div>
      {errors.items && (
        <div className="field-error items-error">{errors.items}</div>
      )}

      {/* ARIA live region for row announcements */}
      <div className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {invoice.items.length} items in invoice
      </div>

      {/* Items Table */}
      <div className="items-table-container-modern">
        <table
          className="items-table-modern"
          role="grid"
          aria-rowcount={invoice.items.length}
          aria-colcount={invoice.discountScope === 'item' ? 8 : 7}
          aria-label="Invoice line items"
        >
          <thead role="rowgroup">
            <tr role="row">
              <th role="columnheader" aria-colindex={1} className="text-center serial-col">#</th>
              <th role="columnheader" aria-colindex={2} className="text-left description-col">Description</th>
              <th role="columnheader" aria-colindex={3} className="text-right quantity-col">Qty</th>
              <th role="columnheader" aria-colindex={4} className="text-right rate-col">Rate</th>
              {invoice.discountScope === 'item' && (
                <th role="columnheader" aria-colindex={5} className="text-right discount-col">Discount</th>
              )}
              <th role="columnheader" aria-colindex={invoice.discountScope === 'item' ? 6 : 5} className="text-right tax-col">Tax %</th>
              <th role="columnheader" aria-colindex={invoice.discountScope === 'item' ? 7 : 6} className="text-right amount-col">Amount</th>
              <th role="columnheader" aria-colindex={invoice.discountScope === 'item' ? 8 : 7} className="delete-col" aria-label="Actions"></th>
            </tr>
          </thead>
          <tbody role="rowgroup">
            {invoice.items.map((item, index) => (
              <tr key={item.id} role="row" aria-rowindex={index + 2}>
                <td role="gridcell" aria-colindex={1} className="text-center serial-col" aria-readonly>{index + 1}</td>
                <td role="gridcell" aria-colindex={2} className="invoice-item-cell">
                  <InvoiceSearchableCell
                    value={item.description}
                    itemId={item.id}
                    items={items}
                    invoiceItems={invoice.items}
                    isLastItem={index === invoice.items.length - 1}
                    editingCell={editingCell}
                    onSetEditingCell={onSetEditingCell}
                    onUpdateItem={onUpdateItem}
                    onAddNewItem={onAddNewItem}
                    onSetPendingFocus={onSetPendingFocus}
                    formatCurrency={formatCurrency}
                    getNextField={(f) => getNextField(f, invoice.discountScope)}
                  />
                </td>
                <td role="gridcell" aria-colindex={3} className="text-right invoice-item-cell quantity-cell">
                  <InvoiceEditableCell
                    value={
                      item.qty_decimal_precision
                        ? item.quantity.toFixed(item.qty_decimal_precision)
                        : item.quantity
                    }
                    itemId={item.id}
                    field="quantity"
                    type="number"
                    isLastItem={index === invoice.items.length - 1}
                    editingCell={editingCell}
                    items={invoice.items}
                    fieldOrder={fieldOrder}
                    onSetEditingCell={(cellId) => onSetEditingCell(cellId)}
                    onUpdateItem={onUpdateItem}
                    onAddNewItem={onAddNewItem}
                    onSetPendingFocus={onSetPendingFocus}
                    getNextField={(f) => getNextField(f, invoice.discountScope)}
                  />
                  {item.unit_of_measure && editingCell !== `${item.id}-quantity` && (
                    <span className="unit-of-measure">{item.unit_of_measure}</span>
                  )}
                </td>
                <td role="gridcell" aria-colindex={4} className="text-right rate-cell-container invoice-item-cell" data-rate-cell={item.id}>
                  <InvoiceEditableCell
                    value={item.rate.toFixed(2)}
                    itemId={item.id}
                    field="rate"
                    type="number"
                    isLastItem={index === invoice.items.length - 1}
                    editingCell={editingCell}
                    items={invoice.items}
                    fieldOrder={fieldOrder}
                    onSetEditingCell={(cellId) => onSetEditingCell(cellId)}
                    onUpdateItem={onUpdateItem}
                    onAddNewItem={onAddNewItem}
                    onSetPendingFocus={onSetPendingFocus}
                    getNextField={(f) => getNextField(f, invoice.discountScope)}
                  />
                </td>
                {invoice.discountScope === 'item' && (
                  <td role="gridcell" aria-colindex={5} className="text-right invoice-item-cell">
                    <div className="discount-cell-modern">
                      <select
                        value={item.discount.type}
                        onChange={(e) => onUpdateItem(item.id, 'discountType', e.target.value)}
                        className="discount-type-select-modern"
                      >
                        <option value="percentage">%</option>
                        <option value="flat">{getCurrencySymbol()}</option>
                      </select>
                      <InvoiceEditableCell
                        value={item.discount.value}
                        itemId={item.id}
                        field="discountValue"
                        type="number"
                        isLastItem={index === invoice.items.length - 1}
                        editingCell={editingCell}
                        items={invoice.items}
                        fieldOrder={fieldOrder}
                        onSetEditingCell={(cellId) => onSetEditingCell(cellId)}
                        onUpdateItem={onUpdateItem}
                        onAddNewItem={onAddNewItem}
                        onSetPendingFocus={onSetPendingFocus}
                        getNextField={(f) => getNextField(f, invoice.discountScope)}
                      />
                    </div>
                  </td>
                )}
                <td role="gridcell" aria-colindex={invoice.discountScope === 'item' ? 6 : 5} className="text-right invoice-item-cell">
                  <InvoiceEditableCell
                    value={item.tax}
                    itemId={item.id}
                    field="tax"
                    type="number"
                    isLastItem={index === invoice.items.length - 1}
                    editingCell={editingCell}
                    items={invoice.items}
                    fieldOrder={fieldOrder}
                    onSetEditingCell={(cellId) => onSetEditingCell(cellId)}
                    onUpdateItem={onUpdateItem}
                    onAddNewItem={onAddNewItem}
                    onSetPendingFocus={onSetPendingFocus}
                    getNextField={(f) => getNextField(f, invoice.discountScope)}
                  />
                </td>
                <td role="gridcell" aria-colindex={invoice.discountScope === 'item' ? 7 : 6} className="text-right amount-cell-modern">
                  {item.sale_type === 'loose' ? (
                    <>
                      <InvoiceEditableCell
                        value={(item.amount || 0).toFixed(2)}
                        displayValue={formatCurrency(item.amount || 0)}
                        itemId={item.id}
                        field="amount"
                        type="number"
                        isLastItem={index === invoice.items.length - 1}
                        editingCell={editingCell}
                        items={invoice.items}
                        fieldOrder={fieldOrder}
                        onSetEditingCell={(cellId) => onSetEditingCell(cellId)}
                        onUpdateItem={onUpdateItem}
                        onAddNewItem={onAddNewItem}
                        onSetPendingFocus={onSetPendingFocus}
                        getNextField={(f) => getNextField(f, invoice.discountScope)}
                      />
                      {lineIssue(item) && (
                        <div
                          className="field-error"
                          style={{
                            fontSize: '0.6875rem',
                            color: lineIssue(item)!.severity === 'error' ? '#dc2626' : '#d97706',
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
                <td role="gridcell" aria-colindex={invoice.discountScope === 'item' ? 8 : 7} className="text-center invoice-item-cell">
                  <button
                    onClick={() => onRemoveItem(item.id)}
                    className="remove-btn-modern"
                    aria-label={`Remove item ${index + 1}: ${item.description || 'empty'}`}
                    title="Remove item"
                  >
                    <Trash2 className="trash-icon" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Price History Tooltip */}
      {priceHint && priceHint.history && (
        <div
          className="price-hint-backdrop"
          onClick={(e) => {
            if (e.target === e.currentTarget) {
              onSetPriceHint(null);
            }
          }}
        >
          <div
            className="price-hint-container"
            onMouseDown={(e) => {
              e.preventDefault();
            }}
          >
            <PriceHistoryHint
              history={priceHint.history}
              currentPrice={priceHint.currentPrice}
              onClose={() => onSetPriceHint(null)}
            />
          </div>
        </div>
      )}

      {/* Totals + Notes & Terms Row */}
      <div style={{ display: 'flex', gap: '1rem', alignItems: 'flex-start', marginBottom: '1.5rem' }}>
        {/* Notes & Terms */}
        <div className="invoice-footer-modern" style={{ flex: 1, minWidth: 0 }}>
          <div>
            <label className="footer-label">NOTES</label>
            <textarea
              value={invoice.notes}
              onChange={(e) => onUpdateInvoice({ notes: e.target.value })}
              rows={3}
              className="footer-textarea"
              placeholder="Thank you for your business..."
            />
          </div>
          <div>
            <label className="footer-label">TERMS & CONDITIONS</label>
            <textarea
              value={invoice.terms}
              onChange={(e) => onUpdateInvoice({ terms: e.target.value })}
              rows={3}
              className="footer-textarea"
              placeholder="Payment terms..."
            />
          </div>
        </div>

        {/* Totals */}
        <div className="totals-breakdown-modern" style={{ width: '280px', flexShrink: 0 }}>
          <div className="total-row-modern">
            <span>Subtotal:</span>
            <span className="total-value">{formatCurrency(calculateSubtotal())}</span>
          </div>

          {invoice.discountScope === 'invoice' ? (
            <div className="total-row-modern">
              <div className="discount-input-modern">
                <span>Discount:</span>
                <div className="discount-controls">
                  <select
                    value={invoice.discount.type}
                    onChange={(e) => onUpdateInvoice({
                      discount: { ...invoice.discount, type: e.target.value as 'flat' | 'percentage' }
                    })}
                    className="discount-type-select-modern"
                  >
                    <option value="percentage">%</option>
                    <option value="flat">{getCurrencySymbol()}</option>
                  </select>
                  <input
                    type="number"
                    value={invoice.discount.value}
                    onChange={(e) => onUpdateInvoice({
                      discount: { ...invoice.discount, value: Number(e.target.value) || 0 }
                    })}
                    className="discount-value-input"
                    placeholder="0"
                  />
                </div>
              </div>
              <span className="discount-amount">
                -{formatCurrency(calculateDiscount())}
              </span>
            </div>
          ) : (
            <div className="total-row-modern">
              <span>Discount (Per Item):</span>
              <span className="discount-amount">
                -{formatCurrency(calculateDiscount())}
              </span>
            </div>
          )}

          <div className="total-row-modern border-top">
            <span>Tax:</span>
            <span className="total-value">{formatCurrency(calculateTax())}</span>
          </div>
          <div className="total-row-modern total-final">
            <span>Total:</span>
            <span className="total-amount-final">{formatCurrency(calculateTotal())}</span>
          </div>
        </div>
      </div>
    </>
  );
});

export default InvoiceItemsTable;
