/**
 * SupplierModals — all modals for the Supplier Detail Page.
 * Consolidates payment modal and delete payment confirmation into a single component.
 */

import { memo } from 'react';

import EditSupplierPaymentForm from './EditSupplierPaymentForm';
import SupplierPaymentModal from './SupplierPaymentModal';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import type { SupplierModalsProps } from '../../types';

function SupplierModals({
  id,
  supplier,
  paymentToDelete,
  paymentToEdit,
  isPaymentModalOpen,
  deletePaymentPending,
  onClosePaymentModal,
  onClosePaymentDelete,
  onClosePaymentEdit,
  onPaymentSuccess,
  onConfirmDeletePayment,
}: SupplierModalsProps) {
  return (
    <>
      {/* Record Payment Modal */}
      <Modal
        isOpen={isPaymentModalOpen}
        onClose={onClosePaymentModal}
        title="Record Supplier Payment"
        size="large"
      >
        <SupplierPaymentModal
          supplierId={id}
          supplier={supplier as { supplier_name: string; supplier_code: string }}
          onClose={onClosePaymentModal}
          onSuccess={onPaymentSuccess}
        />
      </Modal>

      {/* Delete Payment Confirmation Modal */}
      <Modal
        isOpen={!!paymentToDelete}
        onClose={onClosePaymentDelete}
        title="Delete Payment"
        size="small"
      >
        <div className="delete-confirmation">
          <p>
            Are you sure you want to delete payment{' '}
            <strong>{paymentToDelete?.payment_no}</strong>?
          </p>
          <p className="delete-warning">
            Warning: Deleting this payment will update the supplier balance and ledger.
          </p>
          <div className="delete-actions">
            <Button variant="secondary" onClick={onClosePaymentDelete}>
              Cancel
            </Button>
            <Button variant="danger" onClick={onConfirmDeletePayment} loading={deletePaymentPending}>
              Delete Payment
            </Button>
          </div>
        </div>
      </Modal>
      {/* Edit Payment Modal */}
      <Modal
        isOpen={!!paymentToEdit}
        onClose={onClosePaymentEdit}
        title="Edit Payment"
        size="medium"
      >
        {paymentToEdit && (
          <EditSupplierPaymentForm
            payment={paymentToEdit}
            onClose={onClosePaymentEdit}
            onSuccess={() => {
              onClosePaymentEdit();
              onPaymentSuccess();
            }}
          />
        )}
      </Modal>
    </>
  );
}

export default memo(SupplierModals);
