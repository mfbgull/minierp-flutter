import '../../features/activity_log/activity_log_routes.dart';
import '../../features/admin/admin_routes.dart';
import '../../features/auth/auth_routes.dart';
import '../../features/customers/customers_routes.dart';
import '../../features/dashboard/dashboard_routes.dart';
import '../../features/employees/employees_routes.dart';
import '../../features/expenses/expenses_routes.dart';
import '../../features/forecasts/forecast_routes.dart';
import '../../features/integrations/integrations_routes.dart';
import '../../features/inventory/inventory_routes.dart';
import '../../features/owner_equity/owners_equity_routes.dart';
import '../../features/payments/payments_routes.dart';
import '../../features/production/production_routes.dart';
import '../../features/purchases/purchasing_routes.dart';
import '../../features/reports/reports_routes.dart';
import '../../features/sales/sales_routes.dart';
import '../../features/settings/settings_routes.dart';
import '../../features/suppliers/suppliers_routes.dart';
import 'module_routes.dart';

/// One entry per module (SHORTCOMINGS-FIX 1.1). Adding a module means
/// creating one `*_routes.dart` file + adding one line here — `app.dart`
/// builds the router and `app_shell.dart` builds the rail from this.
final List<ModuleRoutes> moduleRegistry = [
  const AuthRoutes(),
  const DashboardRoutes(),
  const InventoryRoutes(),
  const CustomersRoutes(),
  const SalesRoutes(),
  const PurchasingRoutes(),
  const SuppliersRoutes(),
  const ProductionRoutes(),
  const PaymentsRoutes(),
  const ExpensesRoutes(),
  const OwnersEquityRoutes(),
  const EmployeesRoutes(),
  const ReportsRoutes(),
  const ForecastRoutes(),
  const ActivityLogRoutes(),
  const AdminRoutes(),
  const IntegrationsRoutes(),
  const SettingsRoutes(),
];

/// Single source of truth for the shell's module list — the rail
/// (`app_shell.dart`) and the router (`app.dart`) both consume this, so
/// a module added to [moduleRegistry] appears in both automatically.
/// Order matches the sidebar order.
final List<ShellDestination> shellDestinations = [
  for (final module in moduleRegistry)
    if (module.destination != null) module.destination!,
];

/// Resolves the registry entry that owns [destination] (matched by path,
/// which is unique per module).
ModuleRoutes moduleFor(ShellDestination destination) => moduleRegistry.firstWhere(
  (m) => m.destination?.path == destination.path,
);