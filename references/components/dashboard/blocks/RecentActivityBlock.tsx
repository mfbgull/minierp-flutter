import { useQuery } from '@tanstack/react-query';
import { formatDistanceToNow } from 'date-fns';
import { Activity, User } from 'lucide-react';
import api from '../../../utils/api';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

interface ActivityEntry {
  id: number;
  action: string;
  entity_type: string;
  description: string;
  username: string;
  created_at: string;
}

export default function RecentActivityBlock({ blockId, apiEndpoint, config }: DashboardBlockComponentProps) {
  const limit = (config.limit as number) || 20;

  const { data, isLoading, error, refetch } = useQuery<ActivityEntry[]>({
    queryKey: ['dashboard-block', blockId, 'recent_activity'],
    queryFn: async () => {
      const res = await api.get(apiEndpoint || '/activity-logs/recent');
      return res.data.data as ActivityEntry[];
    },
    refetchInterval: ((config.refreshInterval as number) || 0) * 1000,
    staleTime: 30_000,
  });

  const activities = (data || []).slice(0, limit);

  if (isLoading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="dashboard-block-shimmer" style={{ height: 40, borderRadius: 6 }} />
        ))}
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="dashboard-block-error">
        <p>Failed to load activity</p>
        <button onClick={() => refetch()} className="dashboard-block-retry-btn">Retry</button>
      </div>
    );
  }

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <h4 style={{ margin: '0 0 8px 0', fontSize: '0.95rem', color: 'var(--neutral-700)', display: 'flex', alignItems: 'center', gap: 6 }}>
        <Activity size={16} />
        Recent Activity
      </h4>
      <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
        {activities.map((entry) => (
          <div
            key={entry.id}
            style={{
              display: 'flex', alignItems: 'flex-start', gap: 8, padding: '8px 10px',
              background: 'var(--neutral-50)', borderRadius: 6, fontSize: '0.85rem',
            }}
          >
            <User size={14} style={{ marginTop: 2, color: 'var(--neutral-400)', flexShrink: 0 }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 500, color: 'var(--neutral-800)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {entry.description || `${entry.action} ${entry.entity_type}`}
              </div>
              <div style={{ display: 'flex', gap: 8, fontSize: '0.75rem', color: 'var(--neutral-500)', marginTop: 2 }}>
                <span>{entry.username}</span>
                <span>{formatDistanceToNow(new Date(entry.created_at), { addSuffix: true })}</span>
              </div>
            </div>
          </div>
        ))}
        {activities.length === 0 && (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--neutral-500)', fontSize: '0.85rem' }}>
            No recent activity
          </div>
        )}
      </div>
    </div>
  );
}
