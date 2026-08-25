import { Link } from 'react-router-dom';
import { Package, DollarSign, ShoppingCart, Factory, BarChart3, ClipboardList, Waves } from 'lucide-react';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

const actions = [
  { to: '/inventory/items', icon: Package, label: 'New Item', color: 'var(--primary)' },
  { to: '/sales', icon: DollarSign, label: 'Record Sale', color: 'var(--primary)' },
  { to: '/purchases', icon: ShoppingCart, label: 'New Purchase', color: 'var(--primary)' },
  { to: '/production', icon: Factory, label: 'Production', color: 'var(--primary)' },
  { to: '/inventory/stock-movements', icon: BarChart3, label: 'Stock Movement', color: 'var(--primary)' },
  { to: '/bom', icon: ClipboardList, label: 'BOM', color: 'var(--primary)' },
];

export default function QuickActionsBlock(_props: DashboardBlockComponentProps) {
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)' }}>Quick Actions</h4>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 6, flex: 1 }}>
        {actions.map((action) => (
          <Link
            key={action.to}
            to={action.to}
            style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
              gap: 4, padding: '10px 6px', background: 'var(--neutral-50)', borderRadius: 8,
              textDecoration: 'none', color: 'var(--neutral-800)', fontWeight: 500,
              fontSize: '0.8rem', transition: 'all 0.2s', border: '2px solid transparent',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = 'var(--primary)';
              e.currentTarget.style.color = 'white';
              e.currentTarget.style.borderColor = 'var(--primary)';
              e.currentTarget.style.transform = 'translateY(-2px)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = 'var(--neutral-50)';
              e.currentTarget.style.color = 'var(--neutral-800)';
              e.currentTarget.style.borderColor = 'transparent';
              e.currentTarget.style.transform = 'none';
            }}
          >
            <action.icon size={22} strokeWidth={1.5} />
            <span>{action.label}</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
