const STATUS_COLORS: Record<string, string> = {
  Draft: 'bg-gray-100 text-gray-700',
  Sent: 'bg-blue-100 text-blue-700',
  Unpaid: 'bg-gray-100 text-gray-700',
  'Partially Paid': 'bg-yellow-100 text-yellow-700',
  Paid: 'bg-green-100 text-green-700',
  Overdue: 'bg-red-100 text-red-700',
  Cancelled: 'bg-gray-100 text-gray-500',
  Confirmed: 'bg-blue-100 text-blue-700',
  Invoiced: 'bg-yellow-100 text-yellow-700',
  Completed: 'bg-green-100 text-green-700',
  Accepted: 'bg-green-100 text-green-700',
  Rejected: 'bg-red-100 text-red-700',
  Converted: 'bg-purple-100 text-purple-700',
  Expired: 'bg-orange-100 text-orange-700',
  Submitted: 'bg-blue-100 text-blue-700',
  'Partially Received': 'bg-yellow-100 text-yellow-700',
  'In Progress': 'bg-blue-100 text-blue-700',
};

export function getStatusColor(status: string): string {
  return STATUS_COLORS[status] || 'bg-gray-100 text-gray-700';
}
