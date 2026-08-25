/**
 * PaymentsTab — AG-Grid for desktop supplier payment display with edit/delete actions.
 */

import { useMemo, memo } from 'react';

import { ColDef } from 'ag-grid-community';
import { MoreVertical, Edit2, Trash2, Printer } from 'lucide-react';

import DropdownMenu from '../../components/common/DropdownMenu';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import type { SupplierPaymentsTabProps, SupplierPayment } from '../../types';
import { createActionColDef } from '../../utils/agGridIntegration';
import { formatAsCurrency, formatDateString } from '../../utils/customerCalculations';

function PaymentsTab({ payments, loading, onEditPayment, onDeletePayment, onPrintReceipt, onPrintThermal }: SupplierPaymentsTabProps) {
  const columnDefs = useMemo<ColDef<SupplierPayment>[]>(
    () => [
      {
        headerName: 'Payment No',
        field: 'payment_no',
        filter: true,
        width: 120,
      },
      {
        headerName: 'Date',
        field: 'payment_date',
        filter: true,
        width: 110,
        valueFormatter: (params) => formatDateString(params.value),
      },
      {
        headerName: 'Amount',
        field: 'amount',
        filter: 'agNumberColumnFilter',
        width: 110,
        valueFormatter: (params) => formatAsCurrency(params.value),
      },
      {
        headerName: 'Method',
        field: 'payment_method',
        filter: true,
        width: 110,
      },
      {
        headerName: 'Reference',
        field: 'reference_no',
        filter: true,
        width: 120,
      },
      {
        headerName: 'Notes',
        field: 'notes',
        filter: true,
        flex: 1,
      },
      createActionColDef({
        colId: 'actions',
        cellRenderer: (params) => {
          if (!params.data) return null;
          const payment = params.data;
          return (
            <DropdownMenu
              trigger={
                <button className="action-menu-trigger" title="Actions">
                  <MoreVertical size={16} />
                </button>
              }
              items={[
                ...(onPrintReceipt ? [{
                  label: 'Print Receipt',
                  icon: <Printer size={16} />,
                  onClick: () => onPrintReceipt(payment),
                }] : []),
                ...(onPrintThermal ? [{
                  label: 'Print Thermal',
                  icon: <Printer size={16} />,
                  onClick: () => onPrintThermal(payment),
                }] : []),
                {
                  label: 'Edit',
                  icon: <Edit2 size={16} />,
                  onClick: () => onEditPayment(payment),
                },
                {
                  label: 'Delete',
                  icon: <Trash2 size={16} />,
                  onClick: () => onDeletePayment(payment),
                  destructive: true,
                },
              ]}
              align="end"
            />
          );
        },
      }),
    ],
    [onEditPayment, onDeletePayment, onPrintReceipt, onPrintThermal],
  );

  return (
    <div className="payments-tab">
      {loading ? (
        <div className="loading">
          <div className="spinner" />
        </div>
      ) : (
        <MiniERPGrid
          containerStyle={{ height: 400, width: '100%' }}
          rowData={payments}
          columnDefs={columnDefs}
          paginationPageSize={15}
          paginationPageSizeSelector={[10, 15, 25, 50]}
        />
      )}
    </div>
  );
}

export default memo(PaymentsTab);
