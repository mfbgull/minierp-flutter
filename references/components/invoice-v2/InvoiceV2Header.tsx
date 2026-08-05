import { memo } from 'react';
import { X } from 'lucide-react';
import type { InvoiceV2HeaderProps } from '../../types/invoiceV2';

const InvoiceV2Header = memo(function InvoiceV2Header({
  invoiceNo,
  source,
  onClose,
}: InvoiceV2HeaderProps) {
  return (
    <div className="iv2-header">
      <div className="iv2-header-left">
        <h2 className="iv2-header-title">INVOICE</h2>
        <span className="iv2-header-invoice-no">{invoiceNo}</span>

        {source && (
          <span className="iv2-source-badge">
            From {source.type === 'quotation' ? 'Quotation' : 'Sales Order'}{' '}
            {source.reference}
            <button type="button">Change</button>
          </span>
        )}
      </div>

      <button
        className="iv2-header-close"
        onClick={onClose}
        title="Close (Esc)"
        type="button"
      >
        <X size={18} />
      </button>
    </div>
  );
});

export default InvoiceV2Header;
