/**
 * CustomerModals — all modals for the Customer Detail Page.
 * Consolidates payment modal, delete invoice modal, delete payment modal,
 * and edit payment modal into a single component.
 */

import { memo } from 'react';

import EditPaymentForm from './EditPaymentForm';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import PaymentModal from '../../components/customers/PaymentModal';
import type { CustomerModalsProps } from '../../types';

function CustomerModals({
  id,
  customer,
  invoiceToDelete,
  paymentToDelete,
  paymentToEdit,
  isPaymentModalOpen,
  deleteInvoicePending,
  deletePaymentPending,
  onClosePaymentModal,
  onCloseInvoiceDelete,
  onClosePaymentDelete,
  onClosePaymentEdit,
  onPaymentSuccess,
  onConfirmDeleteInvoice,
  onConfirmDeletePayment,
}: CustomerModalsProps) {
  return (
    <>
      {/* Record Payment Modal */}
      <Modal
        isOpen={isPaymentModalOpen}
        onClose={onClosePaymentModal}
        title="Record Payment"
        size="large"
      >
        <PaymentModal
          customerId={id}
          customer={customer as { customer_name: string; customer_code: string }}
          onClose={onClosePaymentModal}
          onSuccess={onPaymentSuccess}
        />
      </Modal>

      {/* Delete Invoice Confirmation Modal */}
      <Modal
        isOpen={!!invoiceToDelete}
        onClose={onCloseInvoiceDelete}
        title="Delete Invoice"
        size="small"
      >
        <div className="delete-confirmation">
          <p>
            Are you sure you want to delete invoice{' '}
            <strong>{invoiceToDelete?.invoice_no}</strong>?
          </p>
          {(invoiceToDelete?.paid_amount || 0) > 0 && (
            <p className="delete-warning">
              Warning: This invoice has payments recorded against it. Deleting it will affect the
              customer's balance.
            </p>
          )}
          <div className="delete-actions">
            <Button variant="secondary" onClick={onCloseInvoiceDelete}>
              Cancel
            </Button>
            <Button variant="danger" onClick={onConfirmDeleteInvoice} loading={deleteInvoicePending}>
              Delete Invoice
            </Button>
          </div>
        </div>
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
            Warning: Deleting this payment will update the associated invoice balances and customer
            balance.
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
          <EditPaymentForm
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

export default memo(CustomerModals);
