/**
 * InvoicesTab — AG-Grid for desktop invoice display with actions dropdown.
 * Uses strongly typed column definitions, memoized for performance.
 */

import { useMemo, memo } from 'react';

import MiniERPGrid from '../../components/common/MiniERPGrid';
import { MoreVertical, Eye, Trash2, Ban } from 'lucide-react';

import DropdownMenu from '../../components/common/DropdownMenu';
import { createActionColDef } from '../../utils/agGridIntegration';
import { formatAsCurrency, formatDateString } from '../../utils/customerCalculations';
import type { InvoicesTabProps, InvoiceColDef } from '../../types';
import { canShowDeleteAction, canCancelInvoice } from '../../utils/invoiceRules';
import { getStatusCellClass, getBalanceCellClass } from '../../utils/statusCellUtils';

function InvoicesTab({ invoices, loading, onViewInvoice, onDeleteInvoice, onCancelInvoice }: InvoicesTabProps) {
  const columnDefs = useMemo<InvoiceColDef[]>(
    () => [
      {
        headerName: 'Invoice No',
        field: 'invoice_no',
        filter: true,
        width: 120,
        cellRenderer: (params) => {
          if (!params.data) return null;
          return (
            <button className="invoice-link" onClick={() => onViewInvoice(params.data!.id)}>
              {params.value}
            </button>
          );
        },
      },
      {
        headerName: 'Date',
        field: 'invoice_date',
        filter: true,
        width: 110,
        valueFormatter: (params) => formatDateString(params.value),
      },
      {
        headerName: 'Due Date',
        field: 'due_date',
        filter: true,
        width: 110,
        valueFormatter: (params) => formatDateString(params.value),
      },
      {
        headerName: 'Total',
        field: 'total_amount',
        filter: 'agNumberColumnFilter',
        width: 110,
        valueFormatter: (params) => formatAsCurrency(params.value),
      },
      {
        headerName: 'Paid',
        field: 'paid_amount',
        filter: 'agNumberColumnFilter',
        width: 100,
        valueFormatter: (params) => formatAsCurrency(params.value),
      },
      {
        headerName: 'Balance',
        field: 'balance_amount',
        filter: 'agNumberColumnFilter',
        width: 100,
        valueFormatter: (params) => formatAsCurrency(params.value),
        cellClass: (params) => getBalanceCellClass(params.value),
      },
      {
        headerName: 'Status',
        field: 'status',
        filter: true,
        width: 110,
        cellRenderer: (params) => <span>{params.value || 'Unknown'}</span>,
        cellClass: (params) => getStatusCellClass(params.value),
      },
      createActionColDef({
        colId: 'actions',
        cellRenderer: (params) => {
          if (!params.data) return null;
          const invoice = params.data;
          return (
            <DropdownMenu
              trigger={
                <button className="action-menu-trigger" title="Actions">
                  <MoreVertical size={16} />
                </button>
              }
              items={[
                {
                  label: 'View',
                  icon: <Eye size={16} />,
                  onClick: () => onViewInvoice(invoice.id),
                },
                ...(canShowDeleteAction(invoice)
                  ? [
                      {
                        label: 'Delete',
                        icon: <Trash2 size={16} />,
                        onClick: () => onDeleteInvoice(invoice),
                        destructive: true,
                      } as const,
                    ]
                  : []),
                ...(canCancelInvoice(invoice)
                  ? [
                      {
                        label: 'Cancel',
                        icon: <Ban size={16} />,
                        onClick: () => onCancelInvoice(invoice),
                        destructive: true,
                      } as const,
                    ]
                  : []),
              ]}
              align="end"
            />
          );
        },
      }) as InvoiceColDef,
    ],
    [onViewInvoice, onDeleteInvoice, onCancelInvoice],
  );

  return (
    <div className="invoices-tab">
      {loading ? (
        <div className="loading">
          <div className="spinner" />
        </div>
      ) : (
        <MiniERPGrid
          containerStyle={{ height: 400, width: '100%' }}
          rowData={invoices}
          columnDefs={columnDefs as any}
          paginationPageSize={15}
          paginationPageSizeSelector={[10, 15, 25, 50]}
          onRowDoubleClicked={(params) => params.data && onViewInvoice(params.data.id)}
        />
      )}
    </div>
  );
}

export default memo(InvoicesTab);
