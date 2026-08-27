import React, { useState } from "react";
import { useTranslation } from "../../hooks/useTranslation";
import { ARAgingReport } from "../../components/reports/ARAgingReport";
import { ReceivablesSummary } from "../../components/reports/ReceivablesSummary";
import { TopDebtorsReport } from "../../components/reports/TopDebtorsReport";
import { DSOReport } from "../../components/reports/DSOReport";
import { useARReportsData } from "../../hooks/useARReportsData";
import { useSettings } from "../../context/SettingsContext";
import "./ARReportsPage.css";

type TabId = "aging" | "summary" | "debtors" | "dso";

const tabs: { id: TabId; labelKey: string }[] = [
  { id: "aging", labelKey: "reports.tabs.AR_Aging" },
  { id: "summary", labelKey: "reports.tabs.Receivables_Summary" },
  { id: "debtors", labelKey: "reports.tabs.Top_Debtors" },
  { id: "dso", labelKey: "reports.tabs.DSO" },
];

export default function ARReportsPage() {
  const { t } = useTranslation();
  const { formatCurrency } = useSettings();
  const [activeTab, setActiveTab] = useState<TabId>("aging");
  const [dateRange, setDateRange] = useState(() => {
    const now = new Date();
    return {
      from: new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split("T")[0],
      to: now.toISOString().split("T")[0],
    };
  });

  const { agingData, agingLoading, summaryData, summaryLoading, debtorsData, debtorsLoading, dsoData, dsoLoading } = useARReportsData({ dateRange });

  const handleDateChange = (field: "from" | "to", value: string) => {
    setDateRange((prev) => ({ ...prev, [field]: value }));
  };

  const renderActiveTab = () => {
    switch (activeTab) {
      case "aging":
        return (
          <ARAgingReport
            data={agingData}
            isLoading={agingLoading}
            formatCurrency={formatCurrency}
          />
        );
      case "summary":
        return (
          <ReceivablesSummary
            data={summaryData}
            isLoading={summaryLoading}
            formatCurrency={formatCurrency}
          />
        );
      case "debtors":
        return (
          <TopDebtorsReport
            data={debtorsData}
            isLoading={debtorsLoading}
            formatCurrency={formatCurrency}
          />
        );
      case "dso":
        return (
          <DSOReport
            data={dsoData}
            isLoading={dsoLoading}
            formatCurrency={formatCurrency}
          />
        );
      default:
        return null;
    }
  };

  return (
    <div className="report-page-modern">
      <div className="report-page-header">
        <div>
          <h1 className="report-page-title">{t("reports.AR_Reports")}</h1>
          <p className="report-page-subtitle">Track customer outstanding balances and payment aging</p>
        </div>
        <div className="date-range-picker">
          <label>
            <span>{t("common.from")}</span>
            <input
              type="date"
              value={dateRange.from}
              onChange={(e) => handleDateChange("from", e.target.value)}
              className="report-date-input"
            />
          </label>
          <label>
            <span>{t("common.to")}</span>
            <input
              type="date"
              value={dateRange.to}
              onChange={(e) => handleDateChange("to", e.target.value)}
              className="report-date-input"
            />
          </label>
        </div>
      </div>

      <div className="report-tabs">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            className={`report-tab ${activeTab === tab.id ? "report-tab--active" : ""}`}
            onClick={() => setActiveTab(tab.id)}
          >
            {t(tab.labelKey)}
          </button>
        ))}
      </div>

      <div className="report-content">{renderActiveTab()}</div>
    </div>
  );
}
