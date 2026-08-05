/**
 * POSTab — AG-Grid for desktop purchase order display with actions dropdown.
 */

import { useMemo, memo } from 'react';

import { ColDef } from 'ag-grid-community';
import { MoreVertical, Eye } from 'lucide-react';

import DropdownMenu from '../../components/common/DropdownMenu';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import type { POSTabProps, PurchaseOrderDetail } from '../../types';
import { createActionColDef } from '../../utils/agGridIntegration';
import { formatAsCurrency, formatDateString } from '../../utils/customerCalculations';

function POSTab({ purchaseOrders, loading, onViewPO }: POSTabProps) {
  const columnDefs = useMemo<ColDef<PurchaseOrderDetail>[]>(
    () => [
      {
        headerName: 'PO No',
        field: 'po_no',
        filter: true,
        width: 120,
        cellRenderer: (params: { value: string; data: { id: number } }) => (
          <button className="invoice-link" onClick={() => onViewPO(params.data.id)}>
            {params.value}
          </button>
        ),
      },
      {
        headerName: 'Date',
        field: 'po_date',
        filter: true,
        width: 110,
        valueFormatter: (params) => formatDateString(params.value),
      },
      {
        headerName: 'Status',
        field: 'status',
        filter: true,
        width: 120,
      },
      {
        headerName: 'Total',
        field: 'total_amount',
        filter: 'agNumberColumnFilter',
        width: 110,
        valueFormatter: (params) => formatAsCurrency(params.value),
      },
      {
        headerName: 'Expected Delivery',
        field: 'expected_delivery_date',
        filter: true,
        width: 130,
        valueFormatter: (params) => (params.value ? formatDateString(params.value) : ''),
      },
      createActionColDef({
        colId: 'actions',
        cellRenderer: (params) => {
          if (!params.data) return null;
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
                  onClick: () => onViewPO(params.data.id),
                },
              ]}
              align="end"
            />
          );
        },
      }),
    ],
    [onViewPO],
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
          rowData={purchaseOrders}
          columnDefs={columnDefs}
          paginationPageSize={15}
          paginationPageSizeSelector={[10, 15, 25, 50]}
          onRowDoubleClicked={(params) => params.data && onViewPO(params.data.id)}
        />
      )}
    </div>
  );
}

export default memo(POSTab);
