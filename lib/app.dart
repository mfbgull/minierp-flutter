import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_notifier.dart';
import 'core/auth/session_events.dart';
import 'core/theme/app_theme.dart';
import 'features/activity_log/activity_log_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/inventory/inventory_shell.dart';
import 'features/purchases/purchasing_shell.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/forecasts/forecast_shell.dart';
import 'features/integrations/integrations_screen.dart';
import 'features/employees/employees_screen.dart';
import 'features/admin/admin_shell.dart';
import 'features/payments/payments_screen.dart';
import 'features/production/production_shell.dart';
import 'data/models/invoice.dart' show Invoice;
import 'features/reports/ar_aging_report_screen.dart';
import 'features/reports/ar_summary_report_screen.dart';
import 'features/reports/bom_usage_report_screen.dart';
import 'features/reports/cash_flow_report_screen.dart';
import 'features/reports/dso_report_screen.dart';
import 'features/reports/expenses_report_screen.dart';
import 'features/reports/inventory_movement_report_screen.dart';
import 'features/reports/low_stock_report_screen.dart';
import 'features/reports/production_summary_report_screen.dart';
import 'features/reports/profit_loss_report_screen.dart';
import 'features/reports/purchase_summary_report_screen.dart';
import 'features/reports/top_debtors_report_screen.dart';
import 'features/reports/customer_statements_report_screen.dart';
import 'features/reports/reports_dashboard_screen.dart'
    show ReportsDashboardScreen, reportTitles;
import 'features/reports/sales_by_customer_report_screen.dart';
import 'features/reports/sales_by_item_report_screen.dart';
import 'features/reports/sales_summary_report_screen.dart';
import 'features/reports/supplier_analysis_report_screen.dart';
import 'features/reports/stock_level_report_screen.dart';
import 'features/reports/stock_valuation_report_screen.dart';
import 'features/sales/sales_invoice_form_page.dart';
import 'features/sales_orders/sales_shell.dart';
import 'features/shell/app_shell.dart';
import 'features/suppliers/suppliers_screen.dart';
import 'features/shell/module_placeholder_screen.dart';
import 'l10n/app_localizations.dart';

/// Bumped whenever the auth *status* changes so the router's
/// `refreshListenable` re-evaluates its redirect. A plain counter, kept
/// separate from the router so `StateNotifier` (which doesn't implement
/// Flutter's `Listenable`) can drive it via `ref.listen` in the app widget.
final routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// App router — route inventory in PORTING.md §5. Screens are added here
/// as they are ported (one GoRoute per module).
///
/// Auth gating (PORTING.md §3): the router is created once and refreshes
/// its redirect when the auth status changes, so navigation state survives
/// login/logout. While the session is being restored (`AuthStatus.unknown`)
/// everything redirects to `/splash`; logged-out users land on `/login`;
/// authenticated users are kept out of `/login` and `/splash`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) => _authRedirect(ref, state.matchedLocation),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Auth-module completion (PORTING.md §3): standalone screen outside
      // the shell (no rail) — opened from the shell's app bar. Session
      // stays valid after a change; a wrong current password is a 401 that
      // the dio layer treats as a credential error, not an expired session.
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      // Invoice create/edit form (PORTING.md §7): standalone page outside
      // the shell (full-width form; back arrow returns to the sales
      // grid). Create when no `extra` is passed, edit when the screen
      // pushes the row's `Invoice` as `extra`.
      GoRoute(
        path: '/sales/form',
        builder: (context, state) =>
            SalesInvoiceFormPage(invoice: state.extra as Invoice?),
      ),
      // Authenticated shell (PORTING.md §5): one branch per module in
      // [shellDestinations] — each keeps its state while switching. Real
      // screens replace the placeholder as they are ported.
      //
      // Note: indexedStack builds all branches eagerly (go_router 17.x has
      // no `lazy` option). Branches are placeholders today, so that's free;
      // when real module screens land, gate their fetches on visibility
      // (or switch to a per-branch lazy route) to avoid 15 fetches at boot.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          for (final dest in shellDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: dest.path,
                  builder: (context, state) => switch (dest.path) {
                    '/' => const DashboardScreen(),
                    // First ported data screen (PORTING.md §5/§6): the
                    // items grid lives at the inventory branch root; the
                    // web app hosts it at /inventory/items.
                    '/inventory' => const InventoryShell(),
                    // Second ported data screen: server-paginated list
                    // (GET /customers + pagination block).
                    '/customers' => const CustomersScreen(),
                    '/suppliers' => const SuppliersScreen(),
                    '/purchasing' => const PurchasingShell(),
                    '/expenses' => const ExpensesScreen(),
                    '/payments' => const PaymentsScreen(),
                    '/production' => const ProductionShell(),
                    // Sales module shell: invoices grid (branch root) +
                    // sales-orders grid as tabs (web: /sales-orders).
                    '/sales' => const SalesShell(),
                    // Reports hub (PORTING.md §11) — one card per report
                    // in the hub; the :report sub-route below resolves
                    // each card to its screen (placeholder until ported).
                    '/reports' => const ReportsDashboardScreen(),
                    // Forecasts (PORTING.md §12): four-tab shell over the
                    // /forecasts endpoints (dashboard, demand, trends,
                    // accuracy).
                    '/forecasts' => const ForecastShell(),
                    // Activity log (PORTING.md §5): offset-paged read-only
                    // grid over GET /activity-logs with filters + stats.
                    '/activity-log' => const ActivityLogScreen(),
                    // Settings (PORTING.md §13): grouped key-value editor
                    // over GET/POST /settings (company, currency, tax,
                    // document numbering).
                    '/settings' => const SettingsScreen(),
                    // Integrations: per-service enable/configure cards
                    // over GET /integrations/settings + PUT
                    // /integrations/settings/:service.
                    '/integrations' => const IntegrationsScreen(),
                    // Employees (PORTING.md §5): server-paginated grid
                    // over GET /employees + CRUD, salary pay modal,
                    // detail dialog (documents + salary history).
                    '/hr' => const EmployeesScreen(),
                    // User management (PORTING.md §5): admin-only shell
                    // with Users and Roles tabs over /users + /roles.
                    '/admin' => const AdminShell(),
                    _ => ModulePlaceholderScreen(
                      title: dest.label(AppLocalizations.of(context)!),
                    ),
                  },
                  // Report screens live as sub-routes under the hub.
                  routes: dest.path == '/reports'
                      ? [
                          GoRoute(
                            path: ':report',
                            builder: (context, state) {
                              final slug = state.pathParameters['report'] ?? '';
                              return switch (slug) {
                                'ar-summary' => const ArSummaryReportScreen(),
                                'ar-aging' => const ArAgingReportScreen(),
                                'sales-summary' =>
                                  const SalesSummaryReportScreen(),
                                'low-stock' => const LowStockReportScreen(),
                                'stock-level' => const StockLevelReportScreen(),
                                'stock-valuation' =>
                                  const StockValuationReportScreen(),
                                'sales-by-customer' =>
                                  const SalesByCustomerReportScreen(),
                                'dso' => const DsoReportScreen(),
                                'expenses' => const ExpensesReportScreen(),
                                'cash-flow' => const CashFlowReportScreen(),
                                'profit-loss' => const ProfitLossReportScreen(),
                                'inventory-movement' =>
                                  const InventoryMovementReportScreen(),
                                'purchase-summary' =>
                                  const PurchaseSummaryReportScreen(),
                                'top-debtors' => const TopDebtorsReportScreen(),
                                'customer-statements' =>
                                  const CustomerStatementsReportScreen(),
                                'sales-by-item' =>
                                  const SalesByItemReportScreen(),
                                'supplier-analysis' =>
                                  const SupplierAnalysisReportScreen(),
                                'production-summary' =>
                                  const ProductionSummaryReportScreen(),
                                'bom-usage' => const BomUsageReportScreen(),
                                _ => ModulePlaceholderScreen(
                                  title:
                                      reportTitles[slug]?.call(
                                        AppLocalizations.of(context)!,
                                      ) ??
                                      slug,
                                ),
                              };
                            },
                          ),
                        ]
                      : const [],
                ),
              ],
            ),
        ],
      ),
    ],
  );
});

/// Resolves where an un-authed/auth'd user may go. Called on every auth
/// status change (via [routerRefreshProvider]) and on every navigation.
String? _authRedirect(Ref ref, String location) {
  final auth = ref.read(authProvider);
  switch (auth.status) {
    case AuthStatus.unknown:
      return location == '/splash' ? null : '/splash';
    case AuthStatus.unauthenticated:
      return location == '/login' ? null : '/login';
    case AuthStatus.authenticated:
      if (location == '/login' || location == '/splash') return '/';
      // Non-admins can type an admin-only URL directly — send them home
      // instead of showing a branch the rail doesn't list (the shell's
      // indexOf fallback would otherwise highlight the wrong rail item).
      final isAdmin = auth.user?.isAdmin ?? false;
      final onAdminPath = shellDestinations
          .where((d) => d.adminOnly)
          .any((d) => location == d.path);
      if (onAdminPath && !isAdmin) return '/';
      return null;
  }
}

class MiniErpApp extends ConsumerWidget {
  const MiniErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-evaluate the router redirect when the auth status changes.
    ref.listen(authProvider, (previous, next) {
      if (previous?.status != next.status) {
        ref.read(routerRefreshProvider).value++;
      }
    });

    // PORTING.md §2: a 401 anywhere (expired token mid-session) clears the
    // session and the router redirects to /login.
    ref.listen(unauthorizedEventsProvider, (previous, next) {
      if (next.hasValue) {
        ref.read(authProvider.notifier).sessionExpired();
      }
    });

    return MaterialApp.router(
      title: 'MiniERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ur')],
    );
  }
}
