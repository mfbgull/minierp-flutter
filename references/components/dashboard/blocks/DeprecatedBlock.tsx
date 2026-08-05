import { AlertTriangle, X } from 'lucide-react';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface DeprecatedBlockProps extends DashboardBlockComponentProps {
  /** The original block title (saved in the layout) */
  originalTitle?: string;
  /** Callback to remove this block (always available, even outside edit mode) */
  onRemove?: (blockId: string) => void;
}

export default function DeprecatedBlock({ originalTitle, blockId, isEditing, onRemove }: DeprecatedBlockProps) {
  return (
    <div style={{
      height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', gap: 8, padding: 16,
      background: 'var(--neutral-50)', borderRadius: 8,
      border: '2px dashed var(--neutral-300)',
      position: 'relative',
    }}>
      <AlertTriangle size={24} style={{ color: 'var(--warning)' }} />
      <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--neutral-700)', textAlign: 'center' }}>
        {originalTitle || 'Unavailable Block'}
      </div>
      <div style={{ fontSize: '0.8rem', color: 'var(--neutral-500)', textAlign: 'center', lineHeight: 1.4 }}>
        This block type is no longer available.
      </div>
      <button
        onClick={() => onRemove?.(blockId)}
        style={{
          display: 'flex', alignItems: 'center', gap: 4, padding: '6px 14px',
          background: 'var(--danger)', color: 'white', border: 'none', borderRadius: 6,
          cursor: 'pointer', fontSize: '0.8rem', fontWeight: 500,
          marginTop: 4,
        }}
      >
        <X size={14} />
        Remove
      </button>
    </div>
  );
}
