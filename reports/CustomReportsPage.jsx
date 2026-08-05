import { useState } from 'react';
import toast from 'react-hot-toast';
import { useNavigate } from 'react-router-dom';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, FileText, Play, Copy, Trash2, Edit2, MoreVertical, LayoutTemplate } from 'lucide-react';

import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import DropdownMenu from '../../components/common/DropdownMenu';
import StatCard, { StatsGrid } from '../../components/common/StatCard';

import { useTranslation } from '../../hooks/useTranslation';
import { createActionColDef } from '../../utils/agGridIntegration';
import customReportsApi from '../../utils/customReportsApi';
import { format } from 'date-fns';
import './CustomReportsPage.css';

export default function CustomReportsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { t } = useTranslation();

  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [newReportName, setNewReportName] = useState('');
  const [newReportDesc, setNewReportDesc] = useState('');
  const [selectedTemplate, setSelectedTemplate] = useState(null);
  const [isTemplateModalOpen, setIsTemplateModalOpen] = useState(false);

  // ── Queries ─────────────────────────────────────────
  const { data: reports = [], isLoading } = useQuery({
    queryKey: ['custom-reports'],
    queryFn: customReportsApi.list,
  });

  const { data: templates = [] } = useQuery({
    queryKey: ['custom-report-templates'],
    queryFn: customReportsApi.listTemplates,
  });

  // ── Mutations ───────────────────────────────────────
  const deleteMutation = useMutation({
    mutationFn: (id) => customReportsApi.delete(id),
    onSuccess: () => {
      toast.success(t('customReports.deleted'));
      queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
    },
    onError: (err) => {
      toast.error(err.response?.data?.error || t('customReports.deleteError'));
    },
  });

  const duplicateMutation = useMutation({
    mutationFn: (id) => customReportsApi.duplicate(id),
    onSuccess: (data) => {
      toast.success(t('customReports.duplicated'));
      queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
    },
    onError: (err) => {
      toast.error(err.response?.data?.error || t('customReports.duplicateError'));
    },
  });

  const quickCreateMutation = useMutation({
    mutationFn: (data) => customReportsApi.create(data),
    onSuccess: (data) => {
      toast.success(t('customReports.created'));
      queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
      setIsCreateModalOpen(false);
      setNewReportName('');
      setNewReportDesc('');
      navigate(`/reports/custom/${data.id}/edit`);
    },
    onError: (err) => {
      toast.error(err.response?.data?.error || t('customReports.createError'));
    },
  });

  const runMutation = useMutation({
    mutationFn: (id) => customReportsApi.run({ reportId: id }),
    onSuccess: (data) => {
      toast.success(`${t('customReports.ran')} (${data.totalCount} ${t('customReports.rows')})`);
    },
    onError: (err) => {
      toast.error(err.response?.data?.error || t('customReports.runError'));
    },
  });

  // ── Handlers ────────────────────────────────────────
  const handleDelete = (report) => {
    if (window.confirm(`${t('customReports.confirmDeleteMsg')} "${report.name}"?`)) {
      deleteMutation.mutate(report.id);
    }
  };

  const handleDuplicate = (report) => {
    duplicateMutation.mutate(report.id);
  };

  const handleRun = (report) => {
    runMutation.mutate(report.id);
  };

  const handleUseTemplate = (template) => {
    setSelectedTemplate(template);
    setNewReportName(template.name + ' (Customized)');
    setNewReportDesc(template.description || '');
    setIsTemplateModalOpen(false);
    setIsCreateModalOpen(true);
  };

  const handleQuickCreate = () => {
    if (!newReportName.trim()) {
      toast.error(t('customReports.nameRequired'));
      return;
    }
    const config = selectedTemplate
      ? selectedTemplate.config
      : {
          entity: 'invoices',
          columns: [
            { field: 'invoice_no', alias: 'Invoice' },
            { field: 'customer_name', alias: 'Customer' },
            { field: 'total_amount', alias: 'Total' },
          ],
          sort: [{ field: 'invoice_date', direction: 'desc' }],
        };

    quickCreateMutation.mutate({
      name: newReportName.trim(),
      description: newReportDesc.trim() || undefined,
      config,
    });
  };

  const handleCreateFromScratch = () => {
    setSelectedTemplate(null);
    setNewReportName('');
    setNewReportDesc('');
    setIsTemplateModalOpen(false);
    setIsCreateModalOpen(true);
  };

  // ── Stats ───────────────────────────────────────────
  const stats = {
    total: reports.length,
    templates: templates.length,
  };

  // ── Column Definitions ──────────────────────────────
  const columnDefs = [
    {
      headerName: t('customReports.name'),
      field: 'name',
      sortable: true,
      filter: true,
      width: 200,
      cellRenderer: (params) => (
        <span
          className="link-text"
          onClick={() => navigate(`/reports/custom/${params.data.id}/edit`)}
        >
          {params.value}
        </span>
      ),
    },
    {
      headerName: t('customReports.description'),
      field: 'description',
      sortable: false,
      filter: false,
      width: 250,
      cellRenderer: (params) => (
        <span className="text-muted">{params.value || '—'}</span>
      ),
    },
    {
      headerName: t('customReports.lastRun'),
      field: 'last_run_at',
      sortable: true,
      width: 130,
      valueFormatter: (params) =>
        params.value ? format(new Date(params.value), 'dd MMM yyyy HH:mm') : '—',
    },
    {
      headerName: t('customReports.created'),
      field: 'created_at',
      sortable: true,
      width: 130,
      valueFormatter: (params) =>
        params.value ? format(new Date(params.value), 'dd MMM yyyy') : '',
    },
    {
      headerName: t('customReports.updated'),
      field: 'updated_at',
      sortable: true,
      width: 130,
      valueFormatter: (params) =>
        params.value ? format(new Date(params.value), 'dd MMM yyyy') : '',
    },
    createActionColDef({
      headerName: '',
      width: 60,
      cellRenderer: (params) => (
        <DropdownMenu
          trigger={
            <button className="action-menu-trigger" title={t('customReports.actions')}>
              <MoreVertical size={16} />
            </button>
          }
          items={[
            {
              label: t('customReports.run'),
              icon: <Play size={16} />,
              onClick: () => handleRun(params.data),
            },
            {
              label: t('customReports.edit'),
              icon: <Edit2 size={16} />,
              onClick: () => navigate(`/reports/custom/${params.data.id}/edit`),
            },
            {
              label: t('customReports.duplicate'),
              icon: <Copy size={16} />,
              onClick: () => handleDuplicate(params.data),
            },
            {
              label: t('customReports.delete'),
              icon: <Trash2 size={16} />,
              onClick: () => handleDelete(params.data),
              destructive: true,
            },
          ]}
          align="end"
        />
      ),
    }),
  ];

  return (
    <div className="custom-reports-page">
      <div className="page-header">
        <div className="header-title">
          <FileText size={24} />
          <h1>{t('customReports.title')}</h1>
        </div>
        <div className="header-actions">
          <Button variant="secondary" onClick={() => setIsTemplateModalOpen(true)}>
            <LayoutTemplate size={18} />
            {t('customReports.fromTemplate')}
          </Button>
          <Button variant="primary" onClick={handleCreateFromScratch}>
            <Plus size={18} />
            {t('customReports.newReport')}
          </Button>
        </div>
      </div>

      <StatsGrid className="compact">
        <StatCard icon={FileText} label={t('customReports.totalReports')} value={stats.total} />
        <StatCard icon={LayoutTemplate} label={t('customReports.templates')} value={stats.templates} />
      </StatsGrid>

      <div className="custom-reports-content">
        {reports.length === 0 && !isLoading ? (
          <div className="empty-state">
            <FileText size={48} className="empty-state-icon" />
            <h3>{t('customReports.noReports')}</h3>
            <p>{t('customReports.noReportsDesc')}</p>
          </div>
        ) : (
          <MiniERPGrid
            wrapperClassName="grid-fill"
            rowData={reports}
            columnDefs={columnDefs}
            paginationPageSize={15}
            paginationPageSizeSelector={[10, 15, 25, 50]}
            loading={isLoading}
            onRowDoubleClicked={(params) => navigate(`/reports/custom/${params.data.id}/edit`)}
          />
        )}
      </div>

      {/* ── Create/Edit Modal ─────────────────────────── */}
      <Modal
        isOpen={isCreateModalOpen}
        onClose={() => {
          setIsCreateModalOpen(false);
          setSelectedTemplate(null);
        }}
        title={selectedTemplate ? t('customReports.createFromTemplate') : t('customReports.newReport')}
        size="medium"
      >
        <div className="custom-report-form">
          {selectedTemplate && (
            <div className="template-badge">
              <LayoutTemplate size={14} />
              <span>{t('customReports.basedOn')}: <strong>{selectedTemplate.name}</strong></span>
            </div>
          )}
          <div className="form-group">
            <label>{t('customReports.name')}</label>
            <input
              type="text"
              className="form-input"
              value={newReportName}
              onChange={(e) => setNewReportName(e.target.value)}
              placeholder={t('customReports.namePlaceholder')}
              autoFocus
            />
          </div>
          <div className="form-group">
            <label>{t('customReports.description')}</label>
            <textarea
              className="form-input form-textarea"
              value={newReportDesc}
              onChange={(e) => setNewReportDesc(e.target.value)}
              placeholder={t('customReports.descPlaceholder')}
              rows={3}
            />
          </div>
          <div className="form-actions">
            <Button variant="ghost" onClick={() => setIsCreateModalOpen(false)}>
              {t('actions.cancel')}
            </Button>
            <Button
              variant="primary"
              onClick={handleQuickCreate}
              loading={quickCreateMutation.isPending}
            >
              {t('customReports.createAndEdit')}
            </Button>
          </div>
        </div>
      </Modal>

      {/* ── Template Picker Modal ────────────────────── */}
      <Modal
        isOpen={isTemplateModalOpen}
        onClose={() => setIsTemplateModalOpen(false)}
        title={t('customReports.chooseTemplate')}
        size="large"
      >
        <div className="template-grid">
          {templates.map((template) => (
            <button
              type="button"
              key={template.id}
              className="template-card"
              onClick={() => handleUseTemplate(template)}
            >
              <div className="template-card-icon">
                <LayoutTemplate size={24} />
              </div>
              <div className="template-card-name">{template.name}</div>
              <div className="template-card-desc">{template.description}</div>
              <div className="template-card-entity">
                {template.config?.entity}
              </div>
            </button>
          ))}
        </div>
      </Modal>


    </div>
  );
}
