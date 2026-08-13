import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
  ];

  /// No description provided for @activitylogCleanup.
  ///
  /// In en, this message translates to:
  /// **'Cleanup'**
  String get activitylogCleanup;

  /// No description provided for @activitylogCleanupdays.
  ///
  /// In en, this message translates to:
  /// **'Retention (days)'**
  String get activitylogCleanupdays;

  /// No description provided for @activitylogCleanupdesc.
  ///
  /// In en, this message translates to:
  /// **'Permanently deletes log entries older than the retention period. This cannot be undone.'**
  String get activitylogCleanupdesc;

  /// No description provided for @activitylogCleanupinvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number of days'**
  String get activitylogCleanupinvalid;

  /// No description provided for @activitylogCleanupsuccess.
  ///
  /// In en, this message translates to:
  /// **'Cleaned up {count} log entries'**
  String activitylogCleanupsuccess(Object count);

  /// No description provided for @activitylogCleanuptitle.
  ///
  /// In en, this message translates to:
  /// **'Clean up old logs'**
  String get activitylogCleanuptitle;

  /// No description provided for @activitylogAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get activitylogAction;

  /// No description provided for @activitylogAllactions.
  ///
  /// In en, this message translates to:
  /// **'All actions'**
  String get activitylogAllactions;

  /// No description provided for @activitylogAllentities.
  ///
  /// In en, this message translates to:
  /// **'All entity types'**
  String get activitylogAllentities;

  /// No description provided for @activitylogAllusers.
  ///
  /// In en, this message translates to:
  /// **'All users'**
  String get activitylogAllusers;

  /// No description provided for @activitylogCount.
  ///
  /// In en, this message translates to:
  /// **'logs'**
  String get activitylogCount;

  /// No description provided for @activitylogDetailtitle.
  ///
  /// In en, this message translates to:
  /// **'Activity Detail'**
  String get activitylogDetailtitle;

  /// No description provided for @activitylogDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get activitylogDuration;

  /// No description provided for @activitylogEntity.
  ///
  /// In en, this message translates to:
  /// **'Entity'**
  String get activitylogEntity;

  /// No description provided for @activitylogExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get activitylogExportcsv;

  /// No description provided for @activitylogExported.
  ///
  /// In en, this message translates to:
  /// **'Activity log exported'**
  String get activitylogExported;

  /// No description provided for @activitylogExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get activitylogExportfailed;

  /// No description provided for @activitylogIp.
  ///
  /// In en, this message translates to:
  /// **'IP Address'**
  String get activitylogIp;

  /// No description provided for @activitylogLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get activitylogLevel;

  /// No description provided for @activitylogMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get activitylogMetadata;

  /// No description provided for @activitylogTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get activitylogTimestamp;

  /// No description provided for @activitylogToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get activitylogToday;

  /// No description provided for @activitylogTotal.
  ///
  /// In en, this message translates to:
  /// **'Total logs'**
  String get activitylogTotal;

  /// No description provided for @activitylogUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get activitylogUser;

  /// No description provided for @activitylogUseragent.
  ///
  /// In en, this message translates to:
  /// **'User Agent'**
  String get activitylogUseragent;

  /// No description provided for @dashboardWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get dashboardWelcome;

  /// No description provided for @dashboardArsummary.
  ///
  /// In en, this message translates to:
  /// **'AR Summary'**
  String get dashboardArsummary;

  /// No description provided for @dashboardTotalitems.
  ///
  /// In en, this message translates to:
  /// **'Total Items'**
  String get dashboardTotalitems;

  /// No description provided for @dashboardWarehousestocks.
  ///
  /// In en, this message translates to:
  /// **'warehouse stocks'**
  String get dashboardWarehousestocks;

  /// No description provided for @dashboardRecentproductions.
  ///
  /// In en, this message translates to:
  /// **'Recent Productions'**
  String get dashboardRecentproductions;

  /// No description provided for @dashboardStockvalue.
  ///
  /// In en, this message translates to:
  /// **'Stock Value'**
  String get dashboardStockvalue;

  /// No description provided for @dashboardCurrentinventoryworth.
  ///
  /// In en, this message translates to:
  /// **'Current inventory worth'**
  String get dashboardCurrentinventoryworth;

  /// No description provided for @dashboardCustomers.
  ///
  /// In en, this message translates to:
  /// **'customers'**
  String get dashboardCustomers;

  /// No description provided for @dashboardInvoices.
  ///
  /// In en, this message translates to:
  /// **'invoices'**
  String get dashboardInvoices;

  /// No description provided for @dashboardSalesrevenue.
  ///
  /// In en, this message translates to:
  /// **'Sales Revenue'**
  String get dashboardSalesrevenue;

  /// No description provided for @dashboardProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get dashboardProfit;

  /// No description provided for @dashboardGlobalDateRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Date range applies to all report screens'**
  String get dashboardGlobalDateRangeHint;

  /// No description provided for @dashboardTopcustomers.
  ///
  /// In en, this message translates to:
  /// **'Top Customers'**
  String get dashboardTopcustomers;

  /// No description provided for @dashboardTotalsales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get dashboardTotalsales;

  /// No description provided for @dashboardRunslast30days.
  ///
  /// In en, this message translates to:
  /// **'Runs in last 30 days'**
  String get dashboardRunslast30days;

  /// No description provided for @dashboardSalesvspurchases.
  ///
  /// In en, this message translates to:
  /// **'Sales vs Purchases (Last 7 Days)'**
  String get dashboardSalesvspurchases;

  /// No description provided for @dashboardStockbycategory.
  ///
  /// In en, this message translates to:
  /// **'Stock by Category'**
  String get dashboardStockbycategory;

  /// No description provided for @dashboardLowstockalerts.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get dashboardLowstockalerts;

  /// No description provided for @dashboardWellstocked.
  ///
  /// In en, this message translates to:
  /// **'All items are well stocked!'**
  String get dashboardWellstocked;

  /// No description provided for @dashboardQuickactions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get dashboardQuickactions;

  /// No description provided for @dashboardNewitem.
  ///
  /// In en, this message translates to:
  /// **'New Item'**
  String get dashboardNewitem;

  /// No description provided for @dashboardRecordsale.
  ///
  /// In en, this message translates to:
  /// **'Record Sale'**
  String get dashboardRecordsale;

  /// No description provided for @dashboardNewpurchase.
  ///
  /// In en, this message translates to:
  /// **'New Purchase'**
  String get dashboardNewpurchase;

  /// No description provided for @dashboardStockmovement.
  ///
  /// In en, this message translates to:
  /// **'Stock Movement'**
  String get dashboardStockmovement;

  /// No description provided for @dashboardLivingecosystem.
  ///
  /// In en, this message translates to:
  /// **'Living Ecosystem'**
  String get dashboardLivingecosystem;

  /// No description provided for @dashboardcustomizationCustomize.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get dashboardcustomizationCustomize;

  /// No description provided for @dashboardcustomizationDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dashboardcustomizationDone;

  /// No description provided for @dashboardcustomizationSave.
  ///
  /// In en, this message translates to:
  /// **'Save Layout'**
  String get dashboardcustomizationSave;

  /// No description provided for @dashboardcustomizationSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get dashboardcustomizationSaving;

  /// No description provided for @dashboardcustomizationSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get dashboardcustomizationSaved;

  /// No description provided for @dashboardcustomizationUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get dashboardcustomizationUnsaved;

  /// No description provided for @dashboardcustomizationSavefailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get dashboardcustomizationSavefailed;

  /// No description provided for @dashboardcustomizationSaveretrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying...'**
  String get dashboardcustomizationSaveretrying;

  /// No description provided for @dashboardcustomizationRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert to Default'**
  String get dashboardcustomizationRevert;

  /// No description provided for @dashboardcustomizationRevertconfirmtitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Dashboard Layout?'**
  String get dashboardcustomizationRevertconfirmtitle;

  /// No description provided for @dashboardcustomizationRevertconfirmmsg.
  ///
  /// In en, this message translates to:
  /// **'This will remove all your custom blocks and reset the dashboard to its default layout. This cannot be undone.'**
  String get dashboardcustomizationRevertconfirmmsg;

  /// No description provided for @dashboardcustomizationReverted.
  ///
  /// In en, this message translates to:
  /// **'Layout reverted to default'**
  String get dashboardcustomizationReverted;

  /// No description provided for @dashboardcustomizationBlockpalette.
  ///
  /// In en, this message translates to:
  /// **'Block Palette'**
  String get dashboardcustomizationBlockpalette;

  /// No description provided for @dashboardcustomizationAddblock.
  ///
  /// In en, this message translates to:
  /// **'Add to Dashboard'**
  String get dashboardcustomizationAddblock;

  /// No description provided for @dashboardcustomizationRemoveblock.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get dashboardcustomizationRemoveblock;

  /// No description provided for @dashboardcustomizationBlocksettings.
  ///
  /// In en, this message translates to:
  /// **'Block Settings'**
  String get dashboardcustomizationBlocksettings;

  /// No description provided for @dashboardcustomizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Block Title'**
  String get dashboardcustomizationTitle;

  /// No description provided for @dashboardcustomizationSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get dashboardcustomizationSize;

  /// No description provided for @dashboardcustomizationSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get dashboardcustomizationSmall;

  /// No description provided for @dashboardcustomizationMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get dashboardcustomizationMedium;

  /// No description provided for @dashboardcustomizationLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get dashboardcustomizationLarge;

  /// No description provided for @dashboardcustomizationRefreshinterval.
  ///
  /// In en, this message translates to:
  /// **'Refresh Interval'**
  String get dashboardcustomizationRefreshinterval;

  /// No description provided for @dashboardcustomizationNorefresh.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dashboardcustomizationNorefresh;

  /// No description provided for @dashboardcustomizationRefresh30s.
  ///
  /// In en, this message translates to:
  /// **'Every 30s'**
  String get dashboardcustomizationRefresh30s;

  /// No description provided for @dashboardcustomizationRefresh60s.
  ///
  /// In en, this message translates to:
  /// **'Every 60s'**
  String get dashboardcustomizationRefresh60s;

  /// No description provided for @dashboardcustomizationRefresh5m.
  ///
  /// In en, this message translates to:
  /// **'Every 5 min'**
  String get dashboardcustomizationRefresh5m;

  /// No description provided for @dashboardcustomizationRefresh15m.
  ///
  /// In en, this message translates to:
  /// **'Every 15 min'**
  String get dashboardcustomizationRefresh15m;

  /// No description provided for @dashboardcustomizationDeleteblock.
  ///
  /// In en, this message translates to:
  /// **'Delete Block'**
  String get dashboardcustomizationDeleteblock;

  /// No description provided for @dashboardcustomizationDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String dashboardcustomizationDeleteconfirm(Object title);

  /// No description provided for @dashboardcustomizationDeleteconfirmmsg.
  ///
  /// In en, this message translates to:
  /// **'This block will be removed from your dashboard.'**
  String get dashboardcustomizationDeleteconfirmmsg;

  /// No description provided for @dashboardcustomizationLayoutsaved.
  ///
  /// In en, this message translates to:
  /// **'Layout saved'**
  String get dashboardcustomizationLayoutsaved;

  /// No description provided for @dashboardcustomizationBlockadded.
  ///
  /// In en, this message translates to:
  /// **'Block added to dashboard'**
  String get dashboardcustomizationBlockadded;

  /// No description provided for @dashboardcustomizationBlockremoved.
  ///
  /// In en, this message translates to:
  /// **'Block removed'**
  String get dashboardcustomizationBlockremoved;

  /// No description provided for @dashboardcustomizationDraghint.
  ///
  /// In en, this message translates to:
  /// **'Drag blocks to rearrange'**
  String get dashboardcustomizationDraghint;

  /// No description provided for @dashboardcustomizationUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get dashboardcustomizationUndo;

  /// No description provided for @dashboardcustomizationRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get dashboardcustomizationRedo;

  /// No description provided for @dashboardcustomizationMobilepalettetitle.
  ///
  /// In en, this message translates to:
  /// **'Add a Block'**
  String get dashboardcustomizationMobilepalettetitle;

  /// No description provided for @dashboardcustomizationMobilepalettedesc.
  ///
  /// In en, this message translates to:
  /// **'Select a block type to add to your dashboard'**
  String get dashboardcustomizationMobilepalettedesc;

  /// No description provided for @dashboardcustomizationDeprecatedblock.
  ///
  /// In en, this message translates to:
  /// **'This block type is no longer available'**
  String get dashboardcustomizationDeprecatedblock;

  /// No description provided for @dashboardcustomizationDeprecatedremove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get dashboardcustomizationDeprecatedremove;

  /// No description provided for @dashboardcustomizationEditshortcuts.
  ///
  /// In en, this message translates to:
  /// **'Escape to exit, Delete to remove, Ctrl+Z to undo'**
  String get dashboardcustomizationEditshortcuts;

  /// No description provided for @dashboardcustomizationSyncedfromothertab.
  ///
  /// In en, this message translates to:
  /// **'Dashboard updated from another tab'**
  String get dashboardcustomizationSyncedfromothertab;

  /// No description provided for @dashboardcustomizationBlockstatcards.
  ///
  /// In en, this message translates to:
  /// **'Stat Cards'**
  String get dashboardcustomizationBlockstatcards;

  /// No description provided for @dashboardcustomizationBlocksalespurchases.
  ///
  /// In en, this message translates to:
  /// **'Sales vs Purchases'**
  String get dashboardcustomizationBlocksalespurchases;

  /// No description provided for @dashboardcustomizationBlockstockbycategory.
  ///
  /// In en, this message translates to:
  /// **'Stock by Category'**
  String get dashboardcustomizationBlockstockbycategory;

  /// No description provided for @dashboardcustomizationBlocklowstock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get dashboardcustomizationBlocklowstock;

  /// No description provided for @dashboardcustomizationBlockquickactions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get dashboardcustomizationBlockquickactions;

  /// No description provided for @dashboardcustomizationBlockrecentactivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get dashboardcustomizationBlockrecentactivity;

  /// No description provided for @dashboardcustomizationBlockarsummary.
  ///
  /// In en, this message translates to:
  /// **'AR Summary'**
  String get dashboardcustomizationBlockarsummary;

  /// No description provided for @dashboardcustomizationBlocktopcustomers.
  ///
  /// In en, this message translates to:
  /// **'Top Customers'**
  String get dashboardcustomizationBlocktopcustomers;

  /// No description provided for @dashboardcustomizationBlockforecastsnapshot.
  ///
  /// In en, this message translates to:
  /// **'Forecast Snapshot'**
  String get dashboardcustomizationBlockforecastsnapshot;

  /// No description provided for @dashboardcustomizationBlocksalessummary.
  ///
  /// In en, this message translates to:
  /// **'Sales Summary'**
  String get dashboardcustomizationBlocksalessummary;

  /// No description provided for @dashboardcustomizationBlockexpensesummary.
  ///
  /// In en, this message translates to:
  /// **'Expense Summary'**
  String get dashboardcustomizationBlockexpensesummary;

  /// No description provided for @dashboardcustomizationBlockproductionstatus.
  ///
  /// In en, this message translates to:
  /// **'Production Status'**
  String get dashboardcustomizationBlockproductionstatus;

  /// No description provided for @dashboardcustomizationBlockstockmovements.
  ///
  /// In en, this message translates to:
  /// **'Stock Movement Summary'**
  String get dashboardcustomizationBlockstockmovements;

  /// No description provided for @dashboardcustomizationBlockcustomtext.
  ///
  /// In en, this message translates to:
  /// **'Text / Heading'**
  String get dashboardcustomizationBlockcustomtext;

  /// No description provided for @dashboardcustomizationBlockkpigauge.
  ///
  /// In en, this message translates to:
  /// **'KPI Gauge'**
  String get dashboardcustomizationBlockkpigauge;

  /// No description provided for @dashboardcustomizationBlockstatcardsdesc.
  ///
  /// In en, this message translates to:
  /// **'Total Items, Stock Value, Sales, Production'**
  String get dashboardcustomizationBlockstatcardsdesc;

  /// No description provided for @dashboardcustomizationBlocksalespurchasesdesc.
  ///
  /// In en, this message translates to:
  /// **'7-day sales vs purchases line chart'**
  String get dashboardcustomizationBlocksalespurchasesdesc;

  /// No description provided for @dashboardcustomizationBlockstockbycategorydesc.
  ///
  /// In en, this message translates to:
  /// **'Stock distribution by category'**
  String get dashboardcustomizationBlockstockbycategorydesc;

  /// No description provided for @dashboardcustomizationBlocklowstockdesc.
  ///
  /// In en, this message translates to:
  /// **'Items below reorder level'**
  String get dashboardcustomizationBlocklowstockdesc;

  /// No description provided for @dashboardcustomizationBlockquickactionsdesc.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts to common pages'**
  String get dashboardcustomizationBlockquickactionsdesc;

  /// No description provided for @dashboardcustomizationBlockrecentactivitydesc.
  ///
  /// In en, this message translates to:
  /// **'Latest system activity'**
  String get dashboardcustomizationBlockrecentactivitydesc;

  /// No description provided for @dashboardcustomizationBlockarsummarydesc.
  ///
  /// In en, this message translates to:
  /// **'Accounts receivable aging'**
  String get dashboardcustomizationBlockarsummarydesc;

  /// No description provided for @dashboardcustomizationBlocktopcustomersdesc.
  ///
  /// In en, this message translates to:
  /// **'Top customers by revenue'**
  String get dashboardcustomizationBlocktopcustomersdesc;

  /// No description provided for @dashboardcustomizationBlockforecastsnapshotdesc.
  ///
  /// In en, this message translates to:
  /// **'Forecast KPIs and metrics'**
  String get dashboardcustomizationBlockforecastsnapshotdesc;

  /// No description provided for @dashboardcustomizationBlocksalessummarydesc.
  ///
  /// In en, this message translates to:
  /// **'Today / Week / Month sales totals'**
  String get dashboardcustomizationBlocksalessummarydesc;

  /// No description provided for @dashboardcustomizationBlockexpensesummarydesc.
  ///
  /// In en, this message translates to:
  /// **'Recent expenses and totals'**
  String get dashboardcustomizationBlockexpensesummarydesc;

  /// No description provided for @dashboardcustomizationBlockproductionstatusdesc.
  ///
  /// In en, this message translates to:
  /// **'Active production orders'**
  String get dashboardcustomizationBlockproductionstatusdesc;

  /// No description provided for @dashboardcustomizationBlockstockmovementsdesc.
  ///
  /// In en, this message translates to:
  /// **'Recent stock in/out movements'**
  String get dashboardcustomizationBlockstockmovementsdesc;

  /// No description provided for @dashboardcustomizationBlockcustomtextdesc.
  ///
  /// In en, this message translates to:
  /// **'Custom heading or notes'**
  String get dashboardcustomizationBlockcustomtextdesc;

  /// No description provided for @dashboardcustomizationBlockkpigaugedesc.
  ///
  /// In en, this message translates to:
  /// **'Single configurable KPI gauge'**
  String get dashboardcustomizationBlockkpigaugedesc;

  /// No description provided for @customersCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersCustomers;

  /// No description provided for @customersNewcustomer.
  ///
  /// In en, this message translates to:
  /// **'New Customer'**
  String get customersNewcustomer;

  /// No description provided for @customersCustomername.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get customersCustomername;

  /// No description provided for @customersPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get customersPhone;

  /// No description provided for @customersEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get customersEmail;

  /// No description provided for @customersAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get customersAddress;

  /// No description provided for @customersActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get customersActions;

  /// No description provided for @customersSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get customersSave;

  /// No description provided for @customersDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get customersDelete;

  /// No description provided for @customersConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get customersConfirmdelete;

  /// No description provided for @customersCustomerdeleted.
  ///
  /// In en, this message translates to:
  /// **'Customer deleted successfully!'**
  String get customersCustomerdeleted;

  /// No description provided for @customersDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String customersDays(Object days);

  /// No description provided for @customersContactinfo.
  ///
  /// In en, this message translates to:
  /// **'Contact Info'**
  String get customersContactinfo;

  /// No description provided for @customersFixbalances.
  ///
  /// In en, this message translates to:
  /// **'Fix Balances'**
  String get customersFixbalances;

  /// No description provided for @customersFixbalancesconfirm.
  ///
  /// In en, this message translates to:
  /// **'This will recalculate all customer balances from unpaid invoices. Continue?'**
  String get customersFixbalancesconfirm;

  /// No description provided for @customersFixbalancessuccess.
  ///
  /// In en, this message translates to:
  /// **'Balances recalculated successfully'**
  String get customersFixbalancessuccess;

  /// No description provided for @customersNotapplicable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get customersNotapplicable;

  /// No description provided for @suppliersSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliersSuppliers;

  /// No description provided for @suppliersNewsupplier.
  ///
  /// In en, this message translates to:
  /// **'New Supplier'**
  String get suppliersNewsupplier;

  /// No description provided for @suppliersSuppliername.
  ///
  /// In en, this message translates to:
  /// **'Supplier Name'**
  String get suppliersSuppliername;

  /// No description provided for @suppliersBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get suppliersBalance;

  /// No description provided for @suppliersContactperson.
  ///
  /// In en, this message translates to:
  /// **'Contact Person'**
  String get suppliersContactperson;

  /// No description provided for @suppliersCreditutilization.
  ///
  /// In en, this message translates to:
  /// **'Credit Utilization'**
  String get suppliersCreditutilization;

  /// No description provided for @suppliersNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get suppliersNotes;

  /// No description provided for @suppliersPaymentterms.
  ///
  /// In en, this message translates to:
  /// **'Payment Terms'**
  String get suppliersPaymentterms;

  /// No description provided for @suppliersSuppliercode.
  ///
  /// In en, this message translates to:
  /// **'Supplier Code'**
  String get suppliersSuppliercode;

  /// No description provided for @suppliersSupplierdetails.
  ///
  /// In en, this message translates to:
  /// **'Supplier Details'**
  String get suppliersSupplierdetails;

  /// No description provided for @suppliersPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get suppliersPhone;

  /// No description provided for @suppliersEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get suppliersEmail;

  /// No description provided for @suppliersEditsupplier.
  ///
  /// In en, this message translates to:
  /// **'Edit Supplier'**
  String get suppliersEditsupplier;

  /// No description provided for @suppliersErrorCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Supplier code is required'**
  String get suppliersErrorCodeRequired;

  /// No description provided for @suppliersErrorEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get suppliersErrorEmail;

  /// No description provided for @suppliersErrorNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Supplier name is required'**
  String get suppliersErrorNameRequired;

  /// No description provided for @suppliersAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get suppliersAddress;

  /// No description provided for @suppliersActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get suppliersActions;

  /// No description provided for @suppliersLedger.
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get suppliersLedger;

  /// No description provided for @suppliersLedgerDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get suppliersLedgerDebit;

  /// No description provided for @suppliersLedgerCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get suppliersLedgerCredit;

  /// No description provided for @suppliersLedgerClosingbalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get suppliersLedgerClosingbalance;

  /// No description provided for @suppliersLedgerNoentries.
  ///
  /// In en, this message translates to:
  /// **'No ledger entries found'**
  String get suppliersLedgerNoentries;

  /// No description provided for @suppliersStatement.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get suppliersStatement;

  /// No description provided for @suppliersOpeningbalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get suppliersOpeningbalance;

  /// No description provided for @suppliersClosingbalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get suppliersClosingbalance;

  /// No description provided for @suppliersOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get suppliersOverview;

  /// No description provided for @suppliersPos.
  ///
  /// In en, this message translates to:
  /// **'POs'**
  String get suppliersPos;

  /// No description provided for @suppliersPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get suppliersPayments;

  /// No description provided for @suppliersBacktosuppliers.
  ///
  /// In en, this message translates to:
  /// **'Back to Suppliers'**
  String get suppliersBacktosuppliers;

  /// No description provided for @suppliersRecordpayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get suppliersRecordpayment;

  /// No description provided for @suppliersFinancialsummary.
  ///
  /// In en, this message translates to:
  /// **'Financial Summary'**
  String get suppliersFinancialsummary;

  /// No description provided for @suppliersCurrentbalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get suppliersCurrentbalance;

  /// No description provided for @suppliersTotalpovalue.
  ///
  /// In en, this message translates to:
  /// **'Total PO Value'**
  String get suppliersTotalpovalue;

  /// No description provided for @suppliersTotalpos.
  ///
  /// In en, this message translates to:
  /// **'Total POs'**
  String get suppliersTotalpos;

  /// No description provided for @suppliersPostatus.
  ///
  /// In en, this message translates to:
  /// **'Purchase Order Status'**
  String get suppliersPostatus;

  /// No description provided for @suppliersDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get suppliersDraft;

  /// No description provided for @suppliersSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get suppliersSubmitted;

  /// No description provided for @suppliersPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get suppliersPartial;

  /// No description provided for @suppliersCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get suppliersCompleted;

  /// No description provided for @suppliersContactinfo.
  ///
  /// In en, this message translates to:
  /// **'Contact Info'**
  String get suppliersContactinfo;

  /// No description provided for @suppliersAccountsettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get suppliersAccountsettings;

  /// No description provided for @suppliersSincesupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier Since'**
  String get suppliersSincesupplier;

  /// No description provided for @suppliersNopos.
  ///
  /// In en, this message translates to:
  /// **'No purchase orders found'**
  String get suppliersNopos;

  /// No description provided for @suppliersPono.
  ///
  /// In en, this message translates to:
  /// **'PO No'**
  String get suppliersPono;

  /// No description provided for @suppliersTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get suppliersTotal;

  /// No description provided for @suppliersExpecteddelivery.
  ///
  /// In en, this message translates to:
  /// **'Expected Delivery'**
  String get suppliersExpecteddelivery;

  /// No description provided for @suppliersLedgerType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get suppliersLedgerType;

  /// No description provided for @suppliersLedgerTotals.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get suppliersLedgerTotals;

  /// No description provided for @suppliersLedgerTotaldebit.
  ///
  /// In en, this message translates to:
  /// **'Total Debit'**
  String get suppliersLedgerTotaldebit;

  /// No description provided for @suppliersLedgerTotalcredit.
  ///
  /// In en, this message translates to:
  /// **'Total Credit'**
  String get suppliersLedgerTotalcredit;

  /// No description provided for @suppliersExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get suppliersExportcsv;

  /// No description provided for @suppliersExportpdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get suppliersExportpdf;

  /// No description provided for @suppliersExportimage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get suppliersExportimage;

  /// No description provided for @suppliersExportsuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported successfully'**
  String get suppliersExportsuccess;

  /// No description provided for @suppliersNopayments.
  ///
  /// In en, this message translates to:
  /// **'No payments found'**
  String get suppliersNopayments;

  /// No description provided for @suppliersPaymentno.
  ///
  /// In en, this message translates to:
  /// **'Payment No'**
  String get suppliersPaymentno;

  /// No description provided for @suppliersAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get suppliersAmount;

  /// No description provided for @suppliersMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get suppliersMethod;

  /// No description provided for @suppliersReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get suppliersReference;

  /// No description provided for @suppliersPrintreceipt.
  ///
  /// In en, this message translates to:
  /// **'Print Receipt'**
  String get suppliersPrintreceipt;

  /// No description provided for @suppliersPrintreceipta4.
  ///
  /// In en, this message translates to:
  /// **'Print Receipt (A4)'**
  String get suppliersPrintreceipta4;

  /// No description provided for @suppliersDeletepayment.
  ///
  /// In en, this message translates to:
  /// **'Delete Payment'**
  String get suppliersDeletepayment;

  /// No description provided for @suppliersConfirmdeletepayment.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete payment'**
  String get suppliersConfirmdeletepayment;

  /// No description provided for @suppliersPaymentdeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment deleted successfully!'**
  String get suppliersPaymentdeleted;

  /// No description provided for @suppliersStatementsummary.
  ///
  /// In en, this message translates to:
  /// **'Statement Summary'**
  String get suppliersStatementsummary;

  /// No description provided for @suppliersTotaldebits.
  ///
  /// In en, this message translates to:
  /// **'Total Debits'**
  String get suppliersTotaldebits;

  /// No description provided for @suppliersTotalcredits.
  ///
  /// In en, this message translates to:
  /// **'Total Credits'**
  String get suppliersTotalcredits;

  /// No description provided for @suppliersTransactiondetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get suppliersTransactiondetails;

  /// No description provided for @suppliersBeginningbalance.
  ///
  /// In en, this message translates to:
  /// **'Beginning balance'**
  String get suppliersBeginningbalance;

  /// No description provided for @suppliersEndingbalance.
  ///
  /// In en, this message translates to:
  /// **'Ending balance'**
  String get suppliersEndingbalance;

  /// No description provided for @suppliersTotalamount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get suppliersTotalamount;

  /// No description provided for @suppliersAllocation.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get suppliersAllocation;

  /// No description provided for @suppliersAvailablepos.
  ///
  /// In en, this message translates to:
  /// **'Available POs'**
  String get suppliersAvailablepos;

  /// No description provided for @suppliersAutoallocate.
  ///
  /// In en, this message translates to:
  /// **'Auto Allocate'**
  String get suppliersAutoallocate;

  /// No description provided for @suppliersAllposallocated.
  ///
  /// In en, this message translates to:
  /// **'All available POs are allocated'**
  String get suppliersAllposallocated;

  /// No description provided for @suppliersNoopenpos.
  ///
  /// In en, this message translates to:
  /// **'No open purchase orders to allocate against'**
  String get suppliersNoopenpos;

  /// No description provided for @suppliersAllocatedpos.
  ///
  /// In en, this message translates to:
  /// **'Allocated POs'**
  String get suppliersAllocatedpos;

  /// No description provided for @suppliersUnallocated.
  ///
  /// In en, this message translates to:
  /// **'Unallocated Amount'**
  String get suppliersUnallocated;

  /// No description provided for @suppliersAllocationrequired.
  ///
  /// In en, this message translates to:
  /// **'At least one PO allocation is required'**
  String get suppliersAllocationrequired;

  /// No description provided for @suppliersAmountmustmatch.
  ///
  /// In en, this message translates to:
  /// **'Amount must match total allocated'**
  String get suppliersAmountmustmatch;

  /// No description provided for @suppliersPaymentrecordedsuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment Recorded Successfully'**
  String get suppliersPaymentrecordedsuccess;

  /// No description provided for @suppliersWhatnext.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do next?'**
  String get suppliersWhatnext;

  /// No description provided for @suppliersDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get suppliersDelete;

  /// No description provided for @suppliersConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get suppliersConfirmdelete;

  /// No description provided for @suppliersSupplierdeleted.
  ///
  /// In en, this message translates to:
  /// **'Supplier deleted successfully!'**
  String get suppliersSupplierdeleted;

  /// No description provided for @suppliersFixbalances.
  ///
  /// In en, this message translates to:
  /// **'Fix Balances'**
  String get suppliersFixbalances;

  /// No description provided for @suppliersFixbalancesconfirm.
  ///
  /// In en, this message translates to:
  /// **'This will recalculate all supplier balances from their ledger entries. Continue?'**
  String get suppliersFixbalancesconfirm;

  /// No description provided for @suppliersBalancesrecalculated.
  ///
  /// In en, this message translates to:
  /// **'Supplier balances recalculated successfully'**
  String get suppliersBalancesrecalculated;

  /// No description provided for @reportsReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsReports;

  /// No description provided for @reportsReportsdashboard.
  ///
  /// In en, this message translates to:
  /// **'Reports Dashboard'**
  String get reportsReportsdashboard;

  /// No description provided for @reportsLowstockalertreport.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alert Report'**
  String get reportsLowstockalertreport;

  /// No description provided for @reportsStockvaluationreport.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation Report'**
  String get reportsStockvaluationreport;

  /// No description provided for @reportsSalessummaryreport.
  ///
  /// In en, this message translates to:
  /// **'Sales Summary Report'**
  String get reportsSalessummaryreport;

  /// No description provided for @reportsProfitlossreport.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss Report'**
  String get reportsProfitlossreport;

  /// No description provided for @reportsCashflowreport.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow Report'**
  String get reportsCashflowreport;

  /// No description provided for @reportsExpensesreport.
  ///
  /// In en, this message translates to:
  /// **'Expenses Report'**
  String get reportsExpensesreport;

  /// No description provided for @reportsStocklevelreport.
  ///
  /// In en, this message translates to:
  /// **'Stock Level Report'**
  String get reportsStocklevelreport;

  /// No description provided for @reportsInventorymovementreport.
  ///
  /// In en, this message translates to:
  /// **'Inventory Movement Report'**
  String get reportsInventorymovementreport;

  /// No description provided for @reportsTopdebtorsreport.
  ///
  /// In en, this message translates to:
  /// **'Top Debtors Report'**
  String get reportsTopdebtorsreport;

  /// No description provided for @reportsSupplieranalysisreport.
  ///
  /// In en, this message translates to:
  /// **'Supplier Analysis Report'**
  String get reportsSupplieranalysisreport;

  /// No description provided for @reportsPurchasesummaryreport.
  ///
  /// In en, this message translates to:
  /// **'Purchase Summary Report'**
  String get reportsPurchasesummaryreport;

  /// No description provided for @reportsOpeningbalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get reportsOpeningbalance;

  /// No description provided for @reportsTotaldebits.
  ///
  /// In en, this message translates to:
  /// **'Total Debits'**
  String get reportsTotaldebits;

  /// No description provided for @reportsTotalcredits.
  ///
  /// In en, this message translates to:
  /// **'Total Credits'**
  String get reportsTotalcredits;

  /// No description provided for @reportsClosingbalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get reportsClosingbalance;

  /// No description provided for @reportsTotalamount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get reportsTotalamount;

  /// No description provided for @reportsPaidamount.
  ///
  /// In en, this message translates to:
  /// **'Paid Amount'**
  String get reportsPaidamount;

  /// No description provided for @reportsLastinvoicedate.
  ///
  /// In en, this message translates to:
  /// **'Last Invoice Date'**
  String get reportsLastinvoicedate;

  /// No description provided for @reportsAllcustomers.
  ///
  /// In en, this message translates to:
  /// **'All Customers'**
  String get reportsAllcustomers;

  /// No description provided for @reportsProductionsummaryreport.
  ///
  /// In en, this message translates to:
  /// **'Production Summary Report'**
  String get reportsProductionsummaryreport;

  /// No description provided for @reportsSalesbyitemreport.
  ///
  /// In en, this message translates to:
  /// **'Sales by Item Report'**
  String get reportsSalesbyitemreport;

  /// No description provided for @reportsSalesbycustomerreport.
  ///
  /// In en, this message translates to:
  /// **'Sales by Customer Report'**
  String get reportsSalesbycustomerreport;

  /// No description provided for @reportsCustomerstatementsreport.
  ///
  /// In en, this message translates to:
  /// **'Customer Statements Report'**
  String get reportsCustomerstatementsreport;

  /// No description provided for @reportsDsoreport.
  ///
  /// In en, this message translates to:
  /// **'Days Sales Outstanding (DSO) Report'**
  String get reportsDsoreport;

  /// No description provided for @reportsAr_reports.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable Reports'**
  String get reportsAr_reports;

  /// No description provided for @reportsTabsAr_aging.
  ///
  /// In en, this message translates to:
  /// **'AR Aging'**
  String get reportsTabsAr_aging;

  /// No description provided for @reportsTabsReceivables_summary.
  ///
  /// In en, this message translates to:
  /// **'Receivables Summary'**
  String get reportsTabsReceivables_summary;

  /// No description provided for @reportsTabsTop_debtors.
  ///
  /// In en, this message translates to:
  /// **'Top Debtors'**
  String get reportsTabsTop_debtors;

  /// No description provided for @reportsTabsDso.
  ///
  /// In en, this message translates to:
  /// **'Days Sales Outstanding'**
  String get reportsTabsDso;

  /// No description provided for @reportsAccountsreceivablereports.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable Reports'**
  String get reportsAccountsreceivablereports;

  /// No description provided for @reportsAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of'**
  String get reportsAsOf;

  /// No description provided for @reportsAvginvoicevalue.
  ///
  /// In en, this message translates to:
  /// **'Avg. Invoice Value'**
  String get reportsAvginvoicevalue;

  /// No description provided for @reportsBomusage.
  ///
  /// In en, this message translates to:
  /// **'BOM Usage'**
  String get reportsBomusage;

  /// No description provided for @reportsCategoryAr.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable'**
  String get reportsCategoryAr;

  /// No description provided for @reportsCategoryFinancial.
  ///
  /// In en, this message translates to:
  /// **'Financial Reports'**
  String get reportsCategoryFinancial;

  /// No description provided for @reportsCategoryInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory Reports'**
  String get reportsCategoryInventory;

  /// No description provided for @reportsCategoryProduction.
  ///
  /// In en, this message translates to:
  /// **'Production Reports'**
  String get reportsCategoryProduction;

  /// No description provided for @reportsCategoryPurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase Reports'**
  String get reportsCategoryPurchase;

  /// No description provided for @reportsCategorySales.
  ///
  /// In en, this message translates to:
  /// **'Sales Reports'**
  String get reportsCategorySales;

  /// No description provided for @reportsCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get reportsCurrent;

  /// No description provided for @reportsDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Comprehensive business analytics and reporting'**
  String get reportsDashboardSubtitle;

  /// No description provided for @reportsDays1_30.
  ///
  /// In en, this message translates to:
  /// **'1-30 Days'**
  String get reportsDays1_30;

  /// No description provided for @reportsDays31_60.
  ///
  /// In en, this message translates to:
  /// **'31-60 Days'**
  String get reportsDays31_60;

  /// No description provided for @reportsDays61_90.
  ///
  /// In en, this message translates to:
  /// **'61-90 Days'**
  String get reportsDays61_90;

  /// No description provided for @reportsDays90plus.
  ///
  /// In en, this message translates to:
  /// **'90+ Days'**
  String get reportsDays90plus;

  /// No description provided for @reportsItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get reportsItems;

  /// No description provided for @reportsItemssold.
  ///
  /// In en, this message translates to:
  /// **'Items Sold'**
  String get reportsItemssold;

  /// No description provided for @reportsLowstockcount.
  ///
  /// In en, this message translates to:
  /// **'low stock items'**
  String get reportsLowstockcount;

  /// No description provided for @reportsMinimumstock.
  ///
  /// In en, this message translates to:
  /// **'Minimum Stock'**
  String get reportsMinimumstock;

  /// No description provided for @reportsSellingprice.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get reportsSellingprice;

  /// No description provided for @reportsShortage.
  ///
  /// In en, this message translates to:
  /// **'Shortage'**
  String get reportsShortage;

  /// No description provided for @reportsShortagetotal.
  ///
  /// In en, this message translates to:
  /// **'Shortage total'**
  String get reportsShortagetotal;

  /// No description provided for @reportsStockstatus.
  ///
  /// In en, this message translates to:
  /// **'Stock Status'**
  String get reportsStockstatus;

  /// No description provided for @reportsTotalinvoices.
  ///
  /// In en, this message translates to:
  /// **'Total Invoices'**
  String get reportsTotalinvoices;

  /// No description provided for @reportsTotaloutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total Outstanding'**
  String get reportsTotaloutstanding;

  /// No description provided for @reportsTotalreceivables.
  ///
  /// In en, this message translates to:
  /// **'Total Receivables'**
  String get reportsTotalreceivables;

  /// No description provided for @reportsTotalsales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get reportsTotalsales;

  /// No description provided for @reportsTotalitems.
  ///
  /// In en, this message translates to:
  /// **'Total Items'**
  String get reportsTotalitems;

  /// No description provided for @reportsTotalinventoryvalue.
  ///
  /// In en, this message translates to:
  /// **'Total Inventory Value'**
  String get reportsTotalinventoryvalue;

  /// No description provided for @reportsUnitcost.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost'**
  String get reportsUnitcost;

  /// No description provided for @reportsTotalvalue.
  ///
  /// In en, this message translates to:
  /// **'Total Value'**
  String get reportsTotalvalue;

  /// No description provided for @reportsValuationmethod.
  ///
  /// In en, this message translates to:
  /// **'Valuation Method'**
  String get reportsValuationmethod;

  /// No description provided for @reportsBatchtracked.
  ///
  /// In en, this message translates to:
  /// **'Batch Tracked'**
  String get reportsBatchtracked;

  /// No description provided for @reportsLegacyitems.
  ///
  /// In en, this message translates to:
  /// **'Legacy Items'**
  String get reportsLegacyitems;

  /// No description provided for @reportsAvgordervalue.
  ///
  /// In en, this message translates to:
  /// **'Avg. Order Value'**
  String get reportsAvgordervalue;

  /// No description provided for @reportsLastpurchase.
  ///
  /// In en, this message translates to:
  /// **'Last Purchase'**
  String get reportsLastpurchase;

  /// No description provided for @reportsExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get reportsExportcsv;

  /// No description provided for @reportsExported.
  ///
  /// In en, this message translates to:
  /// **'Report exported'**
  String get reportsExported;

  /// No description provided for @reportsExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export report'**
  String get reportsExportfailed;

  /// No description provided for @reportsTotalquantitysold.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity Sold'**
  String get reportsTotalquantitysold;

  /// No description provided for @reportsAvgsellingprice.
  ///
  /// In en, this message translates to:
  /// **'Avg. Selling Price'**
  String get reportsAvgsellingprice;

  /// No description provided for @reportsQuantitysold.
  ///
  /// In en, this message translates to:
  /// **'Quantity Sold'**
  String get reportsQuantitysold;

  /// No description provided for @reportsTotalpurchasevalue.
  ///
  /// In en, this message translates to:
  /// **'Total Purchase Value'**
  String get reportsTotalpurchasevalue;

  /// No description provided for @reportsOntimedeliveryrate.
  ///
  /// In en, this message translates to:
  /// **'On-time Delivery Rate'**
  String get reportsOntimedeliveryrate;

  /// No description provided for @reportsTotalproductionorders.
  ///
  /// In en, this message translates to:
  /// **'Total Production Orders'**
  String get reportsTotalproductionorders;

  /// No description provided for @reportsTotaloutputquantity.
  ///
  /// In en, this message translates to:
  /// **'Total Output Quantity'**
  String get reportsTotaloutputquantity;

  /// No description provided for @reportsCompletedquantity.
  ///
  /// In en, this message translates to:
  /// **'Completed Quantity'**
  String get reportsCompletedquantity;

  /// No description provided for @reportsScrappedquantity.
  ///
  /// In en, this message translates to:
  /// **'Scrapped Quantity'**
  String get reportsScrappedquantity;

  /// No description provided for @reportsProductiondate.
  ///
  /// In en, this message translates to:
  /// **'Production Date'**
  String get reportsProductiondate;

  /// No description provided for @reportsProductionorder.
  ///
  /// In en, this message translates to:
  /// **'Production Order'**
  String get reportsProductionorder;

  /// No description provided for @reportsOutputitem.
  ///
  /// In en, this message translates to:
  /// **'Output Item'**
  String get reportsOutputitem;

  /// No description provided for @reportsOutputquantity.
  ///
  /// In en, this message translates to:
  /// **'Output Quantity'**
  String get reportsOutputquantity;

  /// No description provided for @reportsPlannedquantity.
  ///
  /// In en, this message translates to:
  /// **'Planned Quantity'**
  String get reportsPlannedquantity;

  /// No description provided for @reportsParentitem.
  ///
  /// In en, this message translates to:
  /// **'Parent Item'**
  String get reportsParentitem;

  /// No description provided for @reportsUsagecount.
  ///
  /// In en, this message translates to:
  /// **'Usage Count'**
  String get reportsUsagecount;

  /// No description provided for @reportsLastused.
  ///
  /// In en, this message translates to:
  /// **'Last Used'**
  String get reportsLastused;

  /// No description provided for @reportsTotalcomponents.
  ///
  /// In en, this message translates to:
  /// **'Total Components'**
  String get reportsTotalcomponents;

  /// No description provided for @reportsAllitems.
  ///
  /// In en, this message translates to:
  /// **'All Items'**
  String get reportsAllitems;

  /// No description provided for @fieldsMetric.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get fieldsMetric;

  /// No description provided for @fieldsValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get fieldsValue;

  /// No description provided for @reportsDsodays.
  ///
  /// In en, this message translates to:
  /// **'Days Sales Outstanding'**
  String get reportsDsodays;

  /// No description provided for @reportsDsounit.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get reportsDsounit;

  /// No description provided for @reportsDsosubtitle.
  ///
  /// In en, this message translates to:
  /// **'Measure of the average number of days it takes to collect payment after a sale.'**
  String get reportsDsosubtitle;

  /// No description provided for @reportsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get reportsPeriod;

  /// No description provided for @reportsTotalar.
  ///
  /// In en, this message translates to:
  /// **'Total AR'**
  String get reportsTotalar;

  /// No description provided for @reportsTotalinflow.
  ///
  /// In en, this message translates to:
  /// **'Total Cash Inflow'**
  String get reportsTotalinflow;

  /// No description provided for @reportsTotaloutflow.
  ///
  /// In en, this message translates to:
  /// **'Total Cash Outflow'**
  String get reportsTotaloutflow;

  /// No description provided for @reportsNetcashflow.
  ///
  /// In en, this message translates to:
  /// **'Net Cash Flow'**
  String get reportsNetcashflow;

  /// No description provided for @reportsCashflowpositive.
  ///
  /// In en, this message translates to:
  /// **'This period shows a positive cash flow, indicating good liquidity.'**
  String get reportsCashflowpositive;

  /// No description provided for @reportsCashflownegative.
  ///
  /// In en, this message translates to:
  /// **'This period shows a negative cash flow, consider reviewing expenses and cash outflows.'**
  String get reportsCashflownegative;

  /// No description provided for @reportsTotalrevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get reportsTotalrevenue;

  /// No description provided for @reportsTotalcogs.
  ///
  /// In en, this message translates to:
  /// **'Cost of Goods Sold (COGS)'**
  String get reportsTotalcogs;

  /// No description provided for @reportsGrossprofit.
  ///
  /// In en, this message translates to:
  /// **'Gross Profit'**
  String get reportsGrossprofit;

  /// No description provided for @reportsTotalexpenses.
  ///
  /// In en, this message translates to:
  /// **'Total Expenses'**
  String get reportsTotalexpenses;

  /// No description provided for @reportsTotalrecords.
  ///
  /// In en, this message translates to:
  /// **'Total Records'**
  String get reportsTotalrecords;

  /// No description provided for @reportsAverageexpense.
  ///
  /// In en, this message translates to:
  /// **'Average Expense'**
  String get reportsAverageexpense;

  /// No description provided for @reportsNetprofit.
  ///
  /// In en, this message translates to:
  /// **'Net Profit'**
  String get reportsNetprofit;

  /// No description provided for @reportsGrossprofitmargin.
  ///
  /// In en, this message translates to:
  /// **'Gross Profit Margin'**
  String get reportsGrossprofitmargin;

  /// No description provided for @reportsNetprofitmargin.
  ///
  /// In en, this message translates to:
  /// **'Net Profit Margin'**
  String get reportsNetprofitmargin;

  /// No description provided for @reportsExpensesbycategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by Category'**
  String get reportsExpensesbycategory;

  /// No description provided for @reportsTotalinbound.
  ///
  /// In en, this message translates to:
  /// **'Total Inbound'**
  String get reportsTotalinbound;

  /// No description provided for @reportsTotaloutbound.
  ///
  /// In en, this message translates to:
  /// **'Total Outbound'**
  String get reportsTotaloutbound;

  /// No description provided for @reportsNetmovement.
  ///
  /// In en, this message translates to:
  /// **'Net Movement'**
  String get reportsNetmovement;

  /// No description provided for @reportsMovementno.
  ///
  /// In en, this message translates to:
  /// **'Movement No'**
  String get reportsMovementno;

  /// No description provided for @reportsMovementtype.
  ///
  /// In en, this message translates to:
  /// **'Movement Type'**
  String get reportsMovementtype;

  /// No description provided for @reportsTotalorders.
  ///
  /// In en, this message translates to:
  /// **'Total Orders'**
  String get reportsTotalorders;

  /// No description provided for @reportsTotalcost.
  ///
  /// In en, this message translates to:
  /// **'Total Cost'**
  String get reportsTotalcost;

  /// No description provided for @reportsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received Amount'**
  String get reportsReceived;

  /// No description provided for @reportsBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get reportsBalance;

  /// No description provided for @reportsReturnvalue.
  ///
  /// In en, this message translates to:
  /// **'Returns Value'**
  String get reportsReturnvalue;

  /// No description provided for @reportsTotalinvoiced.
  ///
  /// In en, this message translates to:
  /// **'Total Invoiced'**
  String get reportsTotalinvoiced;

  /// No description provided for @reportsInvoicecount.
  ///
  /// In en, this message translates to:
  /// **'Invoice Count'**
  String get reportsInvoicecount;

  /// No description provided for @quotationsQuotations.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get quotationsQuotations;

  /// No description provided for @quotationsNewquotation.
  ///
  /// In en, this message translates to:
  /// **'New Quotation'**
  String get quotationsNewquotation;

  /// No description provided for @quotationsAdditem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get quotationsAdditem;

  /// No description provided for @quotationsDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Quotation Details'**
  String get quotationsDetailstitle;

  /// No description provided for @quotationsEditsquotation.
  ///
  /// In en, this message translates to:
  /// **'Edit Quotation'**
  String get quotationsEditsquotation;

  /// No description provided for @quotationsPrinta4.
  ///
  /// In en, this message translates to:
  /// **'Print A4'**
  String get quotationsPrinta4;

  /// No description provided for @quotationsErrorCustomerrequired.
  ///
  /// In en, this message translates to:
  /// **'Select a customer'**
  String get quotationsErrorCustomerrequired;

  /// No description provided for @quotationsErrorDate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get quotationsErrorDate;

  /// No description provided for @quotationsErrorItemsrequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item'**
  String get quotationsErrorItemsrequired;

  /// No description provided for @quotationsExpirydate.
  ///
  /// In en, this message translates to:
  /// **'Expiry Date'**
  String get quotationsExpirydate;

  /// No description provided for @quotationsExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get quotationsExportcsv;

  /// No description provided for @quotationsExported.
  ///
  /// In en, this message translates to:
  /// **'Quotations exported'**
  String get quotationsExported;

  /// No description provided for @quotationsExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export quotations'**
  String get quotationsExportfailed;

  /// No description provided for @quotationsItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get quotationsItem;

  /// No description provided for @quotationsQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quotationsQuantity;

  /// No description provided for @quotationsQuotationdate.
  ///
  /// In en, this message translates to:
  /// **'Quotation Date'**
  String get quotationsQuotationdate;

  /// No description provided for @quotationsSaved.
  ///
  /// In en, this message translates to:
  /// **'Quotation saved'**
  String get quotationsSaved;

  /// No description provided for @quotationsSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search quotations...'**
  String get quotationsSearchplaceholder;

  /// No description provided for @quotationsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get quotationsTerms;

  /// No description provided for @quotationsUnitprice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get quotationsUnitprice;

  /// No description provided for @quotationsQuotation.
  ///
  /// In en, this message translates to:
  /// **'Quotation #'**
  String get quotationsQuotation;

  /// No description provided for @quotationsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get quotationsCustomer;

  /// No description provided for @quotationsAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get quotationsAmount;

  /// No description provided for @quotationsDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get quotationsDate;

  /// No description provided for @quotationsExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get quotationsExpiry;

  /// No description provided for @quotationsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get quotationsStatus;

  /// No description provided for @quotationsActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get quotationsActions;

  /// No description provided for @quotationsDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get quotationsDraft;

  /// No description provided for @quotationsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get quotationsSent;

  /// No description provided for @quotationsConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get quotationsConverted;

  /// No description provided for @quotationsAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get quotationsAccepted;

  /// No description provided for @quotationsRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get quotationsRejected;

  /// No description provided for @quotationsExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get quotationsExpired;

  /// No description provided for @quotationsViewdetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get quotationsViewdetails;

  /// No description provided for @quotationsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get quotationsEdit;

  /// No description provided for @quotationsConvertconfirm.
  ///
  /// In en, this message translates to:
  /// **'This will create a sales order from this quotation and mark it as converted. Continue?'**
  String get quotationsConvertconfirm;

  /// No description provided for @quotationsConvertedmsg.
  ///
  /// In en, this message translates to:
  /// **'Quotation converted — sales order {soNo} created'**
  String quotationsConvertedmsg(Object soNo);

  /// No description provided for @quotationsConverttoso.
  ///
  /// In en, this message translates to:
  /// **'Convert to SO'**
  String get quotationsConverttoso;

  /// No description provided for @quotationsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get quotationsDelete;

  /// No description provided for @quotationsConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this quotation?'**
  String get quotationsConfirmdelete;

  /// No description provided for @quotationsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Quotation deleted successfully'**
  String get quotationsDeleted;

  /// No description provided for @quotationsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete quotation'**
  String get quotationsFailed;

  /// No description provided for @quotationsNoquotations.
  ///
  /// In en, this message translates to:
  /// **'No quotations found'**
  String get quotationsNoquotations;

  /// No description provided for @purchaseordersPurchaseorders.
  ///
  /// In en, this message translates to:
  /// **'Purchase Orders'**
  String get purchaseordersPurchaseorders;

  /// No description provided for @purchaseordersNewpurchaseorder.
  ///
  /// In en, this message translates to:
  /// **'New Purchase Order'**
  String get purchaseordersNewpurchaseorder;

  /// No description provided for @purchaseordersPrinta4.
  ///
  /// In en, this message translates to:
  /// **'Print A4'**
  String get purchaseordersPrinta4;

  /// No description provided for @purchaseordersExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get purchaseordersExportcsv;

  /// No description provided for @purchaseordersExported.
  ///
  /// In en, this message translates to:
  /// **'Purchase orders exported'**
  String get purchaseordersExported;

  /// No description provided for @purchaseordersExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export purchase orders'**
  String get purchaseordersExportfailed;

  /// No description provided for @purchaseordersPono.
  ///
  /// In en, this message translates to:
  /// **'PO No'**
  String get purchaseordersPono;

  /// No description provided for @purchaseordersExpecteddelivery.
  ///
  /// In en, this message translates to:
  /// **'Expected Delivery'**
  String get purchaseordersExpecteddelivery;

  /// No description provided for @purchaseordersDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase Order Details'**
  String get purchaseordersDetailstitle;

  /// No description provided for @purchaseordersDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this purchase order? This cannot be undone.'**
  String get purchaseordersDeleteconfirm;

  /// No description provided for @purchaseordersDeleted.
  ///
  /// In en, this message translates to:
  /// **'Purchase order deleted'**
  String get purchaseordersDeleted;

  /// No description provided for @purchaseordersNoitems.
  ///
  /// In en, this message translates to:
  /// **'No items on this order'**
  String get purchaseordersNoitems;

  /// No description provided for @purchaseordersBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get purchaseordersBalance;

  /// No description provided for @purchaseordersAdditem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get purchaseordersAdditem;

  /// No description provided for @purchaseordersEditpurchaseorder.
  ///
  /// In en, this message translates to:
  /// **'Edit Purchase Order'**
  String get purchaseordersEditpurchaseorder;

  /// No description provided for @purchaseordersErrorItemsrequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item'**
  String get purchaseordersErrorItemsrequired;

  /// No description provided for @purchaseordersErrorSupplierrequired.
  ///
  /// In en, this message translates to:
  /// **'Select a supplier'**
  String get purchaseordersErrorSupplierrequired;

  /// No description provided for @purchaseordersPodate.
  ///
  /// In en, this message translates to:
  /// **'PO Date'**
  String get purchaseordersPodate;

  /// No description provided for @purchaseordersSaved.
  ///
  /// In en, this message translates to:
  /// **'Purchase order saved'**
  String get purchaseordersSaved;

  /// No description provided for @purchaseordersSubmitconfirm.
  ///
  /// In en, this message translates to:
  /// **'Submit this purchase order? It will be locked and posted to the supplier ledger.'**
  String get purchaseordersSubmitconfirm;

  /// No description provided for @purchaseordersSubmittedsuccess.
  ///
  /// In en, this message translates to:
  /// **'Purchase order submitted'**
  String get purchaseordersSubmittedsuccess;

  /// No description provided for @purchaseordersUnitprice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get purchaseordersUnitprice;

  /// No description provided for @purchaseordersReceivegoods.
  ///
  /// In en, this message translates to:
  /// **'Receive Goods'**
  String get purchaseordersReceivegoods;

  /// No description provided for @purchaseordersReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get purchaseordersReceipts;

  /// No description provided for @purchaseordersReceiptno.
  ///
  /// In en, this message translates to:
  /// **'Receipt No'**
  String get purchaseordersReceiptno;

  /// No description provided for @purchaseordersReceiptdate.
  ///
  /// In en, this message translates to:
  /// **'Receipt Date'**
  String get purchaseordersReceiptdate;

  /// No description provided for @purchaseordersOrdered.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get purchaseordersOrdered;

  /// No description provided for @purchaseordersQtyreceived.
  ///
  /// In en, this message translates to:
  /// **'Qty Received'**
  String get purchaseordersQtyreceived;

  /// No description provided for @purchaseordersPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get purchaseordersPending;

  /// No description provided for @purchaseordersNoreceipts.
  ///
  /// In en, this message translates to:
  /// **'No receipts recorded yet'**
  String get purchaseordersNoreceipts;

  /// No description provided for @purchaseordersReceiptsaved.
  ///
  /// In en, this message translates to:
  /// **'Goods receipt recorded'**
  String get purchaseordersReceiptsaved;

  /// No description provided for @purchaseordersErrorWarehouserequired.
  ///
  /// In en, this message translates to:
  /// **'Select a warehouse'**
  String get purchaseordersErrorWarehouserequired;

  /// No description provided for @purchaseordersErrorReceiveditemsrequired.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one received quantity'**
  String get purchaseordersErrorReceiveditemsrequired;

  /// No description provided for @purchaseordersErrorQtyexceeds.
  ///
  /// In en, this message translates to:
  /// **'Received quantity cannot exceed the pending quantity'**
  String get purchaseordersErrorQtyexceeds;

  /// No description provided for @salesordersSalesorders.
  ///
  /// In en, this message translates to:
  /// **'Sales Orders'**
  String get salesordersSalesorders;

  /// No description provided for @salesordersNewsalesorder.
  ///
  /// In en, this message translates to:
  /// **'New Sales Order'**
  String get salesordersNewsalesorder;

  /// No description provided for @salesordersPrinta4.
  ///
  /// In en, this message translates to:
  /// **'Print A4'**
  String get salesordersPrinta4;

  /// No description provided for @salesordersSono.
  ///
  /// In en, this message translates to:
  /// **'SO #'**
  String get salesordersSono;

  /// No description provided for @salesordersCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get salesordersCustomer;

  /// No description provided for @salesordersAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get salesordersAmount;

  /// No description provided for @salesordersDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get salesordersDate;

  /// No description provided for @salesordersDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get salesordersDelivered;

  /// No description provided for @salesordersDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get salesordersDelivery;

  /// No description provided for @salesordersStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get salesordersStatus;

  /// No description provided for @salesordersActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get salesordersActions;

  /// No description provided for @salesordersDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get salesordersDraft;

  /// No description provided for @salesordersConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get salesordersConfirmed;

  /// No description provided for @salesordersInvoiced.
  ///
  /// In en, this message translates to:
  /// **'Invoiced'**
  String get salesordersInvoiced;

  /// No description provided for @salesordersCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get salesordersCompleted;

  /// No description provided for @salesordersCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get salesordersCancelled;

  /// No description provided for @salesordersViewdetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get salesordersViewdetails;

  /// No description provided for @salesordersEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get salesordersEdit;

  /// No description provided for @salesordersExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get salesordersExportcsv;

  /// No description provided for @salesordersExported.
  ///
  /// In en, this message translates to:
  /// **'Sales orders exported'**
  String get salesordersExported;

  /// No description provided for @salesordersExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export sales orders'**
  String get salesordersExportfailed;

  /// No description provided for @salesordersConverttoinvoice.
  ///
  /// In en, this message translates to:
  /// **'Convert to Invoice'**
  String get salesordersConverttoinvoice;

  /// No description provided for @salesordersDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get salesordersDelete;

  /// No description provided for @salesordersConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this sales order?'**
  String get salesordersConfirmdelete;

  /// No description provided for @salesordersDeleted.
  ///
  /// In en, this message translates to:
  /// **'Sales order deleted successfully'**
  String get salesordersDeleted;

  /// No description provided for @salesordersFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete sales order'**
  String get salesordersFailed;

  /// No description provided for @salesordersAdditem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get salesordersAdditem;

  /// No description provided for @salesordersBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get salesordersBalance;

  /// No description provided for @salesordersCancelconfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this sales order? Invoiced orders will have their linked invoice cancelled and stock reversed.'**
  String get salesordersCancelconfirm;

  /// No description provided for @salesordersCancelledmsg.
  ///
  /// In en, this message translates to:
  /// **'Sales order cancelled'**
  String get salesordersCancelledmsg;

  /// No description provided for @salesordersDeliverydate.
  ///
  /// In en, this message translates to:
  /// **'Delivery Date'**
  String get salesordersDeliverydate;

  /// No description provided for @salesordersDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Sales Order Details'**
  String get salesordersDetailstitle;

  /// No description provided for @salesordersEditsalesorder.
  ///
  /// In en, this message translates to:
  /// **'Edit Sales Order'**
  String get salesordersEditsalesorder;

  /// No description provided for @salesordersErrorCustomerrequired.
  ///
  /// In en, this message translates to:
  /// **'Select a customer'**
  String get salesordersErrorCustomerrequired;

  /// No description provided for @salesordersErrorDate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get salesordersErrorDate;

  /// No description provided for @salesordersErrorItemsrequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item'**
  String get salesordersErrorItemsrequired;

  /// No description provided for @salesordersItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get salesordersItem;

  /// No description provided for @salesordersNoitems.
  ///
  /// In en, this message translates to:
  /// **'No items on this order'**
  String get salesordersNoitems;

  /// No description provided for @salesordersQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get salesordersQuantity;

  /// No description provided for @salesordersSaved.
  ///
  /// In en, this message translates to:
  /// **'Sales order saved'**
  String get salesordersSaved;

  /// No description provided for @salesordersSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search sales orders...'**
  String get salesordersSearchplaceholder;

  /// No description provided for @salesordersSodate.
  ///
  /// In en, this message translates to:
  /// **'SO Date'**
  String get salesordersSodate;

  /// No description provided for @salesordersUnitprice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get salesordersUnitprice;

  /// No description provided for @productionProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get productionProduction;

  /// No description provided for @productionNewproduction.
  ///
  /// In en, this message translates to:
  /// **'New Production'**
  String get productionNewproduction;

  /// No description provided for @warehousesWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Warehouses'**
  String get warehousesWarehouses;

  /// No description provided for @warehousesNewwarehouse.
  ///
  /// In en, this message translates to:
  /// **'New Warehouse'**
  String get warehousesNewwarehouse;

  /// No description provided for @stockmovementsStockmovements.
  ///
  /// In en, this message translates to:
  /// **'Stock Movements'**
  String get stockmovementsStockmovements;

  /// No description provided for @stockmovementsNewmovement.
  ///
  /// In en, this message translates to:
  /// **'New Movement'**
  String get stockmovementsNewmovement;

  /// No description provided for @stockmovementsTotalmovements.
  ///
  /// In en, this message translates to:
  /// **'Total Movements'**
  String get stockmovementsTotalmovements;

  /// No description provided for @stockmovementsTotalquantity.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity'**
  String get stockmovementsTotalquantity;

  /// No description provided for @stockmovementsMostactivetype.
  ///
  /// In en, this message translates to:
  /// **'Most Active Type'**
  String get stockmovementsMostactivetype;

  /// No description provided for @stockmovementsProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get stockmovementsProduction;

  /// No description provided for @stockmovementsTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get stockmovementsTransfers;

  /// No description provided for @stockmovementsAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get stockmovementsAdjustments;

  /// No description provided for @stockmovementsStockadditions.
  ///
  /// In en, this message translates to:
  /// **'Stock additions'**
  String get stockmovementsStockadditions;

  /// No description provided for @stockmovementsStockreductions.
  ///
  /// In en, this message translates to:
  /// **'Stock reductions'**
  String get stockmovementsStockreductions;

  /// No description provided for @stockmovementsAggregatemoved.
  ///
  /// In en, this message translates to:
  /// **'Aggregate moved'**
  String get stockmovementsAggregatemoved;

  /// No description provided for @stockmovementsNomovements.
  ///
  /// In en, this message translates to:
  /// **'No movements'**
  String get stockmovementsNomovements;

  /// No description provided for @stockmovementsCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get stockmovementsCount;

  /// No description provided for @stockmovementsStockin.
  ///
  /// In en, this message translates to:
  /// **'Stock in'**
  String get stockmovementsStockin;

  /// No description provided for @stockmovementsStockout.
  ///
  /// In en, this message translates to:
  /// **'Stock out'**
  String get stockmovementsStockout;

  /// No description provided for @stockmovementsCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get stockmovementsCreated;

  /// No description provided for @stockmovementsMovedbetween.
  ///
  /// In en, this message translates to:
  /// **'Moved between warehouses'**
  String get stockmovementsMovedbetween;

  /// No description provided for @stockmovementsManualchanges.
  ///
  /// In en, this message translates to:
  /// **'Manual changes'**
  String get stockmovementsManualchanges;

  /// No description provided for @stockmovementsExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get stockmovementsExportcsv;

  /// No description provided for @stockmovementsMovementreport.
  ///
  /// In en, this message translates to:
  /// **'Movement Report'**
  String get stockmovementsMovementreport;

  /// No description provided for @stockmovementsStockvaluation.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation'**
  String get stockmovementsStockvaluation;

  /// No description provided for @stockmovementsStockbywarehouse.
  ///
  /// In en, this message translates to:
  /// **'Stock by Warehouse'**
  String get stockmovementsStockbywarehouse;

  /// No description provided for @stockmovementsTracktransactions.
  ///
  /// In en, this message translates to:
  /// **'Track all stock transactions'**
  String get stockmovementsTracktransactions;

  /// No description provided for @stockmovementsNewadjustment.
  ///
  /// In en, this message translates to:
  /// **'New Adjustment'**
  String get stockmovementsNewadjustment;

  /// No description provided for @stockmovementsAdjustmentinvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity'**
  String get stockmovementsAdjustmentinvalid;

  /// No description provided for @stockmovementsAdjustmentmsg.
  ///
  /// In en, this message translates to:
  /// **'Stock adjustment recorded'**
  String get stockmovementsAdjustmentmsg;

  /// No description provided for @stockmovementsAdjustmentreason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get stockmovementsAdjustmentreason;

  /// No description provided for @stockmovementsAdjustmentsave.
  ///
  /// In en, this message translates to:
  /// **'Record Adjustment'**
  String get stockmovementsAdjustmentsave;

  /// No description provided for @stockmovementsAdjustmentzero.
  ///
  /// In en, this message translates to:
  /// **'Quantity cannot be zero'**
  String get stockmovementsAdjustmentzero;

  /// No description provided for @stockmovementsAdjustmentsubtitle.
  ///
  /// In en, this message translates to:
  /// **'Item, Warehouse, Quantity — negative quantity adjusts stock down.'**
  String get stockmovementsAdjustmentsubtitle;

  /// No description provided for @stockmovementsAdjustmenthint.
  ///
  /// In en, this message translates to:
  /// **'e.g. -10 or 10'**
  String get stockmovementsAdjustmenthint;

  /// No description provided for @stockmovementsNewtransfer.
  ///
  /// In en, this message translates to:
  /// **'New Transfer'**
  String get stockmovementsNewtransfer;

  /// No description provided for @stockmovementsTransfersubtitle.
  ///
  /// In en, this message translates to:
  /// **'Creates an outgoing movement from the source warehouse and an incoming movement to the destination.'**
  String get stockmovementsTransfersubtitle;

  /// No description provided for @stockmovementsTransferfrom.
  ///
  /// In en, this message translates to:
  /// **'From Warehouse'**
  String get stockmovementsTransferfrom;

  /// No description provided for @stockmovementsTransferto.
  ///
  /// In en, this message translates to:
  /// **'To Warehouse'**
  String get stockmovementsTransferto;

  /// No description provided for @stockmovementsTransfersave.
  ///
  /// In en, this message translates to:
  /// **'Transfer Stock'**
  String get stockmovementsTransfersave;

  /// No description provided for @stockmovementsTransfermsg.
  ///
  /// In en, this message translates to:
  /// **'Stock transferred'**
  String get stockmovementsTransfermsg;

  /// No description provided for @stockmovementsTransferdiff.
  ///
  /// In en, this message translates to:
  /// **'Source and destination must be different'**
  String get stockmovementsTransferdiff;

  /// No description provided for @stockmovementsTransferpositive.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be positive'**
  String get stockmovementsTransferpositive;

  /// No description provided for @stockmovementsTransferpartialfail.
  ///
  /// In en, this message translates to:
  /// **'Transfer incomplete: the outgoing movement was recorded, but the incoming leg failed:'**
  String get stockmovementsTransferpartialfail;

  /// No description provided for @stockmovementsReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse Adjustment'**
  String get stockmovementsReverse;

  /// No description provided for @stockmovementsReverseconfirm.
  ///
  /// In en, this message translates to:
  /// **'Post a compensating movement for this adjustment? Stock will be adjusted back by the same quantity.'**
  String get stockmovementsReverseconfirm;

  /// No description provided for @stockmovementsReversemsg.
  ///
  /// In en, this message translates to:
  /// **'Adjustment reversed'**
  String get stockmovementsReversemsg;

  /// No description provided for @stockmovementsFilterall.
  ///
  /// In en, this message translates to:
  /// **'All Movements'**
  String get stockmovementsFilterall;

  /// No description provided for @stockmovementsFilterpurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get stockmovementsFilterpurchase;

  /// No description provided for @stockmovementsFiltersale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get stockmovementsFiltersale;

  /// No description provided for @stockmovementsFiltertransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get stockmovementsFiltertransfer;

  /// No description provided for @stockmovementsFilterproduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get stockmovementsFilterproduction;

  /// No description provided for @stockmovementsFilteradjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get stockmovementsFilteradjustment;

  /// No description provided for @stockmovementsLinkedmovement.
  ///
  /// In en, this message translates to:
  /// **'Linked Movement'**
  String get stockmovementsLinkedmovement;

  /// No description provided for @stockmovementsAlltransactions.
  ///
  /// In en, this message translates to:
  /// **'All transactions'**
  String get stockmovementsAlltransactions;

  /// No description provided for @stockmovementsSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search movements...'**
  String get stockmovementsSearchplaceholder;

  /// No description provided for @stockbywarehouseViewbywarehouse.
  ///
  /// In en, this message translates to:
  /// **'View current stock levels for each item by warehouse'**
  String get stockbywarehouseViewbywarehouse;

  /// No description provided for @stockbywarehouseTotalitems.
  ///
  /// In en, this message translates to:
  /// **'Total Items'**
  String get stockbywarehouseTotalitems;

  /// No description provided for @stockbywarehouseItemswithstock.
  ///
  /// In en, this message translates to:
  /// **'Items with stock'**
  String get stockbywarehouseItemswithstock;

  /// No description provided for @stockbywarehouseAggregateqty.
  ///
  /// In en, this message translates to:
  /// **'Aggregate quantity'**
  String get stockbywarehouseAggregateqty;

  /// No description provided for @stockbywarehouseActivelocations.
  ///
  /// In en, this message translates to:
  /// **'Active locations'**
  String get stockbywarehouseActivelocations;

  /// No description provided for @stockbywarehouseLargeststock.
  ///
  /// In en, this message translates to:
  /// **'Largest Stock'**
  String get stockbywarehouseLargeststock;

  /// No description provided for @stockbywarehouseMultiwarehouseitems.
  ///
  /// In en, this message translates to:
  /// **'Multi-Warehouse Items'**
  String get stockbywarehouseMultiwarehouseitems;

  /// No description provided for @stockbywarehouseMultiplelocations.
  ///
  /// In en, this message translates to:
  /// **'In multiple locations'**
  String get stockbywarehouseMultiplelocations;

  /// No description provided for @stockbywarehouseAverageqty.
  ///
  /// In en, this message translates to:
  /// **'Average Qty'**
  String get stockbywarehouseAverageqty;

  /// No description provided for @stockbywarehousePerstockline.
  ///
  /// In en, this message translates to:
  /// **'Per stock line'**
  String get stockbywarehousePerstockline;

  /// No description provided for @stockbywarehouseExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get stockbywarehouseExportcsv;

  /// No description provided for @stockbywarehouseAllwarehouses.
  ///
  /// In en, this message translates to:
  /// **'All Warehouses'**
  String get stockbywarehouseAllwarehouses;

  /// No description provided for @stockbywarehouseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get stockbywarehouseQuantity;

  /// No description provided for @stockbywarehouseAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get stockbywarehouseAll;

  /// No description provided for @stockbywarehouseStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stockbywarehouseStock;

  /// No description provided for @stockbywarehouseZero.
  ///
  /// In en, this message translates to:
  /// **'Zero'**
  String get stockbywarehouseZero;

  /// No description provided for @forecastsForecasts.
  ///
  /// In en, this message translates to:
  /// **'Forecasts'**
  String get forecastsForecasts;

  /// No description provided for @forecastsDashboard.
  ///
  /// In en, this message translates to:
  /// **'Demand Forecast'**
  String get forecastsDashboard;

  /// No description provided for @forecastsDemandtitle.
  ///
  /// In en, this message translates to:
  /// **'Demand Forecast'**
  String get forecastsDemandtitle;

  /// No description provided for @forecastsForecasttrends.
  ///
  /// In en, this message translates to:
  /// **'Forecast Trends'**
  String get forecastsForecasttrends;

  /// No description provided for @forecastsTrackeditems.
  ///
  /// In en, this message translates to:
  /// **'Tracked Items'**
  String get forecastsTrackeditems;

  /// No description provided for @forecastsNeedrestock.
  ///
  /// In en, this message translates to:
  /// **'Need Restock'**
  String get forecastsNeedrestock;

  /// No description provided for @forecastsAvgconfidence.
  ///
  /// In en, this message translates to:
  /// **'Avg Confidence'**
  String get forecastsAvgconfidence;

  /// No description provided for @forecastsCriticalalerts.
  ///
  /// In en, this message translates to:
  /// **'Critical Alerts'**
  String get forecastsCriticalalerts;

  /// No description provided for @forecastsAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get forecastsAlerts;

  /// No description provided for @forecastsViewall.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get forecastsViewall;

  /// No description provided for @forecastsNoalerts.
  ///
  /// In en, this message translates to:
  /// **'No alerts — all items adequately stocked'**
  String get forecastsNoalerts;

  /// No description provided for @forecastsTopgrowing.
  ///
  /// In en, this message translates to:
  /// **'Top Growing Items'**
  String get forecastsTopgrowing;

  /// No description provided for @forecastsViewtrends.
  ///
  /// In en, this message translates to:
  /// **'View Trends'**
  String get forecastsViewtrends;

  /// No description provided for @forecastsNotrenddata.
  ///
  /// In en, this message translates to:
  /// **'No trending data available'**
  String get forecastsNotrenddata;

  /// No description provided for @forecastsLoaderror.
  ///
  /// In en, this message translates to:
  /// **'Failed to load forecast data'**
  String get forecastsLoaderror;

  /// No description provided for @forecastsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get forecastsRetry;

  /// No description provided for @forecastsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get forecastsRefresh;

  /// No description provided for @forecastsRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing...'**
  String get forecastsRefreshing;

  /// No description provided for @forecastsCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get forecastsCategory;

  /// No description provided for @forecastsTrendlabel.
  ///
  /// In en, this message translates to:
  /// **'Trend'**
  String get forecastsTrendlabel;

  /// No description provided for @forecastsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get forecastsStatus;

  /// No description provided for @forecastsAllcategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get forecastsAllcategories;

  /// No description provided for @forecastsAlltrends.
  ///
  /// In en, this message translates to:
  /// **'All Trends'**
  String get forecastsAlltrends;

  /// No description provided for @forecastsAllstatus.
  ///
  /// In en, this message translates to:
  /// **'All Status'**
  String get forecastsAllstatus;

  /// No description provided for @forecastsNoforecasts.
  ///
  /// In en, this message translates to:
  /// **'No forecast data available'**
  String get forecastsNoforecasts;

  /// No description provided for @forecastsMonthlytrend.
  ///
  /// In en, this message translates to:
  /// **'Monthly Sales & Forecast'**
  String get forecastsMonthlytrend;

  /// No description provided for @forecastsActualsales.
  ///
  /// In en, this message translates to:
  /// **'Actual Sales'**
  String get forecastsActualsales;

  /// No description provided for @forecastsTrendline.
  ///
  /// In en, this message translates to:
  /// **'3-Month Trend'**
  String get forecastsTrendline;

  /// No description provided for @forecastsForecast.
  ///
  /// In en, this message translates to:
  /// **'Forecast'**
  String get forecastsForecast;

  /// No description provided for @forecastsTopitemsbyvolume.
  ///
  /// In en, this message translates to:
  /// **'Top Items by Volume'**
  String get forecastsTopitemsbyvolume;

  /// No description provided for @forecastsTotalsold.
  ///
  /// In en, this message translates to:
  /// **'Total Sold'**
  String get forecastsTotalsold;

  /// No description provided for @forecastsTotalsold12mo.
  ///
  /// In en, this message translates to:
  /// **'Total Sold (12mo)'**
  String get forecastsTotalsold12mo;

  /// No description provided for @forecastsItembreakdown.
  ///
  /// In en, this message translates to:
  /// **'Item Breakdown'**
  String get forecastsItembreakdown;

  /// No description provided for @forecastsSelectitem.
  ///
  /// In en, this message translates to:
  /// **'Select Item (or all)'**
  String get forecastsSelectitem;

  /// No description provided for @forecastsGrowing.
  ///
  /// In en, this message translates to:
  /// **'Growing'**
  String get forecastsGrowing;

  /// No description provided for @forecastsDeclining.
  ///
  /// In en, this message translates to:
  /// **'Declining'**
  String get forecastsDeclining;

  /// No description provided for @forecastsStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get forecastsStable;

  /// No description provided for @forecastsAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Forecast Accuracy'**
  String get forecastsAccuracy;

  /// No description provided for @forecastsAccuracytitle.
  ///
  /// In en, this message translates to:
  /// **'Forecast Accuracy'**
  String get forecastsAccuracytitle;

  /// No description provided for @forecastsAvgmape.
  ///
  /// In en, this message translates to:
  /// **'Avg MAPE'**
  String get forecastsAvgmape;

  /// No description provided for @forecastsAvgmae.
  ///
  /// In en, this message translates to:
  /// **'Avg MAE'**
  String get forecastsAvgmae;

  /// No description provided for @forecastsItemswithaccuracy.
  ///
  /// In en, this message translates to:
  /// **'Items Tracked'**
  String get forecastsItemswithaccuracy;

  /// No description provided for @forecastsBestmodel.
  ///
  /// In en, this message translates to:
  /// **'Best Model'**
  String get forecastsBestmodel;

  /// No description provided for @forecastsComputeaccuracy.
  ///
  /// In en, this message translates to:
  /// **'Compute Accuracy'**
  String get forecastsComputeaccuracy;

  /// No description provided for @forecastsComputing.
  ///
  /// In en, this message translates to:
  /// **'Computing...'**
  String get forecastsComputing;

  /// No description provided for @forecastsAccuracysubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compare predicted vs actual demand to evaluate forecast quality'**
  String get forecastsAccuracysubtitle;

  /// No description provided for @forecastsNoaccuracydata.
  ///
  /// In en, this message translates to:
  /// **'No accuracy data. Click \'Compute Accuracy\' to backfill past predictions.'**
  String get forecastsNoaccuracydata;

  /// No description provided for @forecastsAccuracycomputed.
  ///
  /// In en, this message translates to:
  /// **'Accuracy computed for {count} records'**
  String forecastsAccuracycomputed(Object count);

  /// No description provided for @forecastsMapelabel.
  ///
  /// In en, this message translates to:
  /// **'MAPE'**
  String get forecastsMapelabel;

  /// No description provided for @forecastsMaelabel.
  ///
  /// In en, this message translates to:
  /// **'MAE'**
  String get forecastsMaelabel;

  /// No description provided for @forecastsSmapelabel.
  ///
  /// In en, this message translates to:
  /// **'sMAPE'**
  String get forecastsSmapelabel;

  /// No description provided for @forecastsSamples.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get forecastsSamples;

  /// No description provided for @forecastsAccuracytrend.
  ///
  /// In en, this message translates to:
  /// **'Accuracy Trend'**
  String get forecastsAccuracytrend;

  /// No description provided for @forecastsAccuracytrenddesc.
  ///
  /// In en, this message translates to:
  /// **'MAPE over time for selected item'**
  String get forecastsAccuracytrenddesc;

  /// No description provided for @forecastsSelectitemforchart.
  ///
  /// In en, this message translates to:
  /// **'Select an item from the table to see its accuracy trend'**
  String get forecastsSelectitemforchart;

  /// No description provided for @forecastsAccuracyvsactual.
  ///
  /// In en, this message translates to:
  /// **'Predicted vs Actual'**
  String get forecastsAccuracyvsactual;

  /// No description provided for @forecastsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get forecastsModel;

  /// No description provided for @forecastsSortbymape.
  ///
  /// In en, this message translates to:
  /// **'Best (lowest MAPE) first'**
  String get forecastsSortbymape;

  /// No description provided for @forecastsPredictedweek.
  ///
  /// In en, this message translates to:
  /// **'Predicted (Week)'**
  String get forecastsPredictedweek;

  /// No description provided for @forecastsPredictedmonth.
  ///
  /// In en, this message translates to:
  /// **'Predicted (Month)'**
  String get forecastsPredictedmonth;

  /// No description provided for @forecastsPredictedquarter.
  ///
  /// In en, this message translates to:
  /// **'Predicted (Quarter)'**
  String get forecastsPredictedquarter;

  /// No description provided for @forecastsRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommendation'**
  String get forecastsRecommendation;

  /// No description provided for @forecastsOrdernow.
  ///
  /// In en, this message translates to:
  /// **'Order Now'**
  String get forecastsOrdernow;

  /// No description provided for @forecastsOrdersoon.
  ///
  /// In en, this message translates to:
  /// **'Order Soon'**
  String get forecastsOrdersoon;

  /// No description provided for @forecastsMonitor.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get forecastsMonitor;

  /// No description provided for @forecastsAdequate.
  ///
  /// In en, this message translates to:
  /// **'Adequate'**
  String get forecastsAdequate;

  /// No description provided for @forecastsConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get forecastsConfidence;

  /// No description provided for @forecastsPending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get forecastsPending;

  /// No description provided for @forecastsSearchitems.
  ///
  /// In en, this message translates to:
  /// **'Search items...'**
  String get forecastsSearchitems;

  /// No description provided for @forecastsCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get forecastsCritical;

  /// No description provided for @forecastsWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get forecastsWarning;

  /// No description provided for @forecastsOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get forecastsOk;

  /// No description provided for @bomBillofmaterials.
  ///
  /// In en, this message translates to:
  /// **'Bill of Materials (BOM)'**
  String get bomBillofmaterials;

  /// No description provided for @bomNewbom.
  ///
  /// In en, this message translates to:
  /// **'New BOM'**
  String get bomNewbom;

  /// No description provided for @settingsSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsSettings;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Company profile, currency, tax rates and document numbering.'**
  String get settingsSubtitle;

  /// No description provided for @settingsSectionCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get settingsSectionCompany;

  /// No description provided for @settingsSectionCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency & Formatting'**
  String get settingsSectionCurrency;

  /// No description provided for @settingsSectionTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get settingsSectionTax;

  /// No description provided for @settingsSectionNumbering.
  ///
  /// In en, this message translates to:
  /// **'Document Numbering'**
  String get settingsSectionNumbering;

  /// No description provided for @settingsSectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other Settings'**
  String get settingsSectionOther;

  /// No description provided for @settingsSectionDate.
  ///
  /// In en, this message translates to:
  /// **'Date & Range'**
  String get settingsSectionDate;

  /// No description provided for @settingsKeyCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get settingsKeyCompanyName;

  /// No description provided for @settingsKeyCompanyEmail.
  ///
  /// In en, this message translates to:
  /// **'Company Email'**
  String get settingsKeyCompanyEmail;

  /// No description provided for @settingsKeyCompanyPhone.
  ///
  /// In en, this message translates to:
  /// **'Company Phone'**
  String get settingsKeyCompanyPhone;

  /// No description provided for @settingsKeyCompanyAddress.
  ///
  /// In en, this message translates to:
  /// **'Company Address'**
  String get settingsKeyCompanyAddress;

  /// No description provided for @settingsKeyCompanyTaxId.
  ///
  /// In en, this message translates to:
  /// **'Company Tax ID'**
  String get settingsKeyCompanyTaxId;

  /// No description provided for @settingsKeyCurrencySymbol.
  ///
  /// In en, this message translates to:
  /// **'Currency Symbol'**
  String get settingsKeyCurrencySymbol;

  /// No description provided for @settingsKeyCurrencyCode.
  ///
  /// In en, this message translates to:
  /// **'Currency Code'**
  String get settingsKeyCurrencyCode;

  /// No description provided for @settingsKeyCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsKeyCurrency;

  /// No description provided for @settingsKeyDecimalPlaces.
  ///
  /// In en, this message translates to:
  /// **'Decimal Places'**
  String get settingsKeyDecimalPlaces;

  /// No description provided for @settingsKeyDateFormat.
  ///
  /// In en, this message translates to:
  /// **'Date Format'**
  String get settingsKeyDateFormat;

  /// No description provided for @settingsKeyTooltipTimeout.
  ///
  /// In en, this message translates to:
  /// **'Tooltip Timeout (s)'**
  String get settingsKeyTooltipTimeout;

  /// No description provided for @settingsKeyTaxRate.
  ///
  /// In en, this message translates to:
  /// **'Default Tax Rate (%)'**
  String get settingsKeyTaxRate;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save settings'**
  String get settingsSaveFailed;

  /// No description provided for @settingsUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get settingsUnsaved;

  /// No description provided for @settingsNumberingHelper.
  ///
  /// In en, this message translates to:
  /// **'Server-managed document counter — edit with care.'**
  String get settingsNumberingHelper;

  /// No description provided for @settingsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No settings to display'**
  String get settingsEmpty;

  /// No description provided for @integrationsIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get integrationsIntegrations;

  /// No description provided for @integrationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure third-party services (email, SMS, weather, validation, currency, tax). API keys are stored encrypted and never displayed.'**
  String get integrationsSubtitle;

  /// No description provided for @integrationsConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get integrationsConfigured;

  /// No description provided for @integrationsNotconfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get integrationsNotconfigured;

  /// No description provided for @integrationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get integrationsEnabled;

  /// No description provided for @integrationsSaved.
  ///
  /// In en, this message translates to:
  /// **'Integration settings saved'**
  String get integrationsSaved;

  /// No description provided for @integrationsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save integration settings'**
  String get integrationsSaveFailed;

  /// No description provided for @integrationsApikey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get integrationsApikey;

  /// No description provided for @integrationsApikeyHelper.
  ///
  /// In en, this message translates to:
  /// **'Stored encrypted — leave blank to keep the current key.'**
  String get integrationsApikeyHelper;

  /// No description provided for @integrationsFieldFromemail.
  ///
  /// In en, this message translates to:
  /// **'From Email'**
  String get integrationsFieldFromemail;

  /// No description provided for @integrationsFieldFromname.
  ///
  /// In en, this message translates to:
  /// **'From Name'**
  String get integrationsFieldFromname;

  /// No description provided for @integrationsFieldAccountsid.
  ///
  /// In en, this message translates to:
  /// **'Account SID'**
  String get integrationsFieldAccountsid;

  /// No description provided for @integrationsFieldPhonenumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get integrationsFieldPhonenumber;

  /// No description provided for @integrationsFieldDefaultlocation.
  ///
  /// In en, this message translates to:
  /// **'Default Location'**
  String get integrationsFieldDefaultlocation;

  /// No description provided for @integrationsFieldBase.
  ///
  /// In en, this message translates to:
  /// **'Base Currency'**
  String get integrationsFieldBase;

  /// No description provided for @integrationsFieldUpdateinterval.
  ///
  /// In en, this message translates to:
  /// **'Update Interval (s)'**
  String get integrationsFieldUpdateinterval;

  /// No description provided for @integrationsFieldDefaultcountry.
  ///
  /// In en, this message translates to:
  /// **'Default Country'**
  String get integrationsFieldDefaultcountry;

  /// No description provided for @integrationsFieldZipcode.
  ///
  /// In en, this message translates to:
  /// **'ZIP Code'**
  String get integrationsFieldZipcode;

  /// No description provided for @integrationsServiceEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (SendGrid)'**
  String get integrationsServiceEmail;

  /// No description provided for @integrationsServiceNotifications.
  ///
  /// In en, this message translates to:
  /// **'SMS Notifications (Twilio)'**
  String get integrationsServiceNotifications;

  /// No description provided for @integrationsServiceWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather (Weatherstack)'**
  String get integrationsServiceWeather;

  /// No description provided for @integrationsServiceValidation.
  ///
  /// In en, this message translates to:
  /// **'Phone Validation (Numverify)'**
  String get integrationsServiceValidation;

  /// No description provided for @integrationsServiceCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency Exchange (Fixer)'**
  String get integrationsServiceCurrency;

  /// No description provided for @integrationsServiceTax.
  ///
  /// In en, this message translates to:
  /// **'Tax Calculation (TaxJar)'**
  String get integrationsServiceTax;

  /// No description provided for @usermanagementUsermanagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get usermanagementUsermanagement;

  /// No description provided for @usermanagementRolespermissions.
  ///
  /// In en, this message translates to:
  /// **'Roles & Permissions'**
  String get usermanagementRolespermissions;

  /// No description provided for @usermanagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create and manage system users, roles and permissions'**
  String get usermanagementSubtitle;

  /// No description provided for @usermanagementUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usermanagementUsers;

  /// No description provided for @usermanagementAllroles.
  ///
  /// In en, this message translates to:
  /// **'All Roles'**
  String get usermanagementAllroles;

  /// No description provided for @usermanagementAllstatus.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get usermanagementAllstatus;

  /// No description provided for @usermanagementSearchusers.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get usermanagementSearchusers;

  /// No description provided for @usermanagementNewuser.
  ///
  /// In en, this message translates to:
  /// **'New User'**
  String get usermanagementNewuser;

  /// No description provided for @usermanagementEdituser.
  ///
  /// In en, this message translates to:
  /// **'Edit User'**
  String get usermanagementEdituser;

  /// No description provided for @usermanagementUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usermanagementUsername;

  /// No description provided for @usermanagementEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get usermanagementEmail;

  /// No description provided for @usermanagementFullname.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get usermanagementFullname;

  /// No description provided for @usermanagementRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get usermanagementRole;

  /// No description provided for @usermanagementPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get usermanagementPassword;

  /// No description provided for @usermanagementUsercreated.
  ///
  /// In en, this message translates to:
  /// **'User created successfully'**
  String get usermanagementUsercreated;

  /// No description provided for @usermanagementUserupdated.
  ///
  /// In en, this message translates to:
  /// **'User updated successfully'**
  String get usermanagementUserupdated;

  /// No description provided for @usermanagementUserdeleted.
  ///
  /// In en, this message translates to:
  /// **'User deleted successfully'**
  String get usermanagementUserdeleted;

  /// No description provided for @usermanagementDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this user? This cannot be undone.'**
  String get usermanagementDeleteconfirm;

  /// No description provided for @usermanagementActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get usermanagementActivate;

  /// No description provided for @usermanagementDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get usermanagementDeactivate;

  /// No description provided for @usermanagementActivated.
  ///
  /// In en, this message translates to:
  /// **'User activated'**
  String get usermanagementActivated;

  /// No description provided for @usermanagementDeactivated.
  ///
  /// In en, this message translates to:
  /// **'User deactivated'**
  String get usermanagementDeactivated;

  /// No description provided for @usermanagementResetpassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get usermanagementResetpassword;

  /// No description provided for @usermanagementNewpassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get usermanagementNewpassword;

  /// No description provided for @usermanagementResetconfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset this user\'s password?'**
  String get usermanagementResetconfirm;

  /// No description provided for @usermanagementResetdone.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully'**
  String get usermanagementResetdone;

  /// No description provided for @usermanagementValidationUsernamerequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get usermanagementValidationUsernamerequired;

  /// No description provided for @usermanagementValidationEmailrequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get usermanagementValidationEmailrequired;

  /// No description provided for @usermanagementValidationInvalidemail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get usermanagementValidationInvalidemail;

  /// No description provided for @usermanagementValidationFullnamerequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get usermanagementValidationFullnamerequired;

  /// No description provided for @usermanagementValidationRolerequired.
  ///
  /// In en, this message translates to:
  /// **'Select a role'**
  String get usermanagementValidationRolerequired;

  /// No description provided for @usermanagementValidationPasswordlength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get usermanagementValidationPasswordlength;

  /// No description provided for @usermanagementNewrole.
  ///
  /// In en, this message translates to:
  /// **'New Role'**
  String get usermanagementNewrole;

  /// No description provided for @usermanagementEditrole.
  ///
  /// In en, this message translates to:
  /// **'Edit Role'**
  String get usermanagementEditrole;

  /// No description provided for @usermanagementRolename.
  ///
  /// In en, this message translates to:
  /// **'Role Name'**
  String get usermanagementRolename;

  /// No description provided for @usermanagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get usermanagementDescription;

  /// No description provided for @usermanagementSystemrole.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get usermanagementSystemrole;

  /// No description provided for @usermanagementPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get usermanagementPermissions;

  /// No description provided for @usermanagementPermissioncount.
  ///
  /// In en, this message translates to:
  /// **'permissions'**
  String get usermanagementPermissioncount;

  /// No description provided for @usermanagementPermissionstitle.
  ///
  /// In en, this message translates to:
  /// **'Role Permissions'**
  String get usermanagementPermissionstitle;

  /// No description provided for @usermanagementPermissionsubtitle.
  ///
  /// In en, this message translates to:
  /// **'Assign permissions for {role}'**
  String usermanagementPermissionsubtitle(Object role);

  /// No description provided for @usermanagementPermissionsaved.
  ///
  /// In en, this message translates to:
  /// **'Permissions updated'**
  String get usermanagementPermissionsaved;

  /// No description provided for @usermanagementRolevalidationname.
  ///
  /// In en, this message translates to:
  /// **'Role name is required'**
  String get usermanagementRolevalidationname;

  /// No description provided for @usermanagementRolecreated.
  ///
  /// In en, this message translates to:
  /// **'Role created successfully'**
  String get usermanagementRolecreated;

  /// No description provided for @usermanagementRoleupdated.
  ///
  /// In en, this message translates to:
  /// **'Role updated successfully'**
  String get usermanagementRoleupdated;

  /// No description provided for @usermanagementRoledeleted.
  ///
  /// In en, this message translates to:
  /// **'Role deleted successfully'**
  String get usermanagementRoledeleted;

  /// No description provided for @usermanagementRoledeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this role? Users assigned to it must be reassigned first.'**
  String get usermanagementRoledeleteconfirm;

  /// No description provided for @usermanagementCantmodifysystem.
  ///
  /// In en, this message translates to:
  /// **'System roles cannot be modified'**
  String get usermanagementCantmodifysystem;

  /// No description provided for @usermanagementNoresults.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get usermanagementNoresults;

  /// No description provided for @expensesExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesExpenses;

  /// No description provided for @expensesNewexpense.
  ///
  /// In en, this message translates to:
  /// **'New Expense'**
  String get expensesNewexpense;

  /// No description provided for @expensesDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get expensesDescription;

  /// No description provided for @expensesAllcategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get expensesAllcategories;

  /// No description provided for @expensesAllstatuses.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get expensesAllstatuses;

  /// No description provided for @expensesCount.
  ///
  /// In en, this message translates to:
  /// **'expenses'**
  String get expensesCount;

  /// No description provided for @expensesCreatedby.
  ///
  /// In en, this message translates to:
  /// **'Created By'**
  String get expensesCreatedby;

  /// No description provided for @expensesDeleteconfirmdesc.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove the expense record.'**
  String get expensesDeleteconfirmdesc;

  /// No description provided for @expensesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Expense deleted'**
  String get expensesDeleted;

  /// No description provided for @expensesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Expense'**
  String get expensesEdit;

  /// No description provided for @expensesErrorAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get expensesErrorAmountInvalid;

  /// No description provided for @expensesErrorAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get expensesErrorAmountRequired;

  /// No description provided for @expensesErrorCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Category is required'**
  String get expensesErrorCategoryRequired;

  /// No description provided for @expensesExpensedate.
  ///
  /// In en, this message translates to:
  /// **'Expense Date'**
  String get expensesExpensedate;

  /// No description provided for @expensesExpenseno.
  ///
  /// In en, this message translates to:
  /// **'Expense No'**
  String get expensesExpenseno;

  /// No description provided for @expensesExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get expensesExportcsv;

  /// No description provided for @expensesExported.
  ///
  /// In en, this message translates to:
  /// **'Expenses exported'**
  String get expensesExported;

  /// No description provided for @expensesExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export expenses'**
  String get expensesExportfailed;

  /// No description provided for @expensesPaymentmethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get expensesPaymentmethod;

  /// No description provided for @expensesProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get expensesProject;

  /// No description provided for @expensesReferenceno.
  ///
  /// In en, this message translates to:
  /// **'Reference No'**
  String get expensesReferenceno;

  /// No description provided for @expensesVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get expensesVendor;

  /// No description provided for @employeesTitle.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get employeesTitle;

  /// No description provided for @employeesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage employee records and HR information'**
  String get employeesSubtitle;

  /// No description provided for @employeesAddnew.
  ///
  /// In en, this message translates to:
  /// **'Add Employee'**
  String get employeesAddnew;

  /// No description provided for @employeesEditemployee.
  ///
  /// In en, this message translates to:
  /// **'Edit Employee'**
  String get employeesEditemployee;

  /// No description provided for @employeesFieldsFirst_name.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get employeesFieldsFirst_name;

  /// No description provided for @employeesFieldsLast_name.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get employeesFieldsLast_name;

  /// No description provided for @employeesFieldsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get employeesFieldsEmail;

  /// No description provided for @employeesFieldsPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get employeesFieldsPhone;

  /// No description provided for @employeesFieldsMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get employeesFieldsMobile;

  /// No description provided for @employeesFieldsCnic_no.
  ///
  /// In en, this message translates to:
  /// **'CNIC No'**
  String get employeesFieldsCnic_no;

  /// No description provided for @employeesFieldsAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get employeesFieldsAddress;

  /// No description provided for @employeesFieldsCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get employeesFieldsCity;

  /// No description provided for @employeesFieldsState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get employeesFieldsState;

  /// No description provided for @employeesFieldsPostal_code.
  ///
  /// In en, this message translates to:
  /// **'Postal Code'**
  String get employeesFieldsPostal_code;

  /// No description provided for @employeesFieldsCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get employeesFieldsCountry;

  /// No description provided for @employeesFieldsDate_of_birth.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get employeesFieldsDate_of_birth;

  /// No description provided for @employeesFieldsGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get employeesFieldsGender;

  /// No description provided for @employeesFieldsDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get employeesFieldsDepartment;

  /// No description provided for @employeesFieldsDesignation.
  ///
  /// In en, this message translates to:
  /// **'Designation'**
  String get employeesFieldsDesignation;

  /// No description provided for @employeesFieldsEmployment_type.
  ///
  /// In en, this message translates to:
  /// **'Employment Type'**
  String get employeesFieldsEmployment_type;

  /// No description provided for @employeesFieldsDate_of_joining.
  ///
  /// In en, this message translates to:
  /// **'Date of Joining'**
  String get employeesFieldsDate_of_joining;

  /// No description provided for @employeesFieldsDate_of_leaving.
  ///
  /// In en, this message translates to:
  /// **'Date of Leaving'**
  String get employeesFieldsDate_of_leaving;

  /// No description provided for @employeesFieldsSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get employeesFieldsSalary;

  /// No description provided for @employeesFieldsBank_name.
  ///
  /// In en, this message translates to:
  /// **'Bank Name'**
  String get employeesFieldsBank_name;

  /// No description provided for @employeesFieldsBank_account_no.
  ///
  /// In en, this message translates to:
  /// **'Bank Account No'**
  String get employeesFieldsBank_account_no;

  /// No description provided for @employeesFieldsBank_iban.
  ///
  /// In en, this message translates to:
  /// **'IBAN'**
  String get employeesFieldsBank_iban;

  /// No description provided for @employeesFieldsEmergency_contact_name.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact Name'**
  String get employeesFieldsEmergency_contact_name;

  /// No description provided for @employeesFieldsEmergency_contact_phone.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contact Phone'**
  String get employeesFieldsEmergency_contact_phone;

  /// No description provided for @employeesFieldsNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get employeesFieldsNotes;

  /// No description provided for @employeesFieldsIs_active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get employeesFieldsIs_active;

  /// No description provided for @employeesValidationFirstnamerequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get employeesValidationFirstnamerequired;

  /// No description provided for @employeesValidationLastnamerequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get employeesValidationLastnamerequired;

  /// No description provided for @employeesValidationInvalidemail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get employeesValidationInvalidemail;

  /// No description provided for @employeesValidationInvalidphone.
  ///
  /// In en, this message translates to:
  /// **'Invalid phone format'**
  String get employeesValidationInvalidphone;

  /// No description provided for @employeesMessagesCreated.
  ///
  /// In en, this message translates to:
  /// **'Employee created successfully'**
  String get employeesMessagesCreated;

  /// No description provided for @employeesMessagesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Employee updated successfully'**
  String get employeesMessagesUpdated;

  /// No description provided for @employeesMessagesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Employee deleted successfully'**
  String get employeesMessagesDeleted;

  /// No description provided for @employeesDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get employeesDocumentsTitle;

  /// No description provided for @employeesDocumentsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Document'**
  String get employeesDocumentsAdd;

  /// No description provided for @employeesDocumentsName.
  ///
  /// In en, this message translates to:
  /// **'Document Name'**
  String get employeesDocumentsName;

  /// No description provided for @employeesDocumentsType.
  ///
  /// In en, this message translates to:
  /// **'Document Type'**
  String get employeesDocumentsType;

  /// No description provided for @employeesDocumentsNumber.
  ///
  /// In en, this message translates to:
  /// **'Document Number'**
  String get employeesDocumentsNumber;

  /// No description provided for @employeesDocumentsIssuedate.
  ///
  /// In en, this message translates to:
  /// **'Issue Date'**
  String get employeesDocumentsIssuedate;

  /// No description provided for @employeesDocumentsExpirydate.
  ///
  /// In en, this message translates to:
  /// **'Expiry Date'**
  String get employeesDocumentsExpirydate;

  /// No description provided for @employeesDocumentsNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get employeesDocumentsNotes;

  /// No description provided for @employeesDocumentsNodocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents on file'**
  String get employeesDocumentsNodocuments;

  /// No description provided for @employeesDocumentsNamerequired.
  ///
  /// In en, this message translates to:
  /// **'Document name is required'**
  String get employeesDocumentsNamerequired;

  /// No description provided for @employeesDocumentsCreated.
  ///
  /// In en, this message translates to:
  /// **'Document added successfully'**
  String get employeesDocumentsCreated;

  /// No description provided for @employeesDocumentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted successfully'**
  String get employeesDocumentsDeleted;

  /// No description provided for @employeesDocumentsFiletoolarge.
  ///
  /// In en, this message translates to:
  /// **'File size must be under 10MB'**
  String get employeesDocumentsFiletoolarge;

  /// No description provided for @employeesDocumentsDrophere.
  ///
  /// In en, this message translates to:
  /// **'Click or drag a file here to upload'**
  String get employeesDocumentsDrophere;

  /// No description provided for @employeesDocumentsFiletypes.
  ///
  /// In en, this message translates to:
  /// **'PDF, Images, Word, Excel, TXT — max 10MB'**
  String get employeesDocumentsFiletypes;

  /// No description provided for @employeesDocumentsUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get employeesDocumentsUploading;

  /// No description provided for @employeesDocumentsProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get employeesDocumentsProcessing;

  /// No description provided for @employeesDocumentsPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get employeesDocumentsPreview;

  /// No description provided for @employeesDocumentsPreviewnotsupported.
  ///
  /// In en, this message translates to:
  /// **'Preview not available for this file type'**
  String get employeesDocumentsPreviewnotsupported;

  /// No description provided for @employeesDocumentsFile.
  ///
  /// In en, this message translates to:
  /// **'file'**
  String get employeesDocumentsFile;

  /// No description provided for @employeesDocumentsSelectfile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get employeesDocumentsSelectfile;

  /// No description provided for @employeesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search employees...'**
  String get employeesSearch;

  /// No description provided for @employeesAlldepartments.
  ///
  /// In en, this message translates to:
  /// **'All Departments'**
  String get employeesAlldepartments;

  /// No description provided for @employeesAllstatus.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get employeesAllstatus;

  /// No description provided for @employeesFullname.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get employeesFullname;

  /// No description provided for @employeesEmploymenttype.
  ///
  /// In en, this message translates to:
  /// **'Employment Type'**
  String get employeesEmploymenttype;

  /// No description provided for @employeesCount.
  ///
  /// In en, this message translates to:
  /// **'employees'**
  String get employeesCount;

  /// No description provided for @employeesActivecount.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get employeesActivecount;

  /// No description provided for @employeesTotalsalary.
  ///
  /// In en, this message translates to:
  /// **'Total Salary'**
  String get employeesTotalsalary;

  /// No description provided for @employeesDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this employee? This cannot be undone.'**
  String get employeesDeleteconfirm;

  /// No description provided for @employeesPaysalary.
  ///
  /// In en, this message translates to:
  /// **'Pay Salary'**
  String get employeesPaysalary;

  /// No description provided for @employeesSalaryamount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get employeesSalaryamount;

  /// No description provided for @employeesPaymentdate.
  ///
  /// In en, this message translates to:
  /// **'Payment Date'**
  String get employeesPaymentdate;

  /// No description provided for @employeesPaymentmethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get employeesPaymentmethod;

  /// No description provided for @employeesReferenceno.
  ///
  /// In en, this message translates to:
  /// **'Reference No'**
  String get employeesReferenceno;

  /// No description provided for @employeesSalarynotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get employeesSalarynotes;

  /// No description provided for @employeesSalarypaid.
  ///
  /// In en, this message translates to:
  /// **'Salary payment recorded'**
  String get employeesSalarypaid;

  /// No description provided for @employeesSalaryhistory.
  ///
  /// In en, this message translates to:
  /// **'Salary History'**
  String get employeesSalaryhistory;

  /// No description provided for @employeesNosalaryhistory.
  ///
  /// In en, this message translates to:
  /// **'No salary payments yet'**
  String get employeesNosalaryhistory;

  /// No description provided for @employeesDetailtitle.
  ///
  /// In en, this message translates to:
  /// **'Employee Details'**
  String get employeesDetailtitle;

  /// No description provided for @employeesInvalidamount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get employeesInvalidamount;

  /// No description provided for @purchasesPurchases.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get purchasesPurchases;

  /// No description provided for @purchasesNewpurchase.
  ///
  /// In en, this message translates to:
  /// **'New Purchase'**
  String get purchasesNewpurchase;

  /// No description provided for @purchasesPurchaseno.
  ///
  /// In en, this message translates to:
  /// **'Purchase No'**
  String get purchasesPurchaseno;

  /// No description provided for @purchasesSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get purchasesSupplier;

  /// No description provided for @purchasesConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get purchasesConfirmdelete;

  /// No description provided for @purchasesPurchasedeleted.
  ///
  /// In en, this message translates to:
  /// **'Purchase deleted successfully!'**
  String get purchasesPurchasedeleted;

  /// No description provided for @purchasesPurchasesaved.
  ///
  /// In en, this message translates to:
  /// **'Purchase saved successfully!'**
  String get purchasesPurchasesaved;

  /// No description provided for @purchasesNopurchases.
  ///
  /// In en, this message translates to:
  /// **'No purchases to export'**
  String get purchasesNopurchases;

  /// No description provided for @purchasesTotalvalue.
  ///
  /// In en, this message translates to:
  /// **'Total Value'**
  String get purchasesTotalvalue;

  /// No description provided for @purchasesTotalquantity.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity'**
  String get purchasesTotalquantity;

  /// No description provided for @purchasesUniquesuppliers.
  ///
  /// In en, this message translates to:
  /// **'Unique Suppliers'**
  String get purchasesUniquesuppliers;

  /// No description provided for @purchasesUniqueitems.
  ///
  /// In en, this message translates to:
  /// **'Unique Items'**
  String get purchasesUniqueitems;

  /// No description provided for @purchasesTotalpurchases.
  ///
  /// In en, this message translates to:
  /// **'Total Purchases'**
  String get purchasesTotalpurchases;

  /// No description provided for @purchasesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record direct purchases and track costs'**
  String get purchasesSubtitle;

  /// No description provided for @purchasesRecordpurchase.
  ///
  /// In en, this message translates to:
  /// **'Record Purchase'**
  String get purchasesRecordpurchase;

  /// No description provided for @purchasesTotalpurchasescard.
  ///
  /// In en, this message translates to:
  /// **'Total Purchases'**
  String get purchasesTotalpurchasescard;

  /// No description provided for @purchasesAlltransactions.
  ///
  /// In en, this message translates to:
  /// **'All transactions'**
  String get purchasesAlltransactions;

  /// No description provided for @purchasesAvailableqty.
  ///
  /// In en, this message translates to:
  /// **'Available for Return'**
  String get purchasesAvailableqty;

  /// No description provided for @purchasesTotalvaluecard.
  ///
  /// In en, this message translates to:
  /// **'Total Value'**
  String get purchasesTotalvaluecard;

  /// No description provided for @purchasesPurchasecost.
  ///
  /// In en, this message translates to:
  /// **'Purchase cost'**
  String get purchasesPurchasecost;

  /// No description provided for @purchasesTotalquantitycard.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity'**
  String get purchasesTotalquantitycard;

  /// No description provided for @purchasesAggregateitems.
  ///
  /// In en, this message translates to:
  /// **'Aggregate items'**
  String get purchasesAggregateitems;

  /// No description provided for @purchasesSupplierscard.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get purchasesSupplierscard;

  /// No description provided for @purchasesUniquevendors.
  ///
  /// In en, this message translates to:
  /// **'Unique vendors'**
  String get purchasesUniquevendors;

  /// No description provided for @purchasesItemscard.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get purchasesItemscard;

  /// No description provided for @purchasesProductspurchased.
  ///
  /// In en, this message translates to:
  /// **'Products purchased'**
  String get purchasesProductspurchased;

  /// No description provided for @purchasesAveragevalue.
  ///
  /// In en, this message translates to:
  /// **'Average Value'**
  String get purchasesAveragevalue;

  /// No description provided for @purchasesPerpurchase.
  ///
  /// In en, this message translates to:
  /// **'Per purchase'**
  String get purchasesPerpurchase;

  /// No description provided for @purchasesLargestpurchase.
  ///
  /// In en, this message translates to:
  /// **'Largest Purchase'**
  String get purchasesLargestpurchase;

  /// No description provided for @purchasesNopurchasesyet.
  ///
  /// In en, this message translates to:
  /// **'No purchases yet'**
  String get purchasesNopurchasesyet;

  /// No description provided for @purchasesRecent30days.
  ///
  /// In en, this message translates to:
  /// **'Recent (30 Days)'**
  String get purchasesRecent30days;

  /// No description provided for @purchasesLastmonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get purchasesLastmonth;

  /// No description provided for @purchasesExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get purchasesExport;

  /// No description provided for @purchasesExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get purchasesExportcsv;

  /// No description provided for @purchasesExported.
  ///
  /// In en, this message translates to:
  /// **'Purchase returns exported'**
  String get purchasesExported;

  /// No description provided for @purchasesExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export purchase returns'**
  String get purchasesExportfailed;

  /// No description provided for @purchasesSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get purchasesSummary;

  /// No description provided for @purchasesValuation.
  ///
  /// In en, this message translates to:
  /// **'Valuation'**
  String get purchasesValuation;

  /// No description provided for @purchasesMovements.
  ///
  /// In en, this message translates to:
  /// **'Movements'**
  String get purchasesMovements;

  /// No description provided for @purchasesItemsaction.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get purchasesItemsaction;

  /// No description provided for @purchasesPurchasenumber.
  ///
  /// In en, this message translates to:
  /// **'Purchase #'**
  String get purchasesPurchasenumber;

  /// No description provided for @purchasesDatecol.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get purchasesDatecol;

  /// No description provided for @purchasesDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase Details'**
  String get purchasesDetailstitle;

  /// No description provided for @purchasesItemcol.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get purchasesItemcol;

  /// No description provided for @purchasesQuantitycol.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get purchasesQuantitycol;

  /// No description provided for @purchasesUnitcost.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost'**
  String get purchasesUnitcost;

  /// No description provided for @purchasesTotalcol.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get purchasesTotalcol;

  /// No description provided for @purchasesSuppliercol.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get purchasesSuppliercol;

  /// No description provided for @purchasesWarehousecol.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get purchasesWarehousecol;

  /// No description provided for @purchasesNopurchasesfound.
  ///
  /// In en, this message translates to:
  /// **'No purchases found'**
  String get purchasesNopurchasesfound;

  /// No description provided for @purchasesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get purchasesLoading;

  /// No description provided for @purchasesRecordnewpurchase.
  ///
  /// In en, this message translates to:
  /// **'Record New Purchase'**
  String get purchasesRecordnewpurchase;

  /// No description provided for @purchasesSearchitems.
  ///
  /// In en, this message translates to:
  /// **'Search items...'**
  String get purchasesSearchitems;

  /// No description provided for @purchasesSearchwarehouses.
  ///
  /// In en, this message translates to:
  /// **'Search warehouses...'**
  String get purchasesSearchwarehouses;

  /// No description provided for @purchasesTotalcostlabel.
  ///
  /// In en, this message translates to:
  /// **'Total Cost:'**
  String get purchasesTotalcostlabel;

  /// No description provided for @purchasesPurchasedate.
  ///
  /// In en, this message translates to:
  /// **'Purchase Date'**
  String get purchasesPurchasedate;

  /// No description provided for @purchasesSuppliername.
  ///
  /// In en, this message translates to:
  /// **'Supplier Name'**
  String get purchasesSuppliername;

  /// No description provided for @purchasesSupplierplaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g., ABC Suppliers'**
  String get purchasesSupplierplaceholder;

  /// No description provided for @purchasesInvoicenumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice Number'**
  String get purchasesInvoicenumber;

  /// No description provided for @purchasesInvoiceplaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g., INV-2025-001'**
  String get purchasesInvoiceplaceholder;

  /// No description provided for @purchasesRemarks.
  ///
  /// In en, this message translates to:
  /// **'Remarks'**
  String get purchasesRemarks;

  /// No description provided for @purchasesRemarksplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Additional notes about this purchase...'**
  String get purchasesRemarksplaceholder;

  /// No description provided for @purchasesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get purchasesCancel;

  /// No description provided for @purchasesReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to Supplier'**
  String get purchasesReturn;

  /// No description provided for @purchasesReturntitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase Return'**
  String get purchasesReturntitle;

  /// No description provided for @purchasesReturnsubtitle.
  ///
  /// In en, this message translates to:
  /// **'Process a return for this purchase'**
  String get purchasesReturnsubtitle;

  /// No description provided for @purchasesReturnquantity.
  ///
  /// In en, this message translates to:
  /// **'Return Quantity'**
  String get purchasesReturnquantity;

  /// No description provided for @purchasesReturnreason.
  ///
  /// In en, this message translates to:
  /// **'Reason for Return'**
  String get purchasesReturnreason;

  /// No description provided for @purchasesReturnreasonplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter reason for return...'**
  String get purchasesReturnreasonplaceholder;

  /// No description provided for @purchasesProcessreturn.
  ///
  /// In en, this message translates to:
  /// **'Process Return'**
  String get purchasesProcessreturn;

  /// No description provided for @purchasesReturnprocessed.
  ///
  /// In en, this message translates to:
  /// **'Return processed successfully'**
  String get purchasesReturnprocessed;

  /// No description provided for @purchasesReturnfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to process return'**
  String get purchasesReturnfailed;

  /// No description provided for @purchasesReturnhistory.
  ///
  /// In en, this message translates to:
  /// **'View Returns'**
  String get purchasesReturnhistory;

  /// No description provided for @purchasesReturnno.
  ///
  /// In en, this message translates to:
  /// **'Return No'**
  String get purchasesReturnno;

  /// No description provided for @purchasesReturnnoitems.
  ///
  /// In en, this message translates to:
  /// **'No returns found'**
  String get purchasesReturnnoitems;

  /// No description provided for @purchasesReturnvalue.
  ///
  /// In en, this message translates to:
  /// **'Total Return Value'**
  String get purchasesReturnvalue;

  /// No description provided for @purchasesOriginalqty.
  ///
  /// In en, this message translates to:
  /// **'Original Qty'**
  String get purchasesOriginalqty;

  /// No description provided for @purchasesReturnqty.
  ///
  /// In en, this message translates to:
  /// **'Return Qty'**
  String get purchasesReturnqty;

  /// No description provided for @purchasesReturnqtyexceeds.
  ///
  /// In en, this message translates to:
  /// **'Return quantity exceeds the available quantity'**
  String get purchasesReturnqtyexceeds;

  /// No description provided for @purchasesReturnqtyinvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid return quantity'**
  String get purchasesReturnqtyinvalid;

  /// No description provided for @purchasesReturndate.
  ///
  /// In en, this message translates to:
  /// **'Return Date'**
  String get purchasesReturndate;

  /// No description provided for @purchasesReturntype.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get purchasesReturntype;

  /// No description provided for @purchasesPurchasereturn.
  ///
  /// In en, this message translates to:
  /// **'Purchase Return'**
  String get purchasesPurchasereturn;

  /// No description provided for @purchasesPoreturn.
  ///
  /// In en, this message translates to:
  /// **'PO Return'**
  String get purchasesPoreturn;

  /// No description provided for @salesInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get salesInvoices;

  /// No description provided for @salesNewinvoice.
  ///
  /// In en, this message translates to:
  /// **'New Invoice'**
  String get salesNewinvoice;

  /// No description provided for @salesEditinvoice.
  ///
  /// In en, this message translates to:
  /// **'Edit Invoice'**
  String get salesEditinvoice;

  /// No description provided for @salesExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get salesExportcsv;

  /// No description provided for @salesExported.
  ///
  /// In en, this message translates to:
  /// **'Invoices exported'**
  String get salesExported;

  /// No description provided for @salesExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export invoices'**
  String get salesExportfailed;

  /// No description provided for @salesInvoiceno.
  ///
  /// In en, this message translates to:
  /// **'Invoice No'**
  String get salesInvoiceno;

  /// No description provided for @salesDuedate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get salesDuedate;

  /// No description provided for @salesBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get salesBalance;

  /// No description provided for @salesConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get salesConfirmdelete;

  /// No description provided for @salesInvoicedeleted.
  ///
  /// In en, this message translates to:
  /// **'Invoice deleted successfully!'**
  String get salesInvoicedeleted;

  /// No description provided for @salesInvoicesaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved successfully!'**
  String get salesInvoicesaved;

  /// No description provided for @salesErrorCustomerRequired.
  ///
  /// In en, this message translates to:
  /// **'Customer is required'**
  String get salesErrorCustomerRequired;

  /// No description provided for @salesErrorItemsRequired.
  ///
  /// In en, this message translates to:
  /// **'At least one item is required'**
  String get salesErrorItemsRequired;

  /// No description provided for @salesItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get salesItems;

  /// No description provided for @salesRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get salesRate;

  /// No description provided for @salesTax.
  ///
  /// In en, this message translates to:
  /// **'Tax %'**
  String get salesTax;

  /// No description provided for @salesSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get salesSubtotal;

  /// No description provided for @salesDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get salesDiscount;

  /// No description provided for @salesGrandtotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get salesGrandtotal;

  /// No description provided for @salesAdditem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get salesAdditem;

  /// No description provided for @salesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get salesLoading;

  /// No description provided for @salesNoinvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices found'**
  String get salesNoinvoices;

  /// No description provided for @salesSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search invoices...'**
  String get salesSearchplaceholder;

  /// No description provided for @salesAllinvoices.
  ///
  /// In en, this message translates to:
  /// **'All Invoices'**
  String get salesAllinvoices;

  /// No description provided for @salesPaidinvoices.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get salesPaidinvoices;

  /// No description provided for @salesUnpaidinvoices.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get salesUnpaidinvoices;

  /// No description provided for @salesPartialinvoices.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get salesPartialinvoices;

  /// No description provided for @salesOverdueinvoices.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get salesOverdueinvoices;

  /// No description provided for @salesTotalsales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get salesTotalsales;

  /// No description provided for @salesTotalpaid.
  ///
  /// In en, this message translates to:
  /// **'Total Paid'**
  String get salesTotalpaid;

  /// No description provided for @salesTotaldue.
  ///
  /// In en, this message translates to:
  /// **'Total Due'**
  String get salesTotaldue;

  /// No description provided for @salesRecordsale.
  ///
  /// In en, this message translates to:
  /// **'Record Sale'**
  String get salesRecordsale;

  /// No description provided for @salesCreateinvoice.
  ///
  /// In en, this message translates to:
  /// **'Create Invoice'**
  String get salesCreateinvoice;

  /// No description provided for @salesPos.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get salesPos;

  /// No description provided for @salesSalesreport.
  ///
  /// In en, this message translates to:
  /// **'Sales Summary'**
  String get salesSalesreport;

  /// No description provided for @salesStockvaluation.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation'**
  String get salesStockvaluation;

  /// No description provided for @salesPrinta4.
  ///
  /// In en, this message translates to:
  /// **'Print A4'**
  String get salesPrinta4;

  /// No description provided for @salesReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get salesReceipt;

  /// No description provided for @salesreturnsAvailableqty.
  ///
  /// In en, this message translates to:
  /// **'Available for Return'**
  String get salesreturnsAvailableqty;

  /// No description provided for @salesreturnsDisposition.
  ///
  /// In en, this message translates to:
  /// **'Disposition'**
  String get salesreturnsDisposition;

  /// No description provided for @salesreturnsDispositionadjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get salesreturnsDispositionadjust;

  /// No description provided for @salesreturnsDispositioncredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get salesreturnsDispositioncredit;

  /// No description provided for @salesreturnsDispositionrefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get salesreturnsDispositionrefund;

  /// No description provided for @salesreturnsExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get salesreturnsExportcsv;

  /// No description provided for @salesreturnsExported.
  ///
  /// In en, this message translates to:
  /// **'Invoice returns exported'**
  String get salesreturnsExported;

  /// No description provided for @salesreturnsExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export invoice returns'**
  String get salesreturnsExportfailed;

  /// No description provided for @salesreturnsOriginalqty.
  ///
  /// In en, this message translates to:
  /// **'Original Qty'**
  String get salesreturnsOriginalqty;

  /// No description provided for @salesreturnsProcessreturn.
  ///
  /// In en, this message translates to:
  /// **'Process Return'**
  String get salesreturnsProcessreturn;

  /// No description provided for @salesreturnsReturn.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get salesreturnsReturn;

  /// No description provided for @salesreturnsReturndate.
  ///
  /// In en, this message translates to:
  /// **'Return Date'**
  String get salesreturnsReturndate;

  /// No description provided for @salesreturnsReturnno.
  ///
  /// In en, this message translates to:
  /// **'Return No'**
  String get salesreturnsReturnno;

  /// No description provided for @salesreturnsReturnnoitems.
  ///
  /// In en, this message translates to:
  /// **'No returns found'**
  String get salesreturnsReturnnoitems;

  /// No description provided for @salesreturnsReturnprocessed.
  ///
  /// In en, this message translates to:
  /// **'Return processed successfully'**
  String get salesreturnsReturnprocessed;

  /// No description provided for @salesreturnsReturnqty.
  ///
  /// In en, this message translates to:
  /// **'Return Qty'**
  String get salesreturnsReturnqty;

  /// No description provided for @salesreturnsReturnqtyexceeds.
  ///
  /// In en, this message translates to:
  /// **'Return quantity exceeds the available quantity'**
  String get salesreturnsReturnqtyexceeds;

  /// No description provided for @salesreturnsReturnqtyinvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid return quantity'**
  String get salesreturnsReturnqtyinvalid;

  /// No description provided for @salesreturnsReturnquantity.
  ///
  /// In en, this message translates to:
  /// **'Return Quantity'**
  String get salesreturnsReturnquantity;

  /// No description provided for @salesreturnsReturnreason.
  ///
  /// In en, this message translates to:
  /// **'Reason for Return'**
  String get salesreturnsReturnreason;

  /// No description provided for @salesreturnsReturnreasonplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter reason for return...'**
  String get salesreturnsReturnreasonplaceholder;

  /// No description provided for @salesreturnsReturnsubtitle.
  ///
  /// In en, this message translates to:
  /// **'Process a return for this invoice'**
  String get salesreturnsReturnsubtitle;

  /// No description provided for @salesreturnsReturntitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice Return'**
  String get salesreturnsReturntitle;

  /// No description provided for @salesreturnsReturnvalue.
  ///
  /// In en, this message translates to:
  /// **'Total Return Value'**
  String get salesreturnsReturnvalue;

  /// No description provided for @salesreturnsSearchinvoices.
  ///
  /// In en, this message translates to:
  /// **'Search invoices...'**
  String get salesreturnsSearchinvoices;

  /// No description provided for @salesreturnsSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search returns...'**
  String get salesreturnsSearchplaceholder;

  /// No description provided for @salesreturnsSelectinvoice.
  ///
  /// In en, this message translates to:
  /// **'Select an invoice'**
  String get salesreturnsSelectinvoice;

  /// No description provided for @inventoryItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get inventoryItems;

  /// No description provided for @inventoryItemsin.
  ///
  /// In en, this message translates to:
  /// **'Items in'**
  String get inventoryItemsin;

  /// No description provided for @inventoryBacktowarehouses.
  ///
  /// In en, this message translates to:
  /// **'Back to Warehouses'**
  String get inventoryBacktowarehouses;

  /// No description provided for @inventoryStockvalue.
  ///
  /// In en, this message translates to:
  /// **'Stock Value'**
  String get inventoryStockvalue;

  /// No description provided for @inventoryCurrentinventoryworth.
  ///
  /// In en, this message translates to:
  /// **'Current inventory worth'**
  String get inventoryCurrentinventoryworth;

  /// No description provided for @inventoryTotalstock.
  ///
  /// In en, this message translates to:
  /// **'Total Stock'**
  String get inventoryTotalstock;

  /// No description provided for @inventoryAggregateqty.
  ///
  /// In en, this message translates to:
  /// **'Aggregate quantity'**
  String get inventoryAggregateqty;

  /// No description provided for @inventoryInstock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inventoryInstock;

  /// No description provided for @inventoryLowstock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get inventoryLowstock;

  /// No description provided for @inventoryBelowreorder.
  ///
  /// In en, this message translates to:
  /// **'Below reorder level'**
  String get inventoryBelowreorder;

  /// No description provided for @inventoryOutofstock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get inventoryOutofstock;

  /// No description provided for @inventoryZerostock.
  ///
  /// In en, this message translates to:
  /// **'Zero stock items'**
  String get inventoryZerostock;

  /// No description provided for @inventoryCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get inventoryCategories;

  /// No description provided for @inventoryUniquecats.
  ///
  /// In en, this message translates to:
  /// **'Unique categories'**
  String get inventoryUniquecats;

  /// No description provided for @inventoryRawmaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials'**
  String get inventoryRawmaterials;

  /// No description provided for @inventoryMaterialitems.
  ///
  /// In en, this message translates to:
  /// **'Material items'**
  String get inventoryMaterialitems;

  /// No description provided for @inventoryFinishedgoods.
  ///
  /// In en, this message translates to:
  /// **'Finished Goods'**
  String get inventoryFinishedgoods;

  /// No description provided for @inventoryManufacturedproducts.
  ///
  /// In en, this message translates to:
  /// **'Manufactured products'**
  String get inventoryManufacturedproducts;

  /// No description provided for @inventoryExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get inventoryExportcsv;

  /// No description provided for @inventoryImportitems.
  ///
  /// In en, this message translates to:
  /// **'Import Items'**
  String get inventoryImportitems;

  /// No description provided for @inventoryLowstockreport.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Report'**
  String get inventoryLowstockreport;

  /// No description provided for @inventoryStockvaluation.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation'**
  String get inventoryStockvaluation;

  /// No description provided for @inventorySearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search items by name or code...'**
  String get inventorySearchplaceholder;

  /// No description provided for @inventoryNoitemsfound.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get inventoryNoitemsfound;

  /// No description provided for @inventoryNoitemsmatch.
  ///
  /// In en, this message translates to:
  /// **'No items match'**
  String get inventoryNoitemsmatch;

  /// No description provided for @inventoryNoitemswarehouse.
  ///
  /// In en, this message translates to:
  /// **'No items in this warehouse'**
  String get inventoryNoitemswarehouse;

  /// No description provided for @inventoryNoitemswarehouseyet.
  ///
  /// In en, this message translates to:
  /// **'This warehouse doesn\'t have any items yet.'**
  String get inventoryNoitemswarehouseyet;

  /// No description provided for @inventoryViewallitems.
  ///
  /// In en, this message translates to:
  /// **'View All Items'**
  String get inventoryViewallitems;

  /// No description provided for @inventoryClearsearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get inventoryClearsearch;

  /// No description provided for @inventoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get inventoryLoading;

  /// No description provided for @inventoryItemcode.
  ///
  /// In en, this message translates to:
  /// **'Item Code'**
  String get inventoryItemcode;

  /// No description provided for @inventoryItemname.
  ///
  /// In en, this message translates to:
  /// **'Item Name'**
  String get inventoryItemname;

  /// No description provided for @inventoryCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get inventoryCategory;

  /// No description provided for @inventoryUom.
  ///
  /// In en, this message translates to:
  /// **'UOM'**
  String get inventoryUom;

  /// No description provided for @inventoryStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get inventoryStock;

  /// No description provided for @inventoryCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get inventoryCost;

  /// No description provided for @inventoryPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get inventoryPrice;

  /// No description provided for @inventoryActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get inventoryActions;

  /// No description provided for @inventoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get inventoryEdit;

  /// No description provided for @inventoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get inventoryDelete;

  /// No description provided for @inventoryDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting...'**
  String get inventoryDeleting;

  /// No description provided for @inventoryItemdeleted.
  ///
  /// In en, this message translates to:
  /// **'Item deleted successfully!'**
  String get inventoryItemdeleted;

  /// No description provided for @inventoryConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete item'**
  String get inventoryConfirmdelete;

  /// No description provided for @inventoryItemsexported.
  ///
  /// In en, this message translates to:
  /// **'Items exported successfully!'**
  String get inventoryItemsexported;

  /// No description provided for @inventoryNoitemsexport.
  ///
  /// In en, this message translates to:
  /// **'No items to export'**
  String get inventoryNoitemsexport;

  /// No description provided for @inventoryImportcomplete.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get inventoryImportcomplete;

  /// No description provided for @inventoryFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get inventoryFailed;

  /// No description provided for @inventoryImporterror.
  ///
  /// In en, this message translates to:
  /// **'Failed to import CSV file'**
  String get inventoryImporterror;

  /// No description provided for @inventoryCsvempty.
  ///
  /// In en, this message translates to:
  /// **'CSV file is empty'**
  String get inventoryCsvempty;

  /// No description provided for @inventoryNewitem.
  ///
  /// In en, this message translates to:
  /// **'New Item'**
  String get inventoryNewitem;

  /// No description provided for @inventoryActiveitems.
  ///
  /// In en, this message translates to:
  /// **'Active items in catalog'**
  String get inventoryActiveitems;

  /// No description provided for @paymentsPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsPayments;

  /// No description provided for @paymentsRecordpayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get paymentsRecordpayment;

  /// No description provided for @paymentsSelectcustomer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get paymentsSelectcustomer;

  /// No description provided for @paymentsDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete payment'**
  String get paymentsDeleteconfirm;

  /// No description provided for @paymentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment deleted successfully!'**
  String get paymentsDeleted;

  /// No description provided for @paymentsNopayments.
  ///
  /// In en, this message translates to:
  /// **'No payments found'**
  String get paymentsNopayments;

  /// No description provided for @paymentsNopaymentsmatch.
  ///
  /// In en, this message translates to:
  /// **'No payments match'**
  String get paymentsNopaymentsmatch;

  /// No description provided for @paymentsSearchplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search payments...'**
  String get paymentsSearchplaceholder;

  /// No description provided for @paymentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage customer payments'**
  String get paymentsSubtitle;

  /// No description provided for @paymentsPaymentdetails.
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get paymentsPaymentdetails;

  /// No description provided for @paymentsPaymentno.
  ///
  /// In en, this message translates to:
  /// **'Payment No'**
  String get paymentsPaymentno;

  /// No description provided for @paymentsBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get paymentsBalance;

  /// No description provided for @paymentsAllocation.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get paymentsAllocation;

  /// No description provided for @paymentsTotalallocated.
  ///
  /// In en, this message translates to:
  /// **'Total Allocated'**
  String get paymentsTotalallocated;

  /// No description provided for @paymentsOpeninvoices.
  ///
  /// In en, this message translates to:
  /// **'Open Invoices'**
  String get paymentsOpeninvoices;

  /// No description provided for @paymentsNoopeninvoices.
  ///
  /// In en, this message translates to:
  /// **'No open invoices for this customer'**
  String get paymentsNoopeninvoices;

  /// No description provided for @paymentsSelectinvoices.
  ///
  /// In en, this message translates to:
  /// **'Allocate the payment to this customer\'s open invoices'**
  String get paymentsSelectinvoices;

  /// No description provided for @paymentsRecordedsuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded successfully'**
  String get paymentsRecordedsuccess;

  /// No description provided for @paymentsReferencehint.
  ///
  /// In en, this message translates to:
  /// **'Check number, transaction ID, etc.'**
  String get paymentsReferencehint;

  /// No description provided for @paymentsNoteshint.
  ///
  /// In en, this message translates to:
  /// **'Optional notes...'**
  String get paymentsNoteshint;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get navSales;

  /// No description provided for @navPurchases.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get navPurchases;

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get navSuppliers;

  /// No description provided for @navInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get navInvoices;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navManufacturing.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing'**
  String get navManufacturing;

  /// No description provided for @navProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get navProduction;

  /// No description provided for @navBom.
  ///
  /// In en, this message translates to:
  /// **'BOM'**
  String get navBom;

  /// No description provided for @navPos.
  ///
  /// In en, this message translates to:
  /// **'POS Terminal'**
  String get navPos;

  /// No description provided for @navItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get navItems;

  /// No description provided for @navWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Warehouses'**
  String get navWarehouses;

  /// No description provided for @navStockmovements.
  ///
  /// In en, this message translates to:
  /// **'Stock Movements'**
  String get navStockmovements;

  /// No description provided for @navStockbywarehouse.
  ///
  /// In en, this message translates to:
  /// **'Stock by Warehouse'**
  String get navStockbywarehouse;

  /// No description provided for @navPhysicalcounts.
  ///
  /// In en, this message translates to:
  /// **'Physical Counts'**
  String get navPhysicalcounts;

  /// No description provided for @navQuotations.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get navQuotations;

  /// No description provided for @physicalcountsCancelconfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this count? It cannot be completed afterward.'**
  String get physicalcountsCancelconfirm;

  /// No description provided for @physicalcountsCancelcount.
  ///
  /// In en, this message translates to:
  /// **'Cancel Count'**
  String get physicalcountsCancelcount;

  /// No description provided for @physicalcountsCancelledmsg.
  ///
  /// In en, this message translates to:
  /// **'Count cancelled'**
  String get physicalcountsCancelledmsg;

  /// No description provided for @physicalcountsCompleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Complete this count? Adjustments will be posted for any items with variances.'**
  String get physicalcountsCompleteconfirm;

  /// No description provided for @physicalcountsCompletecount.
  ///
  /// In en, this message translates to:
  /// **'Complete Count'**
  String get physicalcountsCompletecount;

  /// No description provided for @physicalcountsCompletedmsg.
  ///
  /// In en, this message translates to:
  /// **'Count completed'**
  String get physicalcountsCompletedmsg;

  /// No description provided for @physicalcountsRecordhint.
  ///
  /// In en, this message translates to:
  /// **'Counted quantity'**
  String get physicalcountsRecordhint;

  /// No description provided for @physicalcountsRecordinvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity'**
  String get physicalcountsRecordinvalid;

  /// No description provided for @physicalcountsRecorditems.
  ///
  /// In en, this message translates to:
  /// **'Record Items'**
  String get physicalcountsRecorditems;

  /// No description provided for @physicalcountsRecordnone.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one counted quantity'**
  String get physicalcountsRecordnone;

  /// No description provided for @physicalcountsRecordedmsg.
  ///
  /// In en, this message translates to:
  /// **'Counts recorded'**
  String get physicalcountsRecordedmsg;

  /// No description provided for @physicalcountsRecordsave.
  ///
  /// In en, this message translates to:
  /// **'Save Counts'**
  String get physicalcountsRecordsave;

  /// No description provided for @warehousesDeletedmsg.
  ///
  /// In en, this message translates to:
  /// **'Warehouse deleted'**
  String get warehousesDeletedmsg;

  /// No description provided for @warehousesDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this warehouse? It cannot be undone.'**
  String get warehousesDeleteconfirm;

  /// No description provided for @navSalesorders.
  ///
  /// In en, this message translates to:
  /// **'Sales Orders'**
  String get navSalesorders;

  /// No description provided for @navReportsdashboard.
  ///
  /// In en, this message translates to:
  /// **'Reports Dashboard'**
  String get navReportsdashboard;

  /// No description provided for @navArreports.
  ///
  /// In en, this message translates to:
  /// **'A/R Reports'**
  String get navArreports;

  /// No description provided for @navSalessummary.
  ///
  /// In en, this message translates to:
  /// **'Sales Summary'**
  String get navSalessummary;

  /// No description provided for @navStocklevel.
  ///
  /// In en, this message translates to:
  /// **'Stock Levels'**
  String get navStocklevel;

  /// No description provided for @navLowstock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alert'**
  String get navLowstock;

  /// No description provided for @navProfitloss.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss'**
  String get navProfitloss;

  /// No description provided for @navCashflow.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow'**
  String get navCashflow;

  /// No description provided for @navExpensesreport.
  ///
  /// In en, this message translates to:
  /// **'Expenses Report'**
  String get navExpensesreport;

  /// No description provided for @navHr.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get navHr;

  /// No description provided for @navEmployees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get navEmployees;

  /// No description provided for @navForecasts.
  ///
  /// In en, this message translates to:
  /// **'Forecasts'**
  String get navForecasts;

  /// No description provided for @navForecastsdashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navForecastsdashboard;

  /// No description provided for @navDemand.
  ///
  /// In en, this message translates to:
  /// **'Demand Forecast'**
  String get navDemand;

  /// No description provided for @navForecasttrends.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get navForecasttrends;

  /// No description provided for @navForecastaccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get navForecastaccuracy;

  /// No description provided for @navRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get navRoles;

  /// No description provided for @navUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get navUsers;

  /// No description provided for @navPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get navPayments;

  /// No description provided for @navActivitylog.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get navActivitylog;

  /// No description provided for @navIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get navIntegrations;

  /// No description provided for @navAdministrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get navAdministrator;

  /// No description provided for @navPurchaseorders.
  ///
  /// In en, this message translates to:
  /// **'Purchase Orders'**
  String get navPurchaseorders;

  /// No description provided for @navSupplieranalysis.
  ///
  /// In en, this message translates to:
  /// **'Supplier Analysis'**
  String get navSupplieranalysis;

  /// No description provided for @navStockvaluation.
  ///
  /// In en, this message translates to:
  /// **'Stock Valuation'**
  String get navStockvaluation;

  /// No description provided for @navInventorymovement.
  ///
  /// In en, this message translates to:
  /// **'Inventory Movement'**
  String get navInventorymovement;

  /// No description provided for @navPurchasereturns.
  ///
  /// In en, this message translates to:
  /// **'Purchase Returns'**
  String get navPurchasereturns;

  /// No description provided for @navInvoicereturns.
  ///
  /// In en, this message translates to:
  /// **'Invoice Returns'**
  String get navInvoicereturns;

  /// No description provided for @navQuickinvoice.
  ///
  /// In en, this message translates to:
  /// **'Quick Invoice'**
  String get navQuickinvoice;

  /// No description provided for @navProductionsummary.
  ///
  /// In en, this message translates to:
  /// **'Production Summary'**
  String get navProductionsummary;

  /// No description provided for @navBomusage.
  ///
  /// In en, this message translates to:
  /// **'BOM Usage'**
  String get navBomusage;

  /// No description provided for @navManageexpenses.
  ///
  /// In en, this message translates to:
  /// **'Manage Expenses'**
  String get navManageexpenses;

  /// No description provided for @navCustomreports.
  ///
  /// In en, this message translates to:
  /// **'Custom Reports'**
  String get navCustomreports;

  /// No description provided for @customreportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Reports'**
  String get customreportsTitle;

  /// No description provided for @customreportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Build and manage ad-hoc reports with a visual builder'**
  String get customreportsSubtitle;

  /// No description provided for @customreportsNewreport.
  ///
  /// In en, this message translates to:
  /// **'New Report'**
  String get customreportsNewreport;

  /// No description provided for @customreportsFromtemplate.
  ///
  /// In en, this message translates to:
  /// **'From Template'**
  String get customreportsFromtemplate;

  /// No description provided for @customreportsChoosetemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose a Template'**
  String get customreportsChoosetemplate;

  /// No description provided for @customreportsCreatefromtemplate.
  ///
  /// In en, this message translates to:
  /// **'Create from Template'**
  String get customreportsCreatefromtemplate;

  /// No description provided for @customreportsBasedon.
  ///
  /// In en, this message translates to:
  /// **'Based on'**
  String get customreportsBasedon;

  /// No description provided for @customreportsName.
  ///
  /// In en, this message translates to:
  /// **'Report Name'**
  String get customreportsName;

  /// No description provided for @customreportsNameplaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g., Monthly Sales Analysis'**
  String get customreportsNameplaceholder;

  /// No description provided for @customreportsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get customreportsDescription;

  /// No description provided for @customreportsDescplaceholder.
  ///
  /// In en, this message translates to:
  /// **'Optional description for this report'**
  String get customreportsDescplaceholder;

  /// No description provided for @customreportsNamerequired.
  ///
  /// In en, this message translates to:
  /// **'Report name is required'**
  String get customreportsNamerequired;

  /// No description provided for @customreportsCreateandedit.
  ///
  /// In en, this message translates to:
  /// **'Create & Open Editor'**
  String get customreportsCreateandedit;

  /// No description provided for @customreportsTotalreports.
  ///
  /// In en, this message translates to:
  /// **'Total Reports'**
  String get customreportsTotalreports;

  /// No description provided for @customreportsTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get customreportsTemplates;

  /// No description provided for @customreportsLastrun.
  ///
  /// In en, this message translates to:
  /// **'Last Run'**
  String get customreportsLastrun;

  /// No description provided for @customreportsCreated.
  ///
  /// In en, this message translates to:
  /// **'Report created successfully'**
  String get customreportsCreated;

  /// No description provided for @customreportsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get customreportsUpdated;

  /// No description provided for @customreportsTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get customreportsTemplate;

  /// No description provided for @customreportsActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get customreportsActions;

  /// No description provided for @customreportsRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get customreportsRun;

  /// No description provided for @customreportsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get customreportsEdit;

  /// No description provided for @customreportsDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get customreportsDuplicate;

  /// No description provided for @customreportsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get customreportsDelete;

  /// No description provided for @customreportsConfirmdelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Report'**
  String get customreportsConfirmdelete;

  /// No description provided for @customreportsConfirmdeletemsg.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get customreportsConfirmdeletemsg;

  /// No description provided for @customreportsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Report deleted successfully'**
  String get customreportsDeleted;

  /// No description provided for @customreportsDeleteerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete report'**
  String get customreportsDeleteerror;

  /// No description provided for @customreportsDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Report duplicated successfully'**
  String get customreportsDuplicated;

  /// No description provided for @customreportsDuplicateerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to duplicate report'**
  String get customreportsDuplicateerror;

  /// No description provided for @customreportsCreateerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to create report'**
  String get customreportsCreateerror;

  /// No description provided for @customreportsRan.
  ///
  /// In en, this message translates to:
  /// **'Report executed successfully'**
  String get customreportsRan;

  /// No description provided for @customreportsRunerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to run report'**
  String get customreportsRunerror;

  /// No description provided for @customreportsRows.
  ///
  /// In en, this message translates to:
  /// **'rows'**
  String get customreportsRows;

  /// No description provided for @customreportsNoreports.
  ///
  /// In en, this message translates to:
  /// **'No custom reports yet'**
  String get customreportsNoreports;

  /// No description provided for @customreportsNoreportsdesc.
  ///
  /// In en, this message translates to:
  /// **'Create your first report from scratch or use a template to get started.'**
  String get customreportsNoreportsdesc;

  /// No description provided for @customreportsbuilderSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get customreportsbuilderSave;

  /// No description provided for @customreportsbuilderSaved.
  ///
  /// In en, this message translates to:
  /// **'Report saved'**
  String get customreportsbuilderSaved;

  /// No description provided for @customreportsbuilderSaveerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to save report'**
  String get customreportsbuilderSaveerror;

  /// No description provided for @customreportsbuilderEntity.
  ///
  /// In en, this message translates to:
  /// **'Entity'**
  String get customreportsbuilderEntity;

  /// No description provided for @customreportsbuilderFields.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get customreportsbuilderFields;

  /// No description provided for @customreportsbuilderColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get customreportsbuilderColumns;

  /// No description provided for @customreportsbuilderFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get customreportsbuilderFilters;

  /// No description provided for @customreportsbuilderSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get customreportsbuilderSort;

  /// No description provided for @customreportsbuilderComputed.
  ///
  /// In en, this message translates to:
  /// **'Computed'**
  String get customreportsbuilderComputed;

  /// No description provided for @customreportsbuilderDragfieldshint.
  ///
  /// In en, this message translates to:
  /// **'Drag fields below'**
  String get customreportsbuilderDragfieldshint;

  /// No description provided for @customreportsbuilderDropfieldshere.
  ///
  /// In en, this message translates to:
  /// **'Drag fields here to add columns'**
  String get customreportsbuilderDropfieldshere;

  /// No description provided for @customreportsbuilderAddfilter.
  ///
  /// In en, this message translates to:
  /// **'Add Filter'**
  String get customreportsbuilderAddfilter;

  /// No description provided for @customreportsbuilderNofilters.
  ///
  /// In en, this message translates to:
  /// **'No filters — add one to filter results'**
  String get customreportsbuilderNofilters;

  /// No description provided for @customreportsbuilderAddsort.
  ///
  /// In en, this message translates to:
  /// **'Add Sort'**
  String get customreportsbuilderAddsort;

  /// No description provided for @customreportsbuilderNosorts.
  ///
  /// In en, this message translates to:
  /// **'No sorts — add one to order results'**
  String get customreportsbuilderNosorts;

  /// No description provided for @customreportsbuilderAddcomputed.
  ///
  /// In en, this message translates to:
  /// **'Add Computed Column'**
  String get customreportsbuilderAddcomputed;

  /// No description provided for @customreportsbuilderNocomputed.
  ///
  /// In en, this message translates to:
  /// **'No computed columns — add one for aggregations'**
  String get customreportsbuilderNocomputed;

  /// No description provided for @customreportsbuilderRun.
  ///
  /// In en, this message translates to:
  /// **'Run Report'**
  String get customreportsbuilderRun;

  /// No description provided for @customreportsbuilderRunerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to run report'**
  String get customreportsbuilderRunerror;

  /// No description provided for @customreportsbuilderPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get customreportsbuilderPreview;

  /// No description provided for @customreportsbuilderRuntopreview.
  ///
  /// In en, this message translates to:
  /// **'Click \'Run Report\' to see results'**
  String get customreportsbuilderRuntopreview;

  /// No description provided for @customreportsbuilderSelectentityfirst.
  ///
  /// In en, this message translates to:
  /// **'Select an entity to start building your report'**
  String get customreportsbuilderSelectentityfirst;

  /// No description provided for @customreportsbuilderChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get customreportsbuilderChart;

  /// No description provided for @customreportsbuilderEnablechart.
  ///
  /// In en, this message translates to:
  /// **'Enable chart visualization'**
  String get customreportsbuilderEnablechart;

  /// No description provided for @customreportsbuilderCharttype.
  ///
  /// In en, this message translates to:
  /// **'Chart Type'**
  String get customreportsbuilderCharttype;

  /// No description provided for @customreportsbuilderChartbar.
  ///
  /// In en, this message translates to:
  /// **'Bar'**
  String get customreportsbuilderChartbar;

  /// No description provided for @customreportsbuilderChartline.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get customreportsbuilderChartline;

  /// No description provided for @customreportsbuilderChartpie.
  ///
  /// In en, this message translates to:
  /// **'Pie'**
  String get customreportsbuilderChartpie;

  /// No description provided for @customreportsbuilderChartdoughnut.
  ///
  /// In en, this message translates to:
  /// **'Doughnut'**
  String get customreportsbuilderChartdoughnut;

  /// No description provided for @customreportsbuilderLabelfield.
  ///
  /// In en, this message translates to:
  /// **'Label Field'**
  String get customreportsbuilderLabelfield;

  /// No description provided for @customreportsbuilderValuefield.
  ///
  /// In en, this message translates to:
  /// **'Value Field'**
  String get customreportsbuilderValuefield;

  /// No description provided for @customreportsbuilderChartempty.
  ///
  /// In en, this message translates to:
  /// **'Select label and value fields in the Chart tab to render a chart.'**
  String get customreportsbuilderChartempty;

  /// No description provided for @customreportsbuilderGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get customreportsbuilderGroup;

  /// No description provided for @customreportsbuilderEnablegroupby.
  ///
  /// In en, this message translates to:
  /// **'Enable grouping'**
  String get customreportsbuilderEnablegroupby;

  /// No description provided for @customreportsbuilderGroupfields.
  ///
  /// In en, this message translates to:
  /// **'Group By Fields'**
  String get customreportsbuilderGroupfields;

  /// No description provided for @customreportsbuilderNogroupfields.
  ///
  /// In en, this message translates to:
  /// **'Select at least one field to group by'**
  String get customreportsbuilderNogroupfields;

  /// No description provided for @customreportsbuilderGroupbyinfo.
  ///
  /// In en, this message translates to:
  /// **'Add SUM, COUNT, or other aggregate computed columns to show grouped values.'**
  String get customreportsbuilderGroupbyinfo;

  /// No description provided for @customreportsbuilderAggregates.
  ///
  /// In en, this message translates to:
  /// **'Aggregates'**
  String get customreportsbuilderAggregates;

  /// No description provided for @customreportsbuilderAddaggregate.
  ///
  /// In en, this message translates to:
  /// **'Add Aggregate'**
  String get customreportsbuilderAddaggregate;

  /// No description provided for @customreportsbuilderNoaggregates.
  ///
  /// In en, this message translates to:
  /// **'No aggregates — add one to compute grouped values'**
  String get customreportsbuilderNoaggregates;

  /// No description provided for @customreportsbuilderExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export as CSV'**
  String get customreportsbuilderExportcsv;

  /// No description provided for @customreportsbuilderExportpdf.
  ///
  /// In en, this message translates to:
  /// **'Export as PDF'**
  String get customreportsbuilderExportpdf;

  /// No description provided for @customreportsbuilderSaveastemplate.
  ///
  /// In en, this message translates to:
  /// **'Save as Template'**
  String get customreportsbuilderSaveastemplate;

  /// No description provided for @customreportsbuilderShowall.
  ///
  /// In en, this message translates to:
  /// **'Show All'**
  String get customreportsbuilderShowall;

  /// No description provided for @customreportsbuilderHideall.
  ///
  /// In en, this message translates to:
  /// **'Hide All'**
  String get customreportsbuilderHideall;

  /// No description provided for @customreportsbuilderTemplatenameprompt.
  ///
  /// In en, this message translates to:
  /// **'Template name:'**
  String get customreportsbuilderTemplatenameprompt;

  /// No description provided for @customreportsbuilderTemplatesaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved successfully!'**
  String get customreportsbuilderTemplatesaved;

  /// No description provided for @customreportsbuilderTemplatesaveerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to save template'**
  String get customreportsbuilderTemplatesaveerror;

  /// No description provided for @actionsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionsSave;

  /// No description provided for @actionsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionsCancel;

  /// No description provided for @actionsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionsDelete;

  /// No description provided for @actionsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionsEdit;

  /// No description provided for @actionsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionsAdd;

  /// No description provided for @actionsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionsSearch;

  /// No description provided for @actionsFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get actionsFilter;

  /// No description provided for @actionsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionsExport;

  /// No description provided for @actionsImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionsImport;

  /// No description provided for @actionsPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get actionsPrint;

  /// No description provided for @actionsClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionsClose;

  /// No description provided for @actionsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionsConfirm;

  /// No description provided for @actionsSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get actionsSubmit;

  /// No description provided for @actionsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionsClear;

  /// No description provided for @actionsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionsReset;

  /// No description provided for @actionsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionsRefresh;

  /// No description provided for @actionsView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get actionsView;

  /// No description provided for @actionsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get actionsCreate;

  /// No description provided for @actionsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get actionsUpdate;

  /// No description provided for @actionsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get actionsDownload;

  /// No description provided for @actionsUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get actionsUpload;

  /// No description provided for @actionsBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionsBack;

  /// No description provided for @actionsNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionsNext;

  /// No description provided for @actionsPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get actionsPrevious;

  /// No description provided for @actionsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionsApply;

  /// No description provided for @actionsSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionsSelect;

  /// No description provided for @actionsYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get actionsYes;

  /// No description provided for @actionsNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get actionsNo;

  /// No description provided for @messagesSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get messagesSaved;

  /// No description provided for @messagesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted successfully'**
  String get messagesDeleted;

  /// No description provided for @messagesError.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get messagesError;

  /// No description provided for @messagesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get messagesConfirm;

  /// No description provided for @messagesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get messagesLoading;

  /// No description provided for @messagesNodata.
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get messagesNodata;

  /// No description provided for @messagesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get messagesSuccess;

  /// No description provided for @messagesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get messagesFailed;

  /// No description provided for @messagesRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get messagesRequired;

  /// No description provided for @messagesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get messagesInvalid;

  /// No description provided for @messagesSavederror.
  ///
  /// In en, this message translates to:
  /// **'Error saving data'**
  String get messagesSavederror;

  /// No description provided for @messagesDeletederror.
  ///
  /// In en, this message translates to:
  /// **'Error deleting data'**
  String get messagesDeletederror;

  /// No description provided for @messagesFetcherror.
  ///
  /// In en, this message translates to:
  /// **'Error fetching data'**
  String get messagesFetcherror;

  /// No description provided for @messagesNetworkerror.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get messagesNetworkerror;

  /// No description provided for @fieldsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldsName;

  /// No description provided for @fieldsQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get fieldsQuantity;

  /// No description provided for @fieldsPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get fieldsPrice;

  /// No description provided for @fieldsTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get fieldsTotal;

  /// No description provided for @fieldsDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get fieldsDate;

  /// No description provided for @fieldsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get fieldsStatus;

  /// No description provided for @fieldsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fieldsDescription;

  /// No description provided for @fieldsAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get fieldsAddress;

  /// No description provided for @fieldsPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get fieldsPhone;

  /// No description provided for @fieldsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldsEmail;

  /// No description provided for @fieldsAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get fieldsAmount;

  /// No description provided for @fieldsBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get fieldsBalance;

  /// No description provided for @fieldsReturned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get fieldsReturned;

  /// No description provided for @fieldsDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get fieldsDiscount;

  /// No description provided for @fieldsTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get fieldsTax;

  /// No description provided for @fieldsSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get fieldsSubtotal;

  /// No description provided for @fieldsGrandtotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get fieldsGrandtotal;

  /// No description provided for @fieldsNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get fieldsNotes;

  /// No description provided for @fieldsReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get fieldsReference;

  /// No description provided for @fieldsInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get fieldsInvoice;

  /// No description provided for @fieldsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get fieldsCustomer;

  /// No description provided for @fieldsCustomerCode.
  ///
  /// In en, this message translates to:
  /// **'Customer Code'**
  String get fieldsCustomerCode;

  /// No description provided for @fieldsItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get fieldsItem;

  /// No description provided for @fieldsWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get fieldsWarehouse;

  /// No description provided for @fieldsSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get fieldsSupplier;

  /// No description provided for @fieldsCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get fieldsCategory;

  /// No description provided for @fieldsUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get fieldsUnit;

  /// No description provided for @fieldsCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get fieldsCost;

  /// No description provided for @fieldsRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get fieldsRate;

  /// No description provided for @fieldsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get fieldsSearch;

  /// No description provided for @fieldsFromdate.
  ///
  /// In en, this message translates to:
  /// **'From Date'**
  String get fieldsFromdate;

  /// No description provided for @fieldsTodate.
  ///
  /// In en, this message translates to:
  /// **'To Date'**
  String get fieldsTodate;

  /// No description provided for @fieldsCreatedat.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get fieldsCreatedat;

  /// No description provided for @fieldsUpdatedat.
  ///
  /// In en, this message translates to:
  /// **'Updated At'**
  String get fieldsUpdatedat;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get statusInactive;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get statusSubmitted;

  /// No description provided for @statusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get statusSent;

  /// No description provided for @statusPartiallypaid.
  ///
  /// In en, this message translates to:
  /// **'Partially Paid'**
  String get statusPartiallypaid;

  /// No description provided for @statusReturned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get statusReturned;

  /// No description provided for @statusPartiallyreturned.
  ///
  /// In en, this message translates to:
  /// **'Partially Returned'**
  String get statusPartiallyreturned;

  /// No description provided for @statusPartiallyreceived.
  ///
  /// In en, this message translates to:
  /// **'Partially Received'**
  String get statusPartiallyreceived;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get statusUnpaid;

  /// No description provided for @statusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get statusPartial;

  /// No description provided for @statusDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get statusDue;

  /// No description provided for @statusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get statusOverdue;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @commonSelectoption.
  ///
  /// In en, this message translates to:
  /// **'Select an option'**
  String get commonSelectoption;

  /// No description provided for @commonEntervalue.
  ///
  /// In en, this message translates to:
  /// **'Enter value'**
  String get commonEntervalue;

  /// No description provided for @commonNoresults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get commonNoresults;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @commonActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get commonActions;

  /// No description provided for @commonDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get commonDetails;

  /// No description provided for @commonSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get commonSummary;

  /// No description provided for @commonHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commonHistory;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get commonLanguage;

  /// No description provided for @commonCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get commonCurrency;

  /// No description provided for @commonLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get commonLogout;

  /// No description provided for @commonLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get commonLogin;

  /// No description provided for @loginUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get loginUsername;

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get loginSigningIn;

  /// No description provided for @loginInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid username or password'**
  String get loginInvalidCredentials;

  /// No description provided for @loginServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Is it running on port 3011?'**
  String get loginServerUnreachable;

  /// No description provided for @loginDevHint.
  ///
  /// In en, this message translates to:
  /// **'Default login: admin / admin123'**
  String get loginDevHint;

  /// No description provided for @splashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get splashLoading;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirmMessage;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get changePasswordCurrent;

  /// No description provided for @changePasswordNew.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get changePasswordNew;

  /// No description provided for @changePasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get changePasswordConfirm;

  /// No description provided for @changePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordButton;

  /// No description provided for @changePasswordUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get changePasswordUpdating;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get changePasswordSuccess;

  /// No description provided for @changePasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get changePasswordMismatch;

  /// No description provided for @changePasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get changePasswordTooShort;

  /// No description provided for @changePasswordSameAsCurrent.
  ///
  /// In en, this message translates to:
  /// **'New password must be different from the current password'**
  String get changePasswordSameAsCurrent;

  /// No description provided for @changePasswordWrongCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get changePasswordWrongCurrent;

  /// No description provided for @commonUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get commonUser;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @commonTotalin.
  ///
  /// In en, this message translates to:
  /// **'Total In'**
  String get commonTotalin;

  /// No description provided for @commonTotalout.
  ///
  /// In en, this message translates to:
  /// **'Total Out'**
  String get commonTotalout;

  /// No description provided for @commonQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get commonQuantity;

  /// No description provided for @commonAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get commonAmount;

  /// No description provided for @commonDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get commonDate;

  /// No description provided for @commonStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commonStatus;

  /// No description provided for @commonCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory;

  /// No description provided for @commonDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get commonFilter;

  /// No description provided for @commonExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get commonExport;

  /// No description provided for @commonImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get commonImport;

  /// No description provided for @commonPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get commonPrint;

  /// No description provided for @commonDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonNavigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get commonNavigate;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get commonView;

  /// No description provided for @commonShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get commonShow;

  /// No description provided for @commonHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get commonHide;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNodata.
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get commonNodata;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get commonSales;

  /// No description provided for @commonReceiptprinting.
  ///
  /// In en, this message translates to:
  /// **'Receipt printing...'**
  String get commonReceiptprinting;

  /// No description provided for @commonPurchases.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get commonPurchases;

  /// No description provided for @commonProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get commonProduction;

  /// No description provided for @commonTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get commonTransfers;

  /// No description provided for @commonWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get commonWarehouse;

  /// No description provided for @commonItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get commonItem;

  /// No description provided for @commonCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get commonCustomer;

  /// No description provided for @commonSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get commonSupplier;

  /// No description provided for @commonUom.
  ///
  /// In en, this message translates to:
  /// **'UOM'**
  String get commonUom;

  /// No description provided for @commonStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get commonStock;

  /// No description provided for @commonPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get commonPrice;

  /// No description provided for @commonCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get commonCost;

  /// No description provided for @commonUnits.
  ///
  /// In en, this message translates to:
  /// **'units'**
  String get commonUnits;

  /// No description provided for @commonFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get commonFrom;

  /// No description provided for @commonTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get commonTo;

  /// No description provided for @shortcutsQuickactions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get shortcutsQuickactions;

  /// No description provided for @shortcutsDismissbar.
  ///
  /// In en, this message translates to:
  /// **'Hide shortcut bar'**
  String get shortcutsDismissbar;

  /// No description provided for @shortcutsNoshortcuts.
  ///
  /// In en, this message translates to:
  /// **'No shortcuts'**
  String get shortcutsNoshortcuts;

  /// No description provided for @shortcutsPrinta4.
  ///
  /// In en, this message translates to:
  /// **'Print A4 Invoice'**
  String get shortcutsPrinta4;

  /// No description provided for @shortcutsPrintreceipt.
  ///
  /// In en, this message translates to:
  /// **'Print Receipt (Thermal)'**
  String get shortcutsPrintreceipt;

  /// No description provided for @shortcutsPrintpo.
  ///
  /// In en, this message translates to:
  /// **'Print Purchase Order'**
  String get shortcutsPrintpo;

  /// No description provided for @shortcutsPrintquotation.
  ///
  /// In en, this message translates to:
  /// **'Print Quotation'**
  String get shortcutsPrintquotation;

  /// No description provided for @errorsNotfound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorsNotfound;

  /// No description provided for @errorsUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Unauthorized'**
  String get errorsUnauthorized;

  /// No description provided for @errorsServererror.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get errorsServererror;

  /// No description provided for @errorsBadrequest.
  ///
  /// In en, this message translates to:
  /// **'Bad request'**
  String get errorsBadrequest;

  /// No description provided for @errorsComingsoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get errorsComingsoon;

  /// No description provided for @errorsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get errorsFailed;

  /// No description provided for @errorsAllowpopups.
  ///
  /// In en, this message translates to:
  /// **'Please allow popups to print receipts'**
  String get errorsAllowpopups;

  /// No description provided for @inventoryReorderlevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder Level'**
  String get inventoryReorderlevel;

  /// No description provided for @inventorySellingprice.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get inventorySellingprice;

  /// No description provided for @inventoryStandardcost.
  ///
  /// In en, this message translates to:
  /// **'Standard Cost'**
  String get inventoryStandardcost;

  /// No description provided for @inventoryCurrentstock.
  ///
  /// In en, this message translates to:
  /// **'Current Stock'**
  String get inventoryCurrentstock;

  /// No description provided for @inventoryItemdetails.
  ///
  /// In en, this message translates to:
  /// **'Item Details'**
  String get inventoryItemdetails;

  /// No description provided for @inventoryStockbywarehouse.
  ///
  /// In en, this message translates to:
  /// **'Stock by Warehouse'**
  String get inventoryStockbywarehouse;

  /// No description provided for @inventoryStockledger.
  ///
  /// In en, this message translates to:
  /// **'Stock Ledger'**
  String get inventoryStockledger;

  /// No description provided for @inventoryStockledgerType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get inventoryStockledgerType;

  /// No description provided for @inventoryStockledgerIn.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get inventoryStockledgerIn;

  /// No description provided for @inventoryStockledgerOut.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get inventoryStockledgerOut;

  /// No description provided for @inventoryStockledgerBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get inventoryStockledgerBalance;

  /// No description provided for @inventoryStockledgerNoentries.
  ///
  /// In en, this message translates to:
  /// **'No stock movements found'**
  String get inventoryStockledgerNoentries;

  /// No description provided for @inventoryStockledgerAllwarehouses.
  ///
  /// In en, this message translates to:
  /// **'All Warehouses'**
  String get inventoryStockledgerAllwarehouses;

  /// No description provided for @inventoryStockledgerExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get inventoryStockledgerExportcsv;

  /// No description provided for @inventoryStockledgerExported.
  ///
  /// In en, this message translates to:
  /// **'Stock ledger exported'**
  String get inventoryStockledgerExported;

  /// No description provided for @inventoryStockledgerExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export stock ledger'**
  String get inventoryStockledgerExportfailed;

  /// No description provided for @inventoryRack.
  ///
  /// In en, this message translates to:
  /// **'Rack'**
  String get inventoryRack;

  /// No description provided for @inventorySaletype.
  ///
  /// In en, this message translates to:
  /// **'Sale Type'**
  String get inventorySaletype;

  /// No description provided for @inventoryPurchaseprice.
  ///
  /// In en, this message translates to:
  /// **'Purchase Price'**
  String get inventoryPurchaseprice;

  /// No description provided for @inventoryPurchased.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get inventoryPurchased;

  /// No description provided for @inventoryItemtype.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get inventoryItemtype;

  /// No description provided for @inventorySaletypePacked.
  ///
  /// In en, this message translates to:
  /// **'Packed'**
  String get inventorySaletypePacked;

  /// No description provided for @inventorySaletypeLoose.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get inventorySaletypeLoose;

  /// No description provided for @customersCustomercode.
  ///
  /// In en, this message translates to:
  /// **'Customer Code'**
  String get customersCustomercode;

  /// No description provided for @customersContactperson.
  ///
  /// In en, this message translates to:
  /// **'Contact Person'**
  String get customersContactperson;

  /// No description provided for @customersCreditlimit.
  ///
  /// In en, this message translates to:
  /// **'Credit Limit'**
  String get customersCreditlimit;

  /// No description provided for @customersBillingaddress.
  ///
  /// In en, this message translates to:
  /// **'Billing Address'**
  String get customersBillingaddress;

  /// No description provided for @customersEditcustomer.
  ///
  /// In en, this message translates to:
  /// **'Edit Customer'**
  String get customersEditcustomer;

  /// No description provided for @customersErrorEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get customersErrorEmail;

  /// No description provided for @customersErrorNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Customer name is required'**
  String get customersErrorNameRequired;

  /// No description provided for @customersErrorNonnegative.
  ///
  /// In en, this message translates to:
  /// **'Must be 0 or more'**
  String get customersErrorNonnegative;

  /// No description provided for @customersErrorNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get customersErrorNumber;

  /// No description provided for @customersErrorPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get customersErrorPhoneRequired;

  /// No description provided for @customersPaymenttermsdays.
  ///
  /// In en, this message translates to:
  /// **'Payment Terms (Days)'**
  String get customersPaymenttermsdays;

  /// No description provided for @customersShippingaddress.
  ///
  /// In en, this message translates to:
  /// **'Shipping Address'**
  String get customersShippingaddress;

  /// No description provided for @customersCreditutilization.
  ///
  /// In en, this message translates to:
  /// **'Credit Utilization'**
  String get customersCreditutilization;

  /// No description provided for @customersCurrentbalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get customersCurrentbalance;

  /// No description provided for @customersCustomerdetails.
  ///
  /// In en, this message translates to:
  /// **'Customer Details'**
  String get customersCustomerdetails;

  /// No description provided for @customersOpeningbalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get customersOpeningbalance;

  /// No description provided for @customersPaymentterms.
  ///
  /// In en, this message translates to:
  /// **'Payment Terms'**
  String get customersPaymentterms;

  /// No description provided for @customersLedger.
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get customersLedger;

  /// No description provided for @customersLedgerClosingbalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get customersLedgerClosingbalance;

  /// No description provided for @customersLedgerCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get customersLedgerCredit;

  /// No description provided for @customersLedgerDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get customersLedgerDebit;

  /// No description provided for @customersLedgerNoentries.
  ///
  /// In en, this message translates to:
  /// **'No ledger entries found'**
  String get customersLedgerNoentries;

  /// No description provided for @customersLedgerTotalcredit.
  ///
  /// In en, this message translates to:
  /// **'Total Credit'**
  String get customersLedgerTotalcredit;

  /// No description provided for @customersLedgerTotaldebit.
  ///
  /// In en, this message translates to:
  /// **'Total Debit'**
  String get customersLedgerTotaldebit;

  /// No description provided for @customersBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get customersBalance;

  /// No description provided for @customersAccountsettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get customersAccountsettings;

  /// No description provided for @customersAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get customersAdd;

  /// No description provided for @customersAllinvoicesallocated.
  ///
  /// In en, this message translates to:
  /// **'All open invoices are already allocated'**
  String get customersAllinvoicesallocated;

  /// No description provided for @customersAllocatedinvoices.
  ///
  /// In en, this message translates to:
  /// **'Total Allocated'**
  String get customersAllocatedinvoices;

  /// No description provided for @customersAllocation.
  ///
  /// In en, this message translates to:
  /// **'Invoice Allocations'**
  String get customersAllocation;

  /// No description provided for @customersAllocationrequired.
  ///
  /// In en, this message translates to:
  /// **'At least one invoice allocation is required'**
  String get customersAllocationrequired;

  /// No description provided for @customersAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get customersAmount;

  /// No description provided for @customersAmountmustmatch.
  ///
  /// In en, this message translates to:
  /// **'Amount must match total allocated'**
  String get customersAmountmustmatch;

  /// No description provided for @customersAutoallocate.
  ///
  /// In en, this message translates to:
  /// **'Auto Allocate'**
  String get customersAutoallocate;

  /// No description provided for @customersAvailableinvoices.
  ///
  /// In en, this message translates to:
  /// **'Available Invoices'**
  String get customersAvailableinvoices;

  /// No description provided for @customersAvgdaystopay.
  ///
  /// In en, this message translates to:
  /// **'Avg. Days to Pay'**
  String get customersAvgdaystopay;

  /// No description provided for @customersBacktocustomers.
  ///
  /// In en, this message translates to:
  /// **'Back to Customers'**
  String get customersBacktocustomers;

  /// No description provided for @customersCancelinvoice.
  ///
  /// In en, this message translates to:
  /// **'Cancel Invoice'**
  String get customersCancelinvoice;

  /// No description provided for @customersCancelinvoiceconfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this invoice? This cannot be undone.'**
  String get customersCancelinvoiceconfirm;

  /// No description provided for @customersClosingbalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get customersClosingbalance;

  /// No description provided for @customersConfirmdeleteinvoice.
  ///
  /// In en, this message translates to:
  /// **'Delete invoice'**
  String get customersConfirmdeleteinvoice;

  /// No description provided for @customersConfirmdeletepayment.
  ///
  /// In en, this message translates to:
  /// **'Delete payment'**
  String get customersConfirmdeletepayment;

  /// No description provided for @customersCustomersince.
  ///
  /// In en, this message translates to:
  /// **'Customer Since'**
  String get customersCustomersince;

  /// No description provided for @customersDeleteinvoice.
  ///
  /// In en, this message translates to:
  /// **'Delete Invoice'**
  String get customersDeleteinvoice;

  /// No description provided for @customersDeletepayment.
  ///
  /// In en, this message translates to:
  /// **'Delete Payment'**
  String get customersDeletepayment;

  /// No description provided for @customersDuedate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get customersDuedate;

  /// No description provided for @customersExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export to CSV'**
  String get customersExportcsv;

  /// No description provided for @customersExportimage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get customersExportimage;

  /// No description provided for @customersExportpdf.
  ///
  /// In en, this message translates to:
  /// **'Export to PDF'**
  String get customersExportpdf;

  /// No description provided for @customersExportsuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get customersExportsuccess;

  /// No description provided for @customersFinancialsummary.
  ///
  /// In en, this message translates to:
  /// **'Financial Summary'**
  String get customersFinancialsummary;

  /// No description provided for @customersInvoicedeleted.
  ///
  /// In en, this message translates to:
  /// **'Invoice deleted'**
  String get customersInvoicedeleted;

  /// No description provided for @customersInvoiceno.
  ///
  /// In en, this message translates to:
  /// **'Invoice No'**
  String get customersInvoiceno;

  /// No description provided for @customersInvoicecancelled.
  ///
  /// In en, this message translates to:
  /// **'Invoice cancelled'**
  String get customersInvoicecancelled;

  /// No description provided for @customersInvoicestatus.
  ///
  /// In en, this message translates to:
  /// **'Invoice Status'**
  String get customersInvoicestatus;

  /// No description provided for @customersInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get customersInvoices;

  /// No description provided for @customersLedgerPayments.
  ///
  /// In en, this message translates to:
  /// **'payments'**
  String get customersLedgerPayments;

  /// No description provided for @customersLedgerTotals.
  ///
  /// In en, this message translates to:
  /// **'TOTALS'**
  String get customersLedgerTotals;

  /// No description provided for @customersLedgerType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get customersLedgerType;

  /// No description provided for @customersMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get customersMethod;

  /// No description provided for @customersNoinvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices found'**
  String get customersNoinvoices;

  /// No description provided for @customersNopayments.
  ///
  /// In en, this message translates to:
  /// **'No payments found'**
  String get customersNopayments;

  /// No description provided for @customersNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customersNotes;

  /// No description provided for @customersOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get customersOutstanding;

  /// No description provided for @customersOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get customersOverdue;

  /// No description provided for @customersOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get customersOverview;

  /// No description provided for @customersPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get customersPaid;

  /// No description provided for @customersPaymentdeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment deleted'**
  String get customersPaymentdeleted;

  /// No description provided for @customersPaymentno.
  ///
  /// In en, this message translates to:
  /// **'Payment No'**
  String get customersPaymentno;

  /// No description provided for @customersPaymentrecordedsuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment Recorded Successfully'**
  String get customersPaymentrecordedsuccess;

  /// No description provided for @customersPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get customersPayments;

  /// No description provided for @customersPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get customersPending;

  /// No description provided for @customersPrintreceipt.
  ///
  /// In en, this message translates to:
  /// **'Print Receipt'**
  String get customersPrintreceipt;

  /// No description provided for @customersPrintreceipta4.
  ///
  /// In en, this message translates to:
  /// **'Print Receipt (A4)'**
  String get customersPrintreceipta4;

  /// No description provided for @customersRecordpayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get customersRecordpayment;

  /// No description provided for @customersReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get customersReference;

  /// No description provided for @customersRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get customersRemove;

  /// No description provided for @customersStatement.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get customersStatement;

  /// No description provided for @customersStatementsummary.
  ///
  /// In en, this message translates to:
  /// **'Statement Summary'**
  String get customersStatementsummary;

  /// No description provided for @customersTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get customersTotal;

  /// No description provided for @customersTotalamount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get customersTotalamount;

  /// No description provided for @customersTotalcredits.
  ///
  /// In en, this message translates to:
  /// **'Total Credits'**
  String get customersTotalcredits;

  /// No description provided for @customersTotaldebits.
  ///
  /// In en, this message translates to:
  /// **'Total Debits'**
  String get customersTotaldebits;

  /// No description provided for @customersTotalinvoiced.
  ///
  /// In en, this message translates to:
  /// **'Total Invoiced'**
  String get customersTotalinvoiced;

  /// No description provided for @customersTotalreceived.
  ///
  /// In en, this message translates to:
  /// **'Total Received'**
  String get customersTotalreceived;

  /// No description provided for @customersTransactiondetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get customersTransactiondetails;

  /// No description provided for @customersUnallocated.
  ///
  /// In en, this message translates to:
  /// **'Unallocated Amount'**
  String get customersUnallocated;

  /// No description provided for @customersUtilization.
  ///
  /// In en, this message translates to:
  /// **'Utilization'**
  String get customersUtilization;

  /// No description provided for @customersWhatnext.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do next?'**
  String get customersWhatnext;

  /// No description provided for @commonPage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get commonPage;

  /// No description provided for @commonOf.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get commonOf;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get commonPrevious;

  /// No description provided for @commonPerpage.
  ///
  /// In en, this message translates to:
  /// **'per page'**
  String get commonPerpage;

  /// No description provided for @inventoryEdititem.
  ///
  /// In en, this message translates to:
  /// **'Edit Item'**
  String get inventoryEdititem;

  /// No description provided for @inventoryErrorCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Item code is required'**
  String get inventoryErrorCodeRequired;

  /// No description provided for @inventoryErrorNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Item name is required'**
  String get inventoryErrorNameRequired;

  /// No description provided for @inventoryErrorUomRequired.
  ///
  /// In en, this message translates to:
  /// **'Unit of measure is required'**
  String get inventoryErrorUomRequired;

  /// No description provided for @inventoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get inventoryRequired;

  /// No description provided for @inventoryErrorNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get inventoryErrorNumber;

  /// No description provided for @inventoryErrorNonnegative.
  ///
  /// In en, this message translates to:
  /// **'Must be 0 or more'**
  String get inventoryErrorNonnegative;

  /// No description provided for @salesClicktoadditem.
  ///
  /// In en, this message translates to:
  /// **'Click to add item...'**
  String get salesClicktoadditem;

  /// No description provided for @salesNoproductsfound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get salesNoproductsfound;

  /// No description provided for @salesPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get salesPayment;

  /// No description provided for @salesRecordpaymentnow.
  ///
  /// In en, this message translates to:
  /// **'Record payment now'**
  String get salesRecordpaymentnow;

  /// No description provided for @salesPaymenthistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get salesPaymenthistory;

  /// No description provided for @salesPaymentdate.
  ///
  /// In en, this message translates to:
  /// **'Payment Date'**
  String get salesPaymentdate;

  /// No description provided for @salesPaymentmethods.
  ///
  /// In en, this message translates to:
  /// **'Payment Methods'**
  String get salesPaymentmethods;

  /// No description provided for @salesAddmethod.
  ///
  /// In en, this message translates to:
  /// **'Add Method'**
  String get salesAddmethod;

  /// No description provided for @salesMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get salesMethod;

  /// No description provided for @salesReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get salesReference;

  /// No description provided for @salesPaymenttotal.
  ///
  /// In en, this message translates to:
  /// **'Payment Total'**
  String get salesPaymenttotal;

  /// No description provided for @paymentsErrorAmountGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Payment amount must be greater than zero'**
  String get paymentsErrorAmountGreaterThanZero;

  /// No description provided for @paymentsErrorAmountExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Payment exceeds the remaining balance of {balance}'**
  String paymentsErrorAmountExceedsBalance(Object balance);

  /// No description provided for @salesPaymentrecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get salesPaymentrecorded;

  /// No description provided for @salesEditpayment.
  ///
  /// In en, this message translates to:
  /// **'Edit Payment'**
  String get salesEditpayment;

  /// No description provided for @salesPaymentupdated.
  ///
  /// In en, this message translates to:
  /// **'Payment updated'**
  String get salesPaymentupdated;

  /// No description provided for @salesDiscountscope.
  ///
  /// In en, this message translates to:
  /// **'Discount Scope'**
  String get salesDiscountscope;

  /// No description provided for @salesInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get salesInvoice;

  /// No description provided for @salesPeritem.
  ///
  /// In en, this message translates to:
  /// **'Per Item'**
  String get salesPeritem;

  /// No description provided for @bomActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get bomActivate;

  /// No description provided for @bomActivated.
  ///
  /// In en, this message translates to:
  /// **'BOM activated'**
  String get bomActivated;

  /// No description provided for @bomAddmaterial.
  ///
  /// In en, this message translates to:
  /// **'Add Material'**
  String get bomAddmaterial;

  /// No description provided for @bomCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get bomCreated;

  /// No description provided for @bomCurrentstock.
  ///
  /// In en, this message translates to:
  /// **'Current Stock'**
  String get bomCurrentstock;

  /// No description provided for @bomDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get bomDeactivate;

  /// No description provided for @bomDeactivated.
  ///
  /// In en, this message translates to:
  /// **'BOM deactivated'**
  String get bomDeactivated;

  /// No description provided for @bomDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this BOM? Materials referencing it will remain untouched. Note: BOMs already used in production records cannot be deleted.'**
  String get bomDeleteconfirm;

  /// No description provided for @bomDeleted.
  ///
  /// In en, this message translates to:
  /// **'BOM deleted'**
  String get bomDeleted;

  /// No description provided for @bomDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get bomDescription;

  /// No description provided for @bomDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Bill of Materials'**
  String get bomDetailstitle;

  /// No description provided for @bomEdittitle.
  ///
  /// In en, this message translates to:
  /// **'Edit BOM'**
  String get bomEdittitle;

  /// No description provided for @bomErrorFinisheditem.
  ///
  /// In en, this message translates to:
  /// **'Select the finished item this BOM produces.'**
  String get bomErrorFinisheditem;

  /// No description provided for @bomErrorItemsrequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one material line'**
  String get bomErrorItemsrequired;

  /// No description provided for @bomExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get bomExportcsv;

  /// No description provided for @bomExported.
  ///
  /// In en, this message translates to:
  /// **'BOMs exported'**
  String get bomExported;

  /// No description provided for @bomExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get bomExportfailed;

  /// No description provided for @bomFinisheditem.
  ///
  /// In en, this message translates to:
  /// **'Finished Item'**
  String get bomFinisheditem;

  /// No description provided for @bomItems.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get bomItems;

  /// No description provided for @bomMaterialcost.
  ///
  /// In en, this message translates to:
  /// **'Material Cost'**
  String get bomMaterialcost;

  /// No description provided for @bomMaterials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get bomMaterials;

  /// No description provided for @bomName.
  ///
  /// In en, this message translates to:
  /// **'BOM Name'**
  String get bomName;

  /// No description provided for @bomNo.
  ///
  /// In en, this message translates to:
  /// **'BOM No'**
  String get bomNo;

  /// No description provided for @bomNoMaterials.
  ///
  /// In en, this message translates to:
  /// **'No material lines'**
  String get bomNoMaterials;

  /// No description provided for @bomQuantity.
  ///
  /// In en, this message translates to:
  /// **'Batch Quantity'**
  String get bomQuantity;

  /// No description provided for @bomSaved.
  ///
  /// In en, this message translates to:
  /// **'BOM saved'**
  String get bomSaved;

  /// No description provided for @bomUnitcost.
  ///
  /// In en, this message translates to:
  /// **'Std Cost'**
  String get bomUnitcost;

  /// No description provided for @productionAddinput.
  ///
  /// In en, this message translates to:
  /// **'Add Input'**
  String get productionAddinput;

  /// No description provided for @productionBatchno.
  ///
  /// In en, this message translates to:
  /// **'Batch No'**
  String get productionBatchno;

  /// No description provided for @productionBom.
  ///
  /// In en, this message translates to:
  /// **'BOM'**
  String get productionBom;

  /// No description provided for @productionBomwarningMismatch.
  ///
  /// In en, this message translates to:
  /// **'The selected BOM produces a different item. Change the BOM or the output item.'**
  String get productionBomwarningMismatch;

  /// No description provided for @productionBomwarningPickoutput.
  ///
  /// In en, this message translates to:
  /// **'Pick an output item first — the BOM auto-fills the inputs for its finished product.'**
  String get productionBomwarningPickoutput;

  /// No description provided for @productionCostperunit.
  ///
  /// In en, this message translates to:
  /// **'Cost per Unit'**
  String get productionCostperunit;

  /// No description provided for @productionCostpreview.
  ///
  /// In en, this message translates to:
  /// **'Batch Cost Preview'**
  String get productionCostpreview;

  /// No description provided for @productionCreatedby.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get productionCreatedby;

  /// No description provided for @productionDeleteconfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this production run? Stock movements and the GL entry will be reversed.'**
  String get productionDeleteconfirm;

  /// No description provided for @productionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Production deleted'**
  String get productionDeleted;

  /// No description provided for @productionDetailstitle.
  ///
  /// In en, this message translates to:
  /// **'Production Details'**
  String get productionDetailstitle;

  /// No description provided for @productionErrorInputsrequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one input material.'**
  String get productionErrorInputsrequired;

  /// No description provided for @productionErrorBomrequired.
  ///
  /// In en, this message translates to:
  /// **'Select a BOM to load its material inputs.'**
  String get productionErrorBomrequired;

  /// No description provided for @productionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get productionAvailable;

  /// No description provided for @productionErrorInvalidqty.
  ///
  /// In en, this message translates to:
  /// **'Input quantities must be greater than zero.'**
  String get productionErrorInvalidqty;

  /// No description provided for @productionErrorOutputrequired.
  ///
  /// In en, this message translates to:
  /// **'Output item is required.'**
  String get productionErrorOutputrequired;

  /// No description provided for @productionErrorWarehouserequired.
  ///
  /// In en, this message translates to:
  /// **'Finished-goods warehouse is required.'**
  String get productionErrorWarehouserequired;

  /// No description provided for @productionExportcsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get productionExportcsv;

  /// No description provided for @productionExported.
  ///
  /// In en, this message translates to:
  /// **'Productions exported.'**
  String get productionExported;

  /// No description provided for @productionExportfailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get productionExportfailed;

  /// No description provided for @productionInputqty.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get productionInputqty;

  /// No description provided for @productionInputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get productionInputs;

  /// No description provided for @productionInputsBomhint.
  ///
  /// In en, this message translates to:
  /// **'Select a BOM — its material lines appear here.'**
  String get productionInputsBomhint;

  /// No description provided for @productionMaterialcost.
  ///
  /// In en, this message translates to:
  /// **'Material Cost'**
  String get productionMaterialcost;

  /// No description provided for @productionNo.
  ///
  /// In en, this message translates to:
  /// **'Production No'**
  String get productionNo;

  /// No description provided for @productionNoinputs.
  ///
  /// In en, this message translates to:
  /// **'No input materials recorded for this run.'**
  String get productionNoinputs;

  /// No description provided for @productionOutputitem.
  ///
  /// In en, this message translates to:
  /// **'Output Item'**
  String get productionOutputitem;

  /// No description provided for @productionOutputquantity.
  ///
  /// In en, this message translates to:
  /// **'Output Quantity'**
  String get productionOutputquantity;

  /// No description provided for @productionOverhead.
  ///
  /// In en, this message translates to:
  /// **'Overhead Cost'**
  String get productionOverhead;

  /// No description provided for @productionRawmaterialsWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials Warehouse'**
  String get productionRawmaterialsWarehouse;

  /// No description provided for @productionSaved.
  ///
  /// In en, this message translates to:
  /// **'Production recorded'**
  String get productionSaved;

  /// No description provided for @productionShortfallLine.
  ///
  /// In en, this message translates to:
  /// **'{name}: {available} available, {required} required'**
  String productionShortfallLine(
    Object available,
    Object name,
    Object required,
  );

  /// No description provided for @productionShortfallTitle.
  ///
  /// In en, this message translates to:
  /// **'Insufficient stock for these inputs'**
  String get productionShortfallTitle;

  /// No description provided for @productionTotalcost.
  ///
  /// In en, this message translates to:
  /// **'Total Cost'**
  String get productionTotalcost;

  /// No description provided for @productionUnitcost.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost'**
  String get productionUnitcost;

  /// No description provided for @productionWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Finished Goods Warehouse'**
  String get productionWarehouse;

  /// No description provided for @fieldsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get fieldsAccount;

  /// No description provided for @dashboardCashbankposition.
  ///
  /// In en, this message translates to:
  /// **'Cash / Bank Position'**
  String get dashboardCashbankposition;

  /// No description provided for @dashboardCashrecon.
  ///
  /// In en, this message translates to:
  /// **'Reconcile'**
  String get dashboardCashrecon;

  /// No description provided for @reportsCashreconciliation.
  ///
  /// In en, this message translates to:
  /// **'Cash Reconciliation'**
  String get reportsCashreconciliation;

  /// No description provided for @cashreconOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get cashreconOpening;

  /// No description provided for @cashreconInflow.
  ///
  /// In en, this message translates to:
  /// **'Inflow'**
  String get cashreconInflow;

  /// No description provided for @cashreconOutflow.
  ///
  /// In en, this message translates to:
  /// **'Outflow'**
  String get cashreconOutflow;

  /// No description provided for @cashreconNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get cashreconNet;

  /// No description provided for @cashreconExpected.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get cashreconExpected;

  /// No description provided for @cashreconCounted.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get cashreconCounted;

  /// No description provided for @cashreconVariance.
  ///
  /// In en, this message translates to:
  /// **'Variance'**
  String get cashreconVariance;

  /// No description provided for @cashreconNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get cashreconNotes;

  /// No description provided for @cashreconNotcounted.
  ///
  /// In en, this message translates to:
  /// **'Not counted'**
  String get cashreconNotcounted;

  /// No description provided for @cashreconReconciled.
  ///
  /// In en, this message translates to:
  /// **'Reconciled'**
  String get cashreconReconciled;

  /// No description provided for @cashreconSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cashreconSave;

  /// No description provided for @cashreconSaved.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation saved'**
  String get cashreconSaved;

  /// No description provided for @cashposTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get cashposTransactions;

  /// No description provided for @cashposPaymentreceived.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get cashposPaymentreceived;

  /// No description provided for @cashposSupplierpayment.
  ///
  /// In en, this message translates to:
  /// **'Supplier payment'**
  String get cashposSupplierpayment;

  /// No description provided for @cashposExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get cashposExpense;

  /// No description provided for @cashposSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get cashposSalary;

  /// No description provided for @cashposRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get cashposRefund;

  /// No description provided for @dashboardOpeningbalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get dashboardOpeningbalance;

  /// No description provided for @dashboardOpeningbalanceHint.
  ///
  /// In en, this message translates to:
  /// **'The starting cash/bank balance your business was founded with. It is added to today\'s position.'**
  String get dashboardOpeningbalanceHint;

  /// No description provided for @dashboardOpeningbalanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Opening balances saved'**
  String get dashboardOpeningbalanceSaved;

  /// No description provided for @drpPresetToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get drpPresetToday;

  /// No description provided for @drpPresetYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get drpPresetYesterday;

  /// No description provided for @drpPresetThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get drpPresetThisWeek;

  /// No description provided for @drpPresetLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get drpPresetLastWeek;

  /// No description provided for @drpPresetLast7.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get drpPresetLast7;

  /// No description provided for @drpPresetLast30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get drpPresetLast30;

  /// No description provided for @drpPresetLast90.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get drpPresetLast90;

  /// No description provided for @drpPresetThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get drpPresetThisMonth;

  /// No description provided for @drpPresetLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get drpPresetLastMonth;

  /// No description provided for @drpPresetCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get drpPresetCustomRange;

  /// No description provided for @drpPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get drpPresetCustom;

  /// No description provided for @drpPresetAllDates.
  ///
  /// In en, this message translates to:
  /// **'All dates'**
  String get drpPresetAllDates;

  /// No description provided for @drpPickStart.
  ///
  /// In en, this message translates to:
  /// **'Pick a start date'**
  String get drpPickStart;

  /// No description provided for @drpPickEnd.
  ///
  /// In en, this message translates to:
  /// **'Pick an end date'**
  String get drpPickEnd;

  /// No description provided for @drpPickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get drpPickDate;

  /// No description provided for @drpDaysSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} days selected'**
  String drpDaysSelected(Object count);

  /// No description provided for @drpOneDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get drpOneDay;

  /// No description provided for @drpPrevPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get drpPrevPeriod;

  /// No description provided for @drpNextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get drpNextPeriod;

  /// No description provided for @drpWeekStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get drpWeekStartsOn;

  /// No description provided for @drpWeekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get drpWeekdayMonday;

  /// No description provided for @drpWeekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get drpWeekdaySaturday;

  /// No description provided for @drpWeekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get drpWeekdaySunday;

  /// No description provided for @drpSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default range'**
  String get drpSetDefault;

  /// No description provided for @drpDefaultSet.
  ///
  /// In en, this message translates to:
  /// **'Default range set'**
  String get drpDefaultSet;

  /// No description provided for @drpDefaultFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save default range'**
  String get drpDefaultFailed;

  /// No description provided for @drpWeekStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save week start'**
  String get drpWeekStartFailed;

  /// No description provided for @drpAddPreset.
  ///
  /// In en, this message translates to:
  /// **'Add preset'**
  String get drpAddPreset;

  /// No description provided for @drpPresetName.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get drpPresetName;

  /// No description provided for @drpPresetAdded.
  ///
  /// In en, this message translates to:
  /// **'Preset added'**
  String get drpPresetAdded;

  /// No description provided for @drpPresetAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save preset'**
  String get drpPresetAddFailed;

  /// No description provided for @drpPresetRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove preset'**
  String get drpPresetRemoveFailed;

  /// No description provided for @drpPresetRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove preset'**
  String get drpPresetRemove;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
