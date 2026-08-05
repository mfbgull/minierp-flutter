import { memo } from 'react';
import { Send, Plus } from 'lucide-react';
import type { InvoiceV2FooterProps } from '../../types/invoiceV2';

const InvoiceV2Footer = memo(function InvoiceV2Footer({
  isSaving,
  isEditMode,
  onCreateAndView,
  onCreateAndNew,
  onCancel,
}: InvoiceV2FooterProps) {
  return (
    <div className="iv2-footer">
      <button
        className="iv2-btn"
        onClick={onCancel}
        disabled={isSaving}
        type="button"
      >
        Cancel
      </button>

      <button
        className="iv2-btn primary"
        onClick={onCreateAndNew}
        disabled={isSaving}
        type="button"
      >
        {isSaving ? (
          <>
            <span className="spinner" />
            {isEditMode ? 'Updating...' : 'Creating...'}
          </>
        ) : (
          <>
            <Plus size={16} />
            {isEditMode ? 'Update & New' : 'Create & New'}
          </>
        )}
      </button>

      <button
        className="iv2-btn primary"
        onClick={onCreateAndView}
        disabled={isSaving}
        type="button"
      >
        {isSaving ? (
          <>
            <span className="spinner" />
            {isEditMode ? 'Updating...' : 'Saving...'}
          </>
        ) : (
          <>
            <Send size={16} />
            {isEditMode ? 'Update & View' : 'Create & View'}
          </>
        )}
      </button>
    </div>
  );
});

export default InvoiceV2Footer;
