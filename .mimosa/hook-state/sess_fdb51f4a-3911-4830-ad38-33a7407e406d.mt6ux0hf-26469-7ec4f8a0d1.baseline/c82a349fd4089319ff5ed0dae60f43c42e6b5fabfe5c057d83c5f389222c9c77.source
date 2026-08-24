import { useState, useEffect, useCallback, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { nanoid } from 'nanoid';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  DndContext, DragOverlay, closestCenter,
  PointerSensor, KeyboardSensor, useSensor, useSensors,
  useDroppable
} from '@dnd-kit/core';
import {
  SortableContext, verticalListSortingStrategy,
  useSortable, arrayMove
} from '@dnd-kit/sortable';
import { useDraggable } from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';

import {
  Save, Play, ArrowLeft, Plus, Trash2, GripVertical, X, Settings2,
  Filter, SlidersHorizontal, FunctionSquare, Columns, Eye, EyeOff,
  BarChart3, LayoutList, Layers, Download, FileText, CopyPlus
} from 'lucide-react';

import {
  Chart as ChartJS,
  CategoryScale, LinearScale, BarElement,
  PointElement, LineElement, ArcElement,
  Title, Tooltip, Legend, Filler
} from 'chart.js';
import { Bar, Line, Pie, Doughnut } from 'react-chartjs-2';
import { jsPDF } from 'jspdf';
import { applyPlugin } from 'jspdf-autotable';
applyPlugin(jsPDF);

// Register Chart.js components once
ChartJS.register(
  CategoryScale, LinearScale, BarElement,
  PointElement, LineElement, ArcElement,
  Title, Tooltip, Legend, Filler
);

import Button from '../../components/common/Button';
import MiniERPGrid from '../../components/common/MiniERPGrid';
import customReportsApi from '../../utils/customReportsApi';
import { useTranslation } from '../../hooks/useTranslation';
import './ReportBuilder.css';

// ── Helper: default config ──────────────────────────────────
const DEFAULT_CONFIG = {
  entity: 'invoices',
  columns: [],
  filters: [],
  sort: [],
  computedColumns: [],
  groupBy: { enabled: false, fields: [], aggregates: [] },
  chart: { enabled: false, type: 'bar', labelField: '', valueField: '' },
};

// ── Aggregate functions ────────────────────────────────────
const AGGREGATE_FUNCTIONS = ['SUM', 'COUNT', 'AVG', 'MIN', 'MAX'];

// ── Operator labels ─────────────────────────────────────────
const OPERATOR_LABELS = {
  equals: '=',
  not_equals: '≠',
  greater_than: '>',
  less_than: '<',
  greater_or_equal: '≥',
  less_or_equal: '≤',
  contains: 'contains',
  starts_with: 'starts with',
  ends_with: 'ends with',
  in_list: 'in list',
  not_in: 'not in',
  between: 'between',
  is_null: 'is null',
  is_not_null: 'is not null',
};

// ═══════════════════════════════════════════════════════════════
//  COMPONENTS
// ═══════════════════════════════════════════════════════════════

// ── Draggable Field ─────────────────────────────────────────
function DraggableField({ field, entityKey }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `field-${entityKey}-${field.name}`,
    data: { field, entityKey },
  });

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      className="draggable-field"
      style={style}
      {...listeners}
      {...attributes}
    >
      <GripVertical size={14} className="drag-handle" />
      <span className="field-type-badge" data-type={field.type}>
        {field.type === 'number' ? '#' : field.type === 'date' ? '📅' : 'Aa'}
      </span>
      <span className="field-name">{field.label || field.name}</span>
    </div>
  );
}

// ── Droppable Column Drop Zone ────────────────────────────
function ColumnDropZone({ children }) {
  const { setNodeRef, isOver } = useDroppable({ id: 'column-dropzone' });

  return (
    <div
      ref={setNodeRef}
      className={`column-dropzone ${isOver ? 'drag-over' : ''}`}
    >
      {children}
    </div>
  );
}

// ── Sortable Column ─────────────────────────────────────────
function SortableColumn({ column, onRemove, onUpdate, onToggleVisibility, index }) {
  const {
    attributes, listeners, setNodeRef, transform, transition, isDragging,
  } = useSortable({ id: column._id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.3 : 1,
  };

  return (
    <div ref={setNodeRef} style={style} className={`sortable-column ${isDragging ? 'dragging' : ''} ${column.visible === false ? 'column-hidden' : ''}`}>
      <button className="column-grip" {...attributes} {...listeners}>
        <GripVertical size={14} />
      </button>
      <span className={`column-name ${column.visible === false ? 'text-muted' : ''}`}>
        {column.alias || column.field}
      </span>
      {column.aggregateFn && (
        <span className="column-agg-badge">{column.aggregateFn}</span>
      )}
      <div className="column-controls">
        <button
          className={`column-vis-btn ${column.visible === false ? 'hidden' : ''}`}
          onClick={() => onToggleVisibility(index)}
          title={column.visible === false ? 'Show column' : 'Hide column'}
        >
          {column.visible === false ? <EyeOff size={14} /> : <Eye size={14} />}
        </button>
        <input
          className="column-alias-input"
          type="text"
          value={column.alias || ''}
          placeholder="Alias"
          onChange={(e) => onUpdate(index, { ...column, alias: e.target.value })}
          onClick={(e) => e.stopPropagation()}
        />
        <button className="column-remove-btn" onClick={() => onRemove(index)}>
          <X size={14} />
        </button>
      </div>
    </div>
  );
}

// ── Drag Overlay (ghost) ────────────────────────────────────
function DragGhost({ active }) {
  if (!active) return null;
  const field = active.data.current?.field;
  if (!field) return null;
  return (
    <div className="drag-ghost">
      <span className="field-type-badge" data-type={field.type}>
        {field.type === 'number' ? '#' : field.type === 'date' ? '📅' : 'Aa'}
      </span>
      <span>{field.label || field.name}</span>
    </div>
  );
}

// ── Filter Row ──────────────────────────────────────────────
function FilterRow({ filter, onChange, onRemove, fields }) {
  return (
    <div className="filter-row">
      <select
        className="filter-field-select"
        value={filter.field || ''}
        onChange={(e) => onChange({ ...filter, field: e.target.value })}
      >
        <option value="">— Select field —</option>
        {fields.map((f) => (
          <option key={f.name} value={f.name}>{f.label || f.name}</option>
        ))}
      </select>

      <select
        className="filter-operator-select"
        value={filter.operator}
        onChange={(e) => onChange({ ...filter, operator: e.target.value })}
      >
        {Object.entries(OPERATOR_LABELS).map(([op, label]) => (
          <option key={op} value={op}>{label}</option>
        ))}
      </select>

      {!['is_null', 'is_not_null'].includes(filter.operator) && (
        <input
          className="filter-value-input"
          type="text"
          value={filter.value || ''}
          placeholder="Value"
          onChange={(e) => onChange({ ...filter, value: e.target.value })}
        />
      )}

      <button className="filter-remove-btn" onClick={onRemove}>
        <Trash2 size={14} />
      </button>
    </div>
  );
}

// ── Sort Row ────────────────────────────────────────────────
function SortRow({ sort, onChange, onRemove, fields }) {
  return (
    <div className="sort-row">
      <select
        className="sort-field-select"
        value={sort.field || ''}
        onChange={(e) => onChange({ ...sort, field: e.target.value })}
      >
        <option value="">— Select field —</option>
        {fields.map((f) => (
          <option key={f.name} value={f.name}>{f.label || f.name}</option>
        ))}
      </select>

      <select
        className="sort-direction-select"
        value={sort.direction}
        onChange={(e) => onChange({ ...sort, direction: e.target.value })}
      >
        <option value="asc">Asc</option>
        <option value="desc">Desc</option>
      </select>

      <button className="sort-remove-btn" onClick={onRemove}>
        <Trash2 size={14} />
      </button>
    </div>
  );
}

// ── Computed Column Row ─────────────────────────────────────
function ComputedColumnRow({ col, onChange, onRemove }) {
  return (
    <div className="computed-col-row">
      <input
        className="cc-name-input"
        type="text"
        value={col.name || ''}
        placeholder="Alias (e.g. total_value)"
        onChange={(e) => onChange({ ...col, name: e.target.value })}
      />
      <input
        className="cc-expr-input"
        type="text"
        value={col.expression || ''}
        placeholder="Expression (e.g. SUM(amount))"
        onChange={(e) => onChange({ ...col, expression: e.target.value })}
      />
      <select
        className="cc-type-select"
        value={col.type || 'number'}
        onChange={(e) => onChange({ ...col, type: e.target.value })}
      >
        <option value="number">Number</option>
        <option value="string">String</option>
        <option value="date">Date</option>
      </select>
      <button className="cc-remove-btn" onClick={onRemove}>
        <Trash2 size={14} />
      </button>
    </div>
  );
}

// ── PDF Export Helper ──────────────────────────────────────
function downloadPDF(rows, columns, title = 'Report') {
  if (!rows || rows.length === 0) return;

  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
  const pageWidth = doc.internal.pageSize.getWidth();

  // Header
  doc.setFontSize(16);
  doc.setFont(undefined, 'bold');
  doc.text(title, 14, 18);

  // Subtitle with timestamp
  doc.setFontSize(9);
  doc.setFont(undefined, 'normal');
  doc.setTextColor(120, 120, 120);
  doc.text(`Generated: ${new Date().toLocaleString()}  |  ${rows.length} rows`, 14, 25);

  // Table headers from columns array
  const headers = columns || Object.keys(rows[0]);
  const tableData = rows.map((row) => headers.map((h) => row[h] ?? ''));

  // Styled table using jspdf-autotable
  doc.autoTable({
    head: [headers],
    body: tableData,
    startY: 30,
    styles: {
      fontSize: 8,
      cellPadding: 2,
      lineColor: [200, 200, 200],
      lineWidth: 0.25,
    },
    headStyles: {
      fillColor: [37, 99, 235],
      textColor: [255, 255, 255],
      fontStyle: 'bold',
      fontSize: 8,
      halign: 'center',
    },
    alternateRowStyles: {
      fillColor: [245, 247, 250],
    },
    margin: { top: 30 },
    didDrawPage: (data) => {
      // Footer with page number
      doc.setFontSize(8);
      doc.setTextColor(160, 160, 160);
      doc.text(
        `Page ${doc.getCurrentPageInfo().pageNumber}`,
        pageWidth - 14,
        doc.internal.pageSize.getHeight() - 8,
        { align: 'right' }
      );
    },
  });

  doc.save(`${title.replace(/[^a-zA-Z0-9_-]/g, '_')}.pdf`);
}

// ── CSV Export Helper ──────────────────────────────────────
function downloadCSV(rows, columns, filename = 'report-export.csv') {
  if (!rows || rows.length === 0) return;

  const headers = columns || Object.keys(rows[0]);
  const csvContent = [
    headers.map((h) => `"${String(h).replace(/"/g, '""')}"`).join(','),
    ...rows.map((row) =>
      headers.map((h) => `"${String(row[h] ?? '').replace(/"/g, '""')}"`).join(',')
    ),
  ].join('\n');

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(link.href);
}

// ── Chart colour palette ────────────────────────────────────
const CHART_COLORS = [
  '#2563eb', '#f59e0b', '#10b981', '#ef4444', '#8b5cf6',
  '#ec4899', '#14b8a6', '#f97316', '#6366f1', '#84cc16',
  '#06b6d4', '#d946ef', '#22c55e', '#eab308', '#3b82f6',
];

// ═══════════════════════════════════════════════════════════════
//  CHART PREVIEW COMPONENT
// ═══════════════════════════════════════════════════════════════

function ChartPreview({ chartConfig, rows, columns = [] }) {
  const { t } = useTranslation();

  if (!rows || rows.length === 0 || !chartConfig.labelField || !chartConfig.valueField) {
    return (
      <div className="preview-empty">
        <BarChart3 size={40} />
        <p>{t('customReportsBuilder.chartEmpty')}</p>
      </div>
    );
  }

  // Resolve field name → alias so we look up the correct key in query results
  const resolveAlias = (field) => {
    if (!field) return field;
    const col = columns.find((c) => c.field === field);
    return col ? (col.alias || col.field) : field;
  };
  const labelKey = resolveAlias(chartConfig.labelField);
  const valueKey = resolveAlias(chartConfig.valueField);

  const labels = rows.map((r) => r[labelKey] ?? '');
  const values = rows.map((r) => Number(r[valueKey]) || 0);

  const data = {
    labels,
    datasets: [
      {
        label: chartConfig.valueField,
        data: values,
        backgroundColor: chartConfig.type === 'bar'
          ? values.map((_, i) => CHART_COLORS[i % CHART_COLORS.length])
          : CHART_COLORS.slice(0, Math.min(values.length, CHART_COLORS.length)),
        borderColor: '#1e293b',
        borderWidth: chartConfig.type === 'pie' || chartConfig.type === 'doughnut' ? 2 : 1,
        fill: chartConfig.type === 'line',
        tension: 0.3,
        pointRadius: 3,
      },
    ],
  };

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: chartConfig.type !== 'bar' && chartConfig.type !== 'line',
        position: 'bottom',
        labels: { boxWidth: 12, padding: 10, font: { size: 11 } },
      },
      tooltip: {
        callbacks: {
          label: (ctx) => `${ctx.dataset.label}: ${ctx.parsed.y ?? ctx.parsed}`,
        },
      },
    },
    scales: chartConfig.type === 'bar' || chartConfig.type === 'line'
      ? {
          x: {
            grid: { display: false },
            ticks: { font: { size: 10 }, maxRotation: 45 },
          },
          y: {
            beginAtZero: true,
            grid: { color: 'rgba(0,0,0,0.06)' },
            ticks: { font: { size: 10 } },
          },
        }
      : undefined,
  };

  const ChartComponent =
    chartConfig.type === 'line' ? Line :
    chartConfig.type === 'pie' ? Pie :
    chartConfig.type === 'doughnut' ? Doughnut :
    Bar;

  return (
    <div className="chart-canvas-wrapper">
      <ChartComponent data={data} options={options} />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
//  LEFT PANEL
// ═══════════════════════════════════════════════════════════════

function LeftPanel({ entities, config, handleEntityChange, selectedEntity, entityFields }) {
  const { t } = useTranslation();

  return (
    <div className="builder-left-panel">
      <div className="panel-section">
        <h3 className="panel-title">{t('customReportsBuilder.entity')}</h3>
        <select
          className="entity-select"
          value={config.entity}
          onChange={(e) => handleEntityChange(e.target.value)}
        >
          {entities.map((e) => (
            <option key={e.key} value={e.key}>{e.label}</option>
          ))}
        </select>
      </div>
      <div className="panel-section fields-panel">
        <h3 className="panel-title">{t('customReportsBuilder.fields')}</h3>
        <div className="fields-list">
          {entityFields.map((field) => (
            <DraggableField key={field.name} field={field} entityKey={selectedEntity.key} />
          ))}
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
//  RIGHT PANEL
// ═══════════════════════════════════════════════════════════════

function RightPanel({
  config, entityFields, isSidebarOpen, setSidebarOpen,
  addFilter, updateFilter, removeFilter,
  addSort, updateSort, removeSort,
  removeColumn, updateColumn, toggleColumnVisibility, toggleAllColumnsVisibility,
  addComputedColumn, updateComputedColumn, removeComputedColumn,
  handleRun, isRunning, runResult, previewColumnDefs,
  chartConfig, updateChartConfig, previewMode, setPreviewMode,
  groupBy, updateGroupBy, addAggregate, updateAggregate, removeAggregate,
  reportMeta,
}) {
  const { t } = useTranslation();

  return (
    <div className="builder-right-panel">
      {/* ── Sidebar Tabs ──────────────────── */}
      <div className="config-sidebar">
        <button
          className={`config-tab ${isSidebarOpen === 'columns' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('columns')}
        >
          <Columns size={16} /> {t('customReportsBuilder.columns')}
          <span className="tab-count">{config.columns?.length || 0}</span>
        </button>
        <button
          className={`config-tab ${isSidebarOpen === 'filters' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('filters')}
        >
          <Filter size={16} /> {t('customReportsBuilder.filters')}
          <span className="tab-count">{config.filters?.length || 0}</span>
        </button>
        <button
          className={`config-tab ${isSidebarOpen === 'sorts' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('sorts')}
        >
          <SlidersHorizontal size={16} /> {t('customReportsBuilder.sort')}
          <span className="tab-count">{config.sort?.length || 0}</span>
        </button>
        <button
          className={`config-tab ${isSidebarOpen === 'computed' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('computed')}
        >
          <FunctionSquare size={16} /> {t('customReportsBuilder.computed')}
          <span className="tab-count">{config.computedColumns?.length || 0}</span>
        </button>
        <button
          className={`config-tab ${isSidebarOpen === 'group' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('group')}
        >
          <Layers size={16} /> {t('customReportsBuilder.group')}
          <span className={`tab-count ${groupBy.enabled ? 'active' : ''}`}>
            {groupBy.enabled ? groupBy.fields.length || 'On' : 'Off'}
          </span>
        </button>
        <button
          className={`config-tab ${isSidebarOpen === 'chart' ? 'active' : ''}`}
          onClick={() => setSidebarOpen('chart')}
        >
          <BarChart3 size={16} /> {t('customReportsBuilder.chart')}
          <span className={`tab-count ${chartConfig.enabled ? 'active' : ''}`}>
            {chartConfig.enabled ? chartConfig.type : 'Off'}
          </span>
        </button>
      </div>

      {/* ── Config Panel ──────────────────────── */}
      <div className="config-panel">
        {/* Columns */}
        {isSidebarOpen === 'columns' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.columns')}</h4>
              {(config.columns || []).length > 0 && (
                <button className="visibility-toggle-btn" onClick={toggleAllColumnsVisibility}>
                  <Eye size={13} />
                  {config.columns.every((c) => c.visible === false)
                    ? t('customReportsBuilder.showAll')
                    : t('customReportsBuilder.hideAll')}
                </button>
              )}
            </div>
            <SortableContext
              items={(config.columns || []).map((c) => c._id)}
              strategy={verticalListSortingStrategy}
            >
              <ColumnDropZone>
                {(config.columns || []).length === 0 ? (
                  <div className="dropzone-placeholder">
                    {t('customReportsBuilder.dropFieldsHere')}
                  </div>
                ) : (
                  (config.columns || []).map((col, i) => (
                    <SortableColumn
                      key={col._id}
                      column={col}
                      index={i}
                      onRemove={removeColumn}
                      onUpdate={updateColumn}
                      onToggleVisibility={toggleColumnVisibility}
                    />
                  ))
                )}
              </ColumnDropZone>
            </SortableContext>
          </div>
        )}

        {/* Filters */}
        {isSidebarOpen === 'filters' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.filters')}</h4>
              <button className="add-btn" onClick={addFilter}>
                <Plus size={14} /> {t('customReportsBuilder.addFilter')}
              </button>
            </div>
            <div className="filters-list">
              {(config.filters || []).length === 0 ? (
                <div className="config-empty">{t('customReportsBuilder.noFilters')}</div>
              ) : (
                (config.filters || []).map((f, i) => (
                  <FilterRow
                    key={f._id}
                    filter={f}
                    onChange={(updated) => updateFilter(i, updated)}
                    onRemove={() => removeFilter(i)}
                    fields={entityFields}
                  />
                ))
              )}
            </div>
          </div>
        )}

        {/* Sorts */}
        {isSidebarOpen === 'sorts' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.sort')}</h4>
              <button className="add-btn" onClick={addSort}>
                <Plus size={14} /> {t('customReportsBuilder.addSort')}
              </button>
            </div>
            <div className="sorts-list">
              {(config.sort || []).length === 0 ? (
                <div className="config-empty">{t('customReportsBuilder.noSorts')}</div>
              ) : (
                (config.sort || []).map((s, i) => (
                  <SortRow
                    key={s._id}
                    sort={s}
                    onChange={(updated) => updateSort(i, updated)}
                    onRemove={() => removeSort(i)}
                    fields={entityFields}
                  />
                ))
              )}
            </div>
          </div>
        )}

        {/* Computed Columns */}
        {isSidebarOpen === 'computed' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.computed')}</h4>
              <button className="add-btn" onClick={addComputedColumn}>
                <Plus size={14} /> {t('customReportsBuilder.addComputed')}
              </button>
            </div>
            <div className="computed-list">
              {(config.computedColumns || []).length === 0 ? (
                <div className="config-empty">{t('customReportsBuilder.noComputed')}</div>
              ) : (
                (config.computedColumns || []).map((c, i) => (
                  <ComputedColumnRow
                    key={c._id}
                    col={c}
                    onChange={(updated) => updateComputedColumn(i, updated)}
                    onRemove={() => removeComputedColumn(i)}
                  />
                ))
              )}
            </div>
          </div>
        )}

        {/* Group By */}
        {isSidebarOpen === 'group' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.group')}</h4>
            </div>

            <div className="chart-config-form">
              <label className="chart-config-label">
                <input
                  type="checkbox"
                  checked={groupBy.enabled}
                  onChange={(e) => updateGroupBy({ ...groupBy, enabled: e.target.checked })}
                />
                {t('customReportsBuilder.enableGroupBy')}
              </label>

              {groupBy.enabled && (
                <>
                  <div className="chart-config-row">
                    <label>{t('customReportsBuilder.groupFields')}</label>
                    <div className="group-fields-list">
                      {entityFields.map((f) => {
                        const checked = groupBy.fields.includes(f.name);
                        return (
                          <label key={f.name} className="group-field-checkbox">
                            <input
                              type="checkbox"
                              checked={checked}
                              onChange={() => {
                                const next = checked
                                  ? groupBy.fields.filter((n) => n !== f.name)
                                  : [...groupBy.fields, f.name];
                                updateGroupBy({ ...groupBy, fields: next });
                              }}
                            />
                            <span className="field-type-badge" data-type={f.type}>
                              {f.type === 'number' ? '#' : f.type === 'date' ? '📅' : 'Aa'}
                            </span>
                            <span>{f.label || f.name}</span>
                          </label>
                        );
                      })}
                    </div>
                  </div>

                  {groupBy.fields.length === 0 && (
                    <p className="config-empty">{t('customReportsBuilder.noGroupFields')}</p>
                  )}

                  {/* ── Aggregates ──────────────────── */}
                  <div className="chart-config-row">
                    <label>{t('customReportsBuilder.aggregates')}</label>
                    <button className="add-btn" onClick={addAggregate}>
                      <Plus size={14} /> {t('customReportsBuilder.addAggregate')}
                    </button>
                  </div>
                  <div className="aggregate-list">
                    {(groupBy.aggregates || []).length === 0 ? (
                      <p className="config-empty">{t('customReportsBuilder.noAggregates')}</p>
                    ) : (
                      (groupBy.aggregates || []).map((agg, i) => (
                        <div key={agg._id} className="aggregate-row">
                          <select
                            className="agg-fn-select"
                            value={agg.function}
                            onChange={(e) => updateAggregate(i, { ...agg, function: e.target.value })}
                          >
                            {AGGREGATE_FUNCTIONS.map((fn) => (
                              <option key={fn} value={fn}>{fn}</option>
                            ))}
                          </select>
                          <select
                            className="agg-field-select"
                            value={agg.field}
                            onChange={(e) => updateAggregate(i, { ...agg, field: e.target.value })}
                          >
                            <option value="">— Field —</option>
                            {entityFields.map((f) => (
                              <option key={f.name} value={f.name}>{f.label || f.name}</option>
                            ))}
                          </select>
                          <input
                            className="agg-alias-input"
                            type="text"
                            value={agg.alias || ''}
                            placeholder="Alias"
                            onChange={(e) => updateAggregate(i, { ...agg, alias: e.target.value })}
                          />
                          <button className="agg-remove-btn" onClick={() => removeAggregate(i)}>
                            <Trash2 size={14} />
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                </>
              )}
            </div>
          </div>
        )}

        {/* Chart */}
        {isSidebarOpen === 'chart' && (
          <div className="config-section">
            <div className="config-section-header">
              <h4>{t('customReportsBuilder.chart')}</h4>
            </div>

            <div className="chart-config-form">
              <label className="chart-config-label">
                <input
                  type="checkbox"
                  checked={chartConfig.enabled}
                  onChange={(e) => updateChartConfig({ ...chartConfig, enabled: e.target.checked })}
                />
                {t('customReportsBuilder.enableChart')}
              </label>

              {chartConfig.enabled && (
                <>
                  <div className="chart-config-row">
                    <label>{t('customReportsBuilder.chartType')}</label>
                    <select
                      className="chart-config-select"
                      value={chartConfig.type}
                      onChange={(e) => updateChartConfig({ ...chartConfig, type: e.target.value })}
                    >
                      <option value="bar">{t('customReportsBuilder.chartBar')}</option>
                      <option value="line">{t('customReportsBuilder.chartLine')}</option>
                      <option value="pie">{t('customReportsBuilder.chartPie')}</option>
                      <option value="doughnut">{t('customReportsBuilder.chartDoughnut')}</option>
                    </select>
                  </div>

                  <div className="chart-config-row">
                    <label>{t('customReportsBuilder.labelField')}</label>
                    <select
                      className="chart-config-select"
                      value={chartConfig.labelField}
                      onChange={(e) => updateChartConfig({ ...chartConfig, labelField: e.target.value })}
                    >
                      <option value="">— Select —</option>
                      {entityFields.map((f) => (
                        <option key={f.name} value={f.name}>{f.label || f.name}</option>
                      ))}
                    </select>
                  </div>

                  <div className="chart-config-row">
                    <label>{t('customReportsBuilder.valueField')}</label>
                    <select
                      className="chart-config-select"
                      value={chartConfig.valueField}
                      onChange={(e) => updateChartConfig({ ...chartConfig, valueField: e.target.value })}
                    >
                      <option value="">— Select —</option>
                      {entityFields.filter((f) => f.type === 'number').map((f) => (
                        <option key={f.name} value={f.name}>{f.label || f.name}</option>
                      ))}
                    </select>
                  </div>
                </>
              )}
            </div>
          </div>
        )}

        {/* ── Run Button ──────────────────── */}
        <div className="run-section">
          <Button
            variant="primary"
            onClick={handleRun}
            loading={isRunning}
            disabled={!config.entity || (config.columns || []).length === 0}
          >
            <Play size={16} /> {t('customReportsBuilder.run')}
          </Button>
          {runResult && (
            <span className="run-info">
              {runResult.rows?.length || 0} rows ({runResult.elapsedMs}ms)
            </span>
          )}
        </div>
      </div>

      {/* ── Preview ──────────────────────── */}
      <div className="preview-panel">
        <div className="preview-header">
          <Eye size={16} />
          <span>{t('customReportsBuilder.preview')}</span>
          {runResult && chartConfig.enabled && (
            <div className="preview-mode-toggle">
              <button
                className={`preview-mode-btn ${previewMode === 'grid' ? 'active' : ''}`}
                onClick={() => setPreviewMode('grid')}
              >
                <LayoutList size={14} /> Grid
              </button>
              <button
                className={`preview-mode-btn ${previewMode === 'chart' ? 'active' : ''}`}
                onClick={() => setPreviewMode('chart')}
              >
                <BarChart3 size={14} /> Chart
              </button>
            </div>
          )}              {runResult && (
                <>
                  <button
                    className="export-csv-btn"
                    onClick={() => {
                      const visibleHeaders = (config.columns || [])
                        .filter((c) => c.visible !== false)
                        .map((c) => c.alias || c.field);
                      downloadCSV(
                        runResult.rows,
                        visibleHeaders.length ? visibleHeaders : runResult.columns,
                        `${reportMeta.name || 'report'}.csv`
                      );
                    }}
                    title={t('customReportsBuilder.exportCsv')}
                  >
                    <Download size={14} /> CSV
                  </button>
                  <button
                    className="export-pdf-btn"
                    onClick={() => {
                      const visibleHeaders = (config.columns || [])
                        .filter((c) => c.visible !== false)
                        .map((c) => c.alias || c.field);
                      downloadPDF(
                        runResult.rows,
                        visibleHeaders.length ? visibleHeaders : runResult.columns,
                        reportMeta.name || 'Report'
                      );
                    }}
                    title={t('customReportsBuilder.exportPdf')}
                  >
                    <FileText size={14} /> PDF
                  </button>
                  <span className="total-badge">{runResult.totalCount} total</span>
                </>
              )}
        </div>
        <div className="preview-grid">
          {runResult ? (
            previewMode === 'chart' && chartConfig.enabled ? (
              <ChartPreview chartConfig={chartConfig} rows={runResult.rows} columns={config.columns || []} />
            ) : (
              <MiniERPGrid
                wrapperClassName="grid-fill"
                rowData={runResult.rows || []}
                columnDefs={previewColumnDefs}
                paginationPageSize={15}
                paginationPageSizeSelector={[10, 15, 25, 50]}
                loading={isRunning}
              />
            )
          ) : (
            <div className="preview-empty">
              <Eye size={40} />
              <p>{t('customReportsBuilder.runToPreview')}</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
//  MAIN PAGE COMPONENT
// ═══════════════════════════════════════════════════════════════

export default function ReportBuilder() {
  const { id } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { t } = useTranslation();

  const isNew = id === 'new';

  // ── State ─────────────────────────────────────────────
  const [reportMeta, setReportMeta] = useState({ name: '', description: '' });
  const [config, setConfig] = useState(DEFAULT_CONFIG);
  const [selectedEntity, setSelectedEntity] = useState(null);
  const [activeDrag, setActiveDrag] = useState(null);
  const [isSidebarOpen, setSidebarOpen] = useState('columns'); // columns | filters | sorts | computed
  const [runResult, setRunResult] = useState(null);
  const [isRunning, setIsRunning] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [previewMode, setPreviewMode] = useState('grid'); // grid | chart

  // ── Queries ───────────────────────────────────────────
  const { data: report, isLoading: loadingReport } = useQuery({
    queryKey: ['custom-report', id],
    queryFn: () => customReportsApi.get(id),
    enabled: !isNew && !!id,
  });

  const { data: entities = [] } = useQuery({
    queryKey: ['custom-report-entities'],
    queryFn: customReportsApi.listEntities,
  });

  // Load report data when fetched
  useEffect(() => {
    if (report) {
      setReportMeta({ name: report.name, description: report.description || '' });
      const cfg = typeof report.config === 'string' ? JSON.parse(report.config) : report.config;
      setConfig({
        ...DEFAULT_CONFIG,
        ...cfg,
        columns: (cfg.columns || []).map((c) => ({ ...c, _id: nanoid() })),
      });
      setPreviewMode('grid');
      setIsDirty(false);
    }
  }, [report]);

  // Set entity definition when entity key changes
  useEffect(() => {
    if (config.entity) {
      const entity = entities.find((e) => e.key === config.entity);
      setSelectedEntity(entity || null);
    }
  }, [config.entity, entities]);

  // ── Sensors for @dnd-kit ──────────────────────────────
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor),
  );

  // ── Handlers: field drag & drop ───────────────────────
  const handleDragStart = useCallback((event) => {
    setActiveDrag(event.active);
  }, []);

  const handleDragEnd = useCallback((event) => {
    setActiveDrag(null);
    const { active, over } = event;
    if (!over) return;

    // Check if a field is being dragged from the palette (has `field` data)
    const isFieldFromPalette = active.data.current?.field;

    if (isFieldFromPalette) {
      // Only add if dropped on the column dropzone or onto an existing sortable column
      const isDropOnZone = over.id === 'column-dropzone' ||
        (config.columns || []).some((c) => c._id === over.id);
      if (!isDropOnZone) return;

      const fieldData = active.data.current.field;
      setConfig((prev) => ({
        ...prev,
        columns: [
          ...(prev.columns || []),
          { field: fieldData.name, alias: fieldData.label || fieldData.name, visible: true, _id: nanoid() },
        ],
      }));
      setIsDirty(true);
      return;
    }

    // Reorder within drop zone (both active and over are sortable column IDs)
    const oldIdx = (config.columns || []).findIndex((c) => c._id === active.id);
    const newIdx = (config.columns || []).findIndex((c) => c._id === over.id);
    if (oldIdx !== -1 && newIdx !== -1) {
      setConfig((prev) => ({
        ...prev,
        columns: arrayMove(prev.columns, oldIdx, newIdx),
      }));
      setIsDirty(true);
    }
  }, [config.columns]);

  // ── Handlers: column management ───────────────────────
  const removeColumn = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      columns: prev.columns.filter((_, i) => i !== index),
    }));
    setIsDirty(true);
  }, []);

  const updateColumn = useCallback((index, updated) => {
    setConfig((prev) => ({
      ...prev,
      columns: prev.columns.map((c, i) => (i === index ? updated : c)),
    }));
    setIsDirty(true);
  }, []);

  const toggleColumnVisibility = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      columns: prev.columns.map((c, i) =>
        i === index ? { ...c, visible: c.visible === false ? true : false } : c
      ),
    }));
    setIsDirty(true);
  }, []);

  const toggleAllColumnsVisibility = useCallback(() => {
    setConfig((prev) => {
      const allHidden = prev.columns.every((c) => c.visible === false);
      const newVisible = allHidden ? true : false;
      return {
        ...prev,
        columns: prev.columns.map((c) => ({ ...c, visible: newVisible })),
      };
    });
    setIsDirty(true);
  }, []);

  // ── Handlers: filters ─────────────────────────────────
  const addFilter = useCallback(() => {
    setConfig((prev) => ({
      ...prev,
      filters: [...(prev.filters || []), { field: '', operator: 'equals', value: '', _id: nanoid() }],
    }));
    setIsDirty(true);
  }, []);

  const updateFilter = useCallback((index, updated) => {
    setConfig((prev) => ({
      ...prev,
      filters: prev.filters.map((f, i) => (i === index ? updated : f)),
    }));
    setIsDirty(true);
  }, []);

  const removeFilter = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      filters: prev.filters.filter((_, i) => i !== index),
    }));
    setIsDirty(true);
  }, []);

  // ── Handlers: sorts ───────────────────────────────────
  const addSort = useCallback(() => {
    setConfig((prev) => ({
      ...prev,
      sort: [...(prev.sort || []), { field: '', direction: 'asc', _id: nanoid() }],
    }));
    setIsDirty(true);
  }, []);

  const updateSort = useCallback((index, updated) => {
    setConfig((prev) => ({
      ...prev,
      sort: prev.sort.map((s, i) => (i === index ? updated : s)),
    }));
    setIsDirty(true);
  }, []);

  const removeSort = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      sort: prev.sort.filter((_, i) => i !== index),
    }));
    setIsDirty(true);
  }, []);

  // ── Handlers: chart config ────────────────────────────
  const updateChartConfig = useCallback((chart) => {
    setConfig((prev) => ({ ...prev, chart }));
    setIsDirty(true);
  }, []);

  // ── Handlers: group by ────────────────────────────────
  const updateGroupBy = useCallback((groupBy) => {
    setConfig((prev) => ({ ...prev, groupBy }));
    setIsDirty(true);
  }, []);

  const addAggregate = useCallback(() => {
    setConfig((prev) => ({
      ...prev,
      groupBy: {
        ...prev.groupBy,
        aggregates: [...(prev.groupBy?.aggregates || []), { function: 'SUM', field: '', alias: '', _id: nanoid() }],
      },
    }));
    setIsDirty(true);
  }, []);

  const updateAggregate = useCallback((index, updated) => {
    setConfig((prev) => ({
      ...prev,
      groupBy: {
        ...prev.groupBy,
        aggregates: prev.groupBy.aggregates.map((a, i) => (i === index ? updated : a)),
      },
    }));
    setIsDirty(true);
  }, []);

  const removeAggregate = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      groupBy: {
        ...prev.groupBy,
        aggregates: prev.groupBy.aggregates.filter((_, i) => i !== index),
      },
    }));
    setIsDirty(true);
  }, []);

  // ── Handlers: computed columns ────────────────────────
  const addComputedColumn = useCallback(() => {
    setConfig((prev) => ({
      ...prev,
      computedColumns: [...(prev.computedColumns || []), { name: '', expression: '', type: 'number', _id: nanoid() }],
    }));
    setIsDirty(true);
  }, []);

  const updateComputedColumn = useCallback((index, updated) => {
    setConfig((prev) => ({
      ...prev,
      computedColumns: prev.computedColumns.map((c, i) => (i === index ? updated : c)),
    }));
    setIsDirty(true);
  }, []);

  const removeComputedColumn = useCallback((index) => {
    setConfig((prev) => ({
      ...prev,
      computedColumns: prev.computedColumns.filter((_, i) => i !== index),
    }));
    setIsDirty(true);
  }, []);

  // ── Entity change ─────────────────────────────────────
  const handleEntityChange = useCallback((entityKey) => {
    setConfig((prev) => ({
      ...DEFAULT_CONFIG,
      entity: entityKey,
    }));
    setRunResult(null);
    setIsDirty(true);
  }, []);

  // ── Build save payload (shared by save & run) ─────────
  const buildPayload = useCallback(() => {
    // Merge manually-defined computed columns with group-by aggregates
    const userColumns = (config.computedColumns || []).map(({ _id, ...rest }) => rest);
    const aggregateColumns = (config.groupBy?.aggregates || [])
      .filter((a) => a.field)
      .map((a) => ({
        name: a.alias || `${a.function}_${a.field}`,
        expression: `${a.function}(${a.field})`,
        type: 'number',
      }));

    return {
      name: reportMeta.name || 'Untitled Report',
      description: reportMeta.description,
      config: {
        entity: config.entity,
        columns: (config.columns || []).map(({ _id, ...rest }) => rest),
        filters: (config.filters || []).map(({ _id, ...rest }) => rest),
        sort: (config.sort || []).map(({ _id, ...rest }) => rest),
        computedColumns: [...userColumns, ...aggregateColumns],
        groupBy: config.groupBy,
        chart: config.chart,
      },
    };
  }, [reportMeta, config]);

  // ── Save ──────────────────────────────────────────────
  const saveMutation = useMutation({
    mutationFn: (payload) => {
      if (isNew) {
        return customReportsApi.create(payload);
      }
      return customReportsApi.update(id, payload);
    },
    onSuccess: (data) => {
      toast.success(t('customReportsBuilder.saved'));
      setIsDirty(false);
      if (isNew && data?.id) {
        navigate(`/reports/custom/${data.id}/edit`, { replace: true });
      } else {
        queryClient.invalidateQueries({ queryKey: ['custom-report', id] });
        queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
      }
    },
    onError: (err) => {
      toast.error(err.response?.data?.error || t('customReportsBuilder.saveError'));
    },
  });

  const handleSave = useCallback(() => {
    saveMutation.mutate(buildPayload());
  }, [buildPayload, saveMutation]);

  const handleSaveAsTemplate = useCallback(async () => {
    const name = window.prompt(t('customReportsBuilder.templateNamePrompt'), `${reportMeta.name || 'Untitled'} (Template)`);
    if (!name) return;

    try {
      await customReportsApi.createTemplate({
        name,
        description: `Template created from report: ${reportMeta.name || 'Untitled'}`,
        config: buildPayload().config,
      });
      toast.success(t('customReportsBuilder.templateSaved'));
      queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
    } catch (err) {
      toast.error(err.response?.data?.error || t('customReportsBuilder.templateSaveError'));
    }
  }, [reportMeta, buildPayload, t, queryClient]);

  // ── Run ───────────────────────────────────────────────
  const handleRun = useCallback(async () => {
    setIsRunning(true);
    setRunResult(null);

    try {
      // 1. Auto-save the report config first
      let reportId = id;
      const payload = buildPayload();

      if (isNew) {
        const saved = await customReportsApi.create(payload);
        reportId = saved.id;
        setIsDirty(false);
        navigate(`/reports/custom/${saved.id}/edit`, { replace: true });
        queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
      } else if (isDirty) {
        await customReportsApi.update(id, payload);
        setIsDirty(false);
        queryClient.invalidateQueries({ queryKey: ['custom-report', id] });
        queryClient.invalidateQueries({ queryKey: ['custom-reports'] });
      }

      // 2. Run the saved report
      const result = await customReportsApi.run({ reportId });
      setRunResult(result);
    } catch (err) {
      toast.error(err.response?.data?.error || err.message || t('customReportsBuilder.runError'));
    } finally {
      setIsRunning(false);
    }
  }, [config, reportMeta, t, isNew, id, navigate, queryClient, isDirty, buildPayload]);

  // ── Current entity fields ─────────────────────────────
  const entityFields = useMemo(() => {
    if (!selectedEntity) return [];
    return selectedEntity.fields || [];
  }, [selectedEntity]);

  // ── Build column defs for AG-Grid preview ─────────────
  const previewColumnDefs = useMemo(() => {
    if (!runResult) return [];
    // Only show columns that are visible in the config.
    // runResult.columns contains ALIASES (e.g. "Customer Name"), so match
    // against c.alias first, falling back to c.field.
    const visibleCols = (config.columns || [])
      .filter((c) => c.visible !== false)
      .map((c) => c.alias || c.field);
    if (visibleCols.length === 0) return [];
    return (runResult.columns || [])
      .filter((col) => visibleCols.includes(col))
      .map((col) => ({
        headerName: col,
        field: col,
        sortable: true,
        filter: true,
        width: 150,
      }));
  }, [runResult, config.columns]);

  // ── Render ────────────────────────────────────────────
  if (loadingReport && !isNew) {
    return <div className="loading"><div className="spinner" /></div>;
  }

  return (
    <div className="report-builder">
      {/* ── Header ──────────────────────────────────── */}
      <div className="builder-header">
        <div className="builder-header-left">
          <button className="back-btn" onClick={() => navigate('/reports/custom')}>
            <ArrowLeft size={18} />
          </button>
          <input
            className="builder-title-input"
            type="text"
            value={reportMeta.name}
            onChange={(e) => { setReportMeta((p) => ({ ...p, name: e.target.value })); setIsDirty(true); }}
            placeholder="Report Name"
          />
          {isDirty && <span className="unsaved-badge">Unsaved</span>}
        </div>
        <div className="builder-header-right">
          <Button variant="primary" onClick={handleSave} loading={saveMutation.isPending}>
            <Save size={16} /> {t('customReportsBuilder.save')}
          </Button>
          <button className="save-template-btn" onClick={handleSaveAsTemplate} title={t('customReportsBuilder.saveAsTemplate')}>
            <CopyPlus size={16} />
          </button>
        </div>
      </div>

      {/* ── Body ────────────────────────────────────── */}
      <div className="builder-body">
        {selectedEntity ? (
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
            <LeftPanel
              entities={entities}
              config={config}
              handleEntityChange={handleEntityChange}
              selectedEntity={selectedEntity}
              entityFields={entityFields}
            />
            <RightPanel
              config={config}
              entityFields={entityFields}
              isSidebarOpen={isSidebarOpen}
              setSidebarOpen={setSidebarOpen}
              addFilter={addFilter}
              updateFilter={updateFilter}
              removeFilter={removeFilter}
              removeColumn={removeColumn}
              updateColumn={updateColumn}
              toggleColumnVisibility={toggleColumnVisibility}
              toggleAllColumnsVisibility={toggleAllColumnsVisibility}
              addSort={addSort}
              updateSort={updateSort}
              removeSort={removeSort}
              addComputedColumn={addComputedColumn}
              updateComputedColumn={updateComputedColumn}
              removeComputedColumn={removeComputedColumn}
              handleRun={handleRun}
              isRunning={isRunning}
              runResult={runResult}
              previewColumnDefs={previewColumnDefs}
              chartConfig={config.chart}
              updateChartConfig={updateChartConfig}
              previewMode={previewMode}
              setPreviewMode={setPreviewMode}
              groupBy={config.groupBy}
              updateGroupBy={updateGroupBy}
              addAggregate={addAggregate}
              updateAggregate={updateAggregate}
              removeAggregate={removeAggregate}
              reportMeta={reportMeta}
            />
            <DragOverlay dropAnimation={null}>
              {activeDrag ? <DragGhost active={activeDrag} /> : null}
            </DragOverlay>
          </DndContext>
        ) : (
          <div className="builder-empty-state">
            <p>{t('customReportsBuilder.selectEntityFirst')}</p>
          </div>
        )}
      </div>
    </div>
  );
}
