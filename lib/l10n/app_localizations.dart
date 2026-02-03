import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

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
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Library Manager'**
  String get appTitle;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addItem;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Item'**
  String get editItem;

  /// No description provided for @deleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete Item'**
  String get deleteItem;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @designation.
  ///
  /// In en, this message translates to:
  /// **'Designation'**
  String get designation;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @stockLocation.
  ///
  /// In en, this message translates to:
  /// **'Stock Location'**
  String get stockLocation;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this item?'**
  String get confirmDelete;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get search;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @generateReport.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generateReport;

  /// No description provided for @codeRequired.
  ///
  /// In en, this message translates to:
  /// **'Code is required'**
  String get codeRequired;

  /// No description provided for @designationRequired.
  ///
  /// In en, this message translates to:
  /// **'Designation is required'**
  String get designationRequired;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @inventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// No description provided for @fullCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Code'**
  String get fullCodeLabel;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @nationalLibrary.
  ///
  /// In en, this message translates to:
  /// **'National Library'**
  String get nationalLibrary;

  /// No description provided for @algerianSystem.
  ///
  /// In en, this message translates to:
  /// **'Algerian Management System'**
  String get algerianSystem;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @addNewBook.
  ///
  /// In en, this message translates to:
  /// **'New Book'**
  String get addNewBook;

  /// No description provided for @refreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshData;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @dataProtection.
  ///
  /// In en, this message translates to:
  /// **'Data Protection'**
  String get dataProtection;

  /// No description provided for @backupDatabase.
  ///
  /// In en, this message translates to:
  /// **'Backup Database'**
  String get backupDatabase;

  /// No description provided for @restoreDatabase.
  ///
  /// In en, this message translates to:
  /// **'Restore Database'**
  String get restoreDatabase;

  /// No description provided for @manageVariables.
  ///
  /// In en, this message translates to:
  /// **'Manage Variables'**
  String get manageVariables;

  /// No description provided for @manageAttributes.
  ///
  /// In en, this message translates to:
  /// **'Manage Attributes'**
  String get manageAttributes;

  /// No description provided for @variablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Variables & Attributes'**
  String get variablesTitle;

  /// No description provided for @manageVariablesDescription.
  ///
  /// In en, this message translates to:
  /// **'Modify code prefixes and system categories (LIV, REV, etc.)'**
  String get manageVariablesDescription;

  /// No description provided for @manageAttributesDescription.
  ///
  /// In en, this message translates to:
  /// **'Modify lookups for Locations, Statuses, and Stock Locations'**
  String get manageAttributesDescription;

  /// No description provided for @backupDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a copy of your database'**
  String get backupDescription;

  /// No description provided for @restoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore data from a backup file'**
  String get restoreDescription;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @adminPassword.
  ///
  /// In en, this message translates to:
  /// **'Admin Password'**
  String get adminPassword;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong Password'**
  String get wrongPassword;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get dangerZone;

  /// No description provided for @eraseAllData.
  ///
  /// In en, this message translates to:
  /// **'Erase All Database'**
  String get eraseAllData;

  /// No description provided for @eraseWarning.
  ///
  /// In en, this message translates to:
  /// **'WARNING: This will permanently delete all items and reset settings. This action cannot be undone.'**
  String get eraseWarning;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connectionType.
  ///
  /// In en, this message translates to:
  /// **'Connection Type'**
  String get connectionType;

  /// No description provided for @hostMode.
  ///
  /// In en, this message translates to:
  /// **'Server (Host)'**
  String get hostMode;

  /// No description provided for @clientMode.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get clientMode;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter Admin Password'**
  String get enterPassword;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Operation History'**
  String get historyTitle;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @operationAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get operationAdd;

  /// No description provided for @operationUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get operationUpdate;

  /// No description provided for @operationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get operationDelete;

  /// No description provided for @operationWipe.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get operationWipe;

  /// No description provided for @noHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No history items found'**
  String get noHistoryFound;

  /// No description provided for @by.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get by;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully'**
  String get passwordUpdated;

  /// No description provided for @minPasswordLength.
  ///
  /// In en, this message translates to:
  /// **'Minimum 4 characters'**
  String get minPasswordLength;

  /// No description provided for @unlockSettings.
  ///
  /// In en, this message translates to:
  /// **'Unlock edit (requires password)'**
  String get unlockSettings;

  /// No description provided for @showActionsLog.
  ///
  /// In en, this message translates to:
  /// **'View operation history'**
  String get showActionsLog;

  /// No description provided for @dataWiped.
  ///
  /// In en, this message translates to:
  /// **'All data has been erased'**
  String get dataWiped;

  /// No description provided for @validate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get validate;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get allStatuses;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFilters;

  /// No description provided for @priceDzd.
  ///
  /// In en, this message translates to:
  /// **'Price (DZD)'**
  String get priceDzd;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More Items'**
  String get loadMore;

  /// No description provided for @serverModeName.
  ///
  /// In en, this message translates to:
  /// **'Server Mode'**
  String get serverModeName;

  /// No description provided for @clientModeName.
  ///
  /// In en, this message translates to:
  /// **'Client Mode'**
  String get clientModeName;

  /// No description provided for @totalDocuments.
  ///
  /// In en, this message translates to:
  /// **'Total Documents'**
  String get totalDocuments;

  /// No description provided for @inventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Inventory Value'**
  String get inventoryValue;

  /// No description provided for @onLoan.
  ///
  /// In en, this message translates to:
  /// **'On Loan'**
  String get onLoan;

  /// No description provided for @historyAction.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyAction;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported successfully'**
  String get exportSuccess;

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Export error'**
  String get exportError;

  /// No description provided for @allTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get allTypes;

  /// No description provided for @noItemsFound.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get noItemsFound;

  /// No description provided for @backupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup created successfully!'**
  String get backupSuccess;

  /// No description provided for @restoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Database restored successfully!'**
  String get restoreSuccess;

  /// No description provided for @setPassword.
  ///
  /// In en, this message translates to:
  /// **'Set a password'**
  String get setPassword;

  /// No description provided for @importExcel.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel (.xlsx)'**
  String get importExcel;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Data imported successfully!'**
  String get importSuccess;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: '**
  String get importError;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan Barcode'**
  String get scanBarcode;

  /// No description provided for @cameraPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to scan barcodes.'**
  String get cameraPermissionRequired;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission was denied.'**
  String get cameraPermissionDenied;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode (ISBN/EAN)'**
  String get barcode;

  /// No description provided for @barcodeHint.
  ///
  /// In en, this message translates to:
  /// **'Scan or enter barcode'**
  String get barcodeHint;

  /// No description provided for @autoGenerated.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated'**
  String get autoGenerated;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @statusDisponible.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get statusDisponible;

  /// No description provided for @statusEmprunte.
  ///
  /// In en, this message translates to:
  /// **'Borrowed'**
  String get statusEmprunte;

  /// No description provided for @statusReserve.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get statusReserve;

  /// No description provided for @statusEndommage.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get statusEndommage;

  /// No description provided for @itemProfile.
  ///
  /// In en, this message translates to:
  /// **'Item Profile'**
  String get itemProfile;

  /// No description provided for @itemDetails.
  ///
  /// In en, this message translates to:
  /// **'Item Details'**
  String get itemDetails;

  /// No description provided for @editItemDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Details'**
  String get editItemDetails;

  /// No description provided for @locationInfo.
  ///
  /// In en, this message translates to:
  /// **'Location Info'**
  String get locationInfo;

  /// No description provided for @pricingInfo.
  ///
  /// In en, this message translates to:
  /// **'Pricing Info'**
  String get pricingInfo;

  /// No description provided for @technicalInfo.
  ///
  /// In en, this message translates to:
  /// **'Technical Info'**
  String get technicalInfo;

  /// No description provided for @markAsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Mark as Available'**
  String get markAsAvailable;

  /// No description provided for @markAsBorrowed.
  ///
  /// In en, this message translates to:
  /// **'Mark as Borrowed'**
  String get markAsBorrowed;

  /// No description provided for @markAsReserved.
  ///
  /// In en, this message translates to:
  /// **'Mark as Reserved'**
  String get markAsReserved;

  /// No description provided for @markAsDamaged.
  ///
  /// In en, this message translates to:
  /// **'Mark as Damaged'**
  String get markAsDamaged;

  /// No description provided for @prefix.
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get prefix;

  /// No description provided for @prefixHint.
  ///
  /// In en, this message translates to:
  /// **'3-4 letters (e.g., LIV, ARCH)'**
  String get prefixHint;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @labelHint.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g., Book, Archives)'**
  String get labelHint;

  /// No description provided for @saveDefinition.
  ///
  /// In en, this message translates to:
  /// **'Save Variable'**
  String get saveDefinition;

  /// No description provided for @cancelEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel Edit'**
  String get cancelEdit;

  /// No description provided for @confirmDeleteDefinition.
  ///
  /// In en, this message translates to:
  /// **'Delete Variable?'**
  String get confirmDeleteDefinition;

  /// No description provided for @deleteDefinitionWarning.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this variable? Existing items will remain but filtering might be affected.'**
  String get deleteDefinitionWarning;

  /// No description provided for @notePrefixChange.
  ///
  /// In en, this message translates to:
  /// **'Note: Changing a prefix will update all linked items.'**
  String get notePrefixChange;

  /// No description provided for @addVariable.
  ///
  /// In en, this message translates to:
  /// **'Add Variable'**
  String get addVariable;

  /// No description provided for @updateVariable.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateVariable;

  /// No description provided for @newVariable.
  ///
  /// In en, this message translates to:
  /// **'New Variable'**
  String get newVariable;

  /// No description provided for @editVariable.
  ///
  /// In en, this message translates to:
  /// **'Edit Variable'**
  String get editVariable;

  /// No description provided for @savedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get savedSuccessfully;

  /// No description provided for @pairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing Code'**
  String get pairingCode;

  /// No description provided for @scanServerCode.
  ///
  /// In en, this message translates to:
  /// **'Scan Server Code'**
  String get scanServerCode;

  /// No description provided for @scanServerDescription.
  ///
  /// In en, this message translates to:
  /// **'Connect automatically by scanning the QR code on the host screen.'**
  String get scanServerDescription;

  /// No description provided for @pairingCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Allow clients to connect by scanning this code.'**
  String get pairingCodeDescription;

  /// No description provided for @enterPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Pairing Code'**
  String get enterPairingCode;

  /// No description provided for @enterPairingCodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Connect without a camera by typing the 6-digit code from the Host.'**
  String get enterPairingCodeDescription;

  /// No description provided for @pairingSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching for host on the LAN...'**
  String get pairingSearching;

  /// No description provided for @pairingIpSet.
  ///
  /// In en, this message translates to:
  /// **'Host found. Connection configured.'**
  String get pairingIpSet;

  /// No description provided for @pairingHostNotFound.
  ///
  /// In en, this message translates to:
  /// **'No host found. Check the code and that both devices are on the same LAN.'**
  String get pairingHostNotFound;

  /// No description provided for @pairingValidMinutes.
  ///
  /// In en, this message translates to:
  /// **'Valid for about {minutes} min'**
  String pairingValidMinutes(int minutes);

  /// No description provided for @connectedDevices.
  ///
  /// In en, this message translates to:
  /// **'Connected Devices'**
  String get connectedDevices;

  /// No description provided for @connectedViaLan.
  ///
  /// In en, this message translates to:
  /// **'Connected via LAN'**
  String get connectedViaLan;

  /// No description provided for @scanWithUsbOrType.
  ///
  /// In en, this message translates to:
  /// **'Use a USB Scanner or type code'**
  String get scanWithUsbOrType;

  /// No description provided for @scanOrTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Scan code or type here...'**
  String get scanOrTypeHint;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required field'**
  String get requiredField;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @loans.
  ///
  /// In en, this message translates to:
  /// **'Loans'**
  String get loans;

  /// No description provided for @memberManagement.
  ///
  /// In en, this message translates to:
  /// **'Member Management'**
  String get memberManagement;

  /// No description provided for @loanManagement.
  ///
  /// In en, this message translates to:
  /// **'Loan Management'**
  String get loanManagement;

  /// No description provided for @newLoan.
  ///
  /// In en, this message translates to:
  /// **'New Loan'**
  String get newLoan;

  /// No description provided for @returnLoan.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnLoan;

  /// No description provided for @selectMember.
  ///
  /// In en, this message translates to:
  /// **'1. Select Member'**
  String get selectMember;

  /// No description provided for @selectItem.
  ///
  /// In en, this message translates to:
  /// **'2. Select Item'**
  String get selectItem;

  /// No description provided for @validateLoan.
  ///
  /// In en, this message translates to:
  /// **'Validate Loan'**
  String get validateLoan;

  /// No description provided for @memberSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Member (Name or ID)'**
  String get memberSearchHint;

  /// No description provided for @itemSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Barcode or Title'**
  String get itemSearchHint;

  /// No description provided for @loanSuccess.
  ///
  /// In en, this message translates to:
  /// **'Loan recorded successfully'**
  String get loanSuccess;

  /// No description provided for @returnSuccess.
  ///
  /// In en, this message translates to:
  /// **'Return recorded successfully'**
  String get returnSuccess;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get addMember;

  /// No description provided for @editMember.
  ///
  /// In en, this message translates to:
  /// **'Edit Member'**
  String get editMember;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @scanToReturn.
  ///
  /// In en, this message translates to:
  /// **'Scan item to return'**
  String get scanToReturn;

  /// No description provided for @confirmReturn.
  ///
  /// In en, this message translates to:
  /// **'Confirm Return'**
  String get confirmReturn;

  /// No description provided for @itemNotFound.
  ///
  /// In en, this message translates to:
  /// **'Item not found'**
  String get itemNotFound;

  /// No description provided for @itemNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Item is not available.'**
  String get itemNotAvailable;

  /// No description provided for @noActiveLoan.
  ///
  /// In en, this message translates to:
  /// **'No active loan found for this item.'**
  String get noActiveLoan;

  /// No description provided for @selectCamera.
  ///
  /// In en, this message translates to:
  /// **'Select Camera'**
  String get selectCamera;

  /// No description provided for @cameraFront.
  ///
  /// In en, this message translates to:
  /// **'Front Camera'**
  String get cameraFront;

  /// No description provided for @cameraBack.
  ///
  /// In en, this message translates to:
  /// **'Back Camera'**
  String get cameraBack;

  /// No description provided for @cameraExternal.
  ///
  /// In en, this message translates to:
  /// **'External Camera (USB)'**
  String get cameraExternal;

  /// No description provided for @cameraUnknown.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraUnknown;

  /// No description provided for @flash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get flash;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get switchCamera;

  /// No description provided for @cameras.
  ///
  /// In en, this message translates to:
  /// **'Cameras'**
  String get cameras;

  /// No description provided for @helpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenter;

  /// No description provided for @setupRoadmap.
  ///
  /// In en, this message translates to:
  /// **'Setup Roadmap'**
  String get setupRoadmap;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @stepLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get stepLanguage;

  /// No description provided for @stepSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get stepSecurity;

  /// No description provided for @stepConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get stepConfiguration;

  /// No description provided for @setupLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred language for the application.'**
  String get setupLanguageDesc;

  /// No description provided for @setupPasswordDesc.
  ///
  /// In en, this message translates to:
  /// **'Set an administrative password to protect your data.'**
  String get setupPasswordDesc;

  /// No description provided for @setupConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure basic library prefixes and attributes.'**
  String get setupConfigDesc;

  /// No description provided for @setupComplete.
  ///
  /// In en, this message translates to:
  /// **'Setup Complete!'**
  String get setupComplete;

  /// No description provided for @setupCompleteDesc.
  ///
  /// In en, this message translates to:
  /// **'You are now ready to use the Library Management System.'**
  String get setupCompleteDesc;

  /// No description provided for @helpMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Member Management'**
  String get helpMembersTitle;

  /// No description provided for @helpMembersContent.
  ///
  /// In en, this message translates to:
  /// **'1. Go to the \'Members\' tab to add or edit registered users.\n2. Each member is assigned a unique ID (e.g., 260001) formatted for national registration.\n3. Track loan history, active borrows, and registration dates per member.'**
  String get helpMembersContent;

  /// No description provided for @helpLoansTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan System'**
  String get helpLoansTitle;

  /// No description provided for @helpLoansContent.
  ///
  /// In en, this message translates to:
  /// **'1. Scanning an item in the \'Loans\' screen starts the checkout process.\n2. Enter the member ID or scan their membership card to link the loan.\n3. Return items by scanning them again in the \'Prêts\' section or manually marking them as returned in history.'**
  String get helpLoansContent;

  /// No description provided for @helpSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN Synchronization'**
  String get helpSyncTitle;

  /// No description provided for @helpSyncContent.
  ///
  /// In en, this message translates to:
  /// **'1. One machine must be set as the \'Host\' (Server) while others are \'Clients\'.\n2. Clients connect using the Host\'s IP address. Pair automatically by scanning the Host\'s sync QR code.\n3. Changes on any device are mirrored to the server via local network protocols.'**
  String get helpSyncContent;

  /// No description provided for @helpBarcodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Barcode Scanning'**
  String get helpBarcodeTitle;

  /// No description provided for @helpBarcodeContent.
  ///
  /// In en, this message translates to:
  /// **'1. Integrated Camera: Supports front/back/external camera toggling with LED flash support.\n2. USB Scanners: Plug-and-play support in any search field.\n3. Multiple Devices: Switch between available cameras using the device selection dropdown in the scanner window.'**
  String get helpBarcodeContent;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation and guides'**
  String get documentation;

  /// No description provided for @resetOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Reset Setup Roadmap'**
  String get resetOnboarding;

  /// No description provided for @resetOnboardingDesc.
  ///
  /// In en, this message translates to:
  /// **'Reset onboarding and setup roadmap (Testing only)'**
  String get resetOnboardingDesc;

  /// No description provided for @resetRestartApp.
  ///
  /// In en, this message translates to:
  /// **'Setup roadmap reset. Restart the app.'**
  String get resetRestartApp;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkForUpdates;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateAvailable;

  /// No description provided for @noUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'You are using the latest version.'**
  String get noUpdateAvailable;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @enableLanAccess.
  ///
  /// In en, this message translates to:
  /// **'Enable LAN Access'**
  String get enableLanAccess;

  /// No description provided for @enableLanAccessDescription.
  ///
  /// In en, this message translates to:
  /// **'Allow other PCs to connect by adding Windows Firewall rules (requires Admin).'**
  String get enableLanAccessDescription;

  /// No description provided for @lanAccessEnabled.
  ///
  /// In en, this message translates to:
  /// **'LAN access enabled.'**
  String get lanAccessEnabled;

  /// No description provided for @lanAccessFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add firewall rules. Please approve the Admin prompt.'**
  String get lanAccessFailed;

  /// No description provided for @quickScan.
  ///
  /// In en, this message translates to:
  /// **'Quick Scan'**
  String get quickScan;

  /// No description provided for @appDefinitionTitle.
  ///
  /// In en, this message translates to:
  /// **'What is Library Manager?'**
  String get appDefinitionTitle;

  /// No description provided for @appDefinitionContent.
  ///
  /// In en, this message translates to:
  /// **'Library Manager is a professional desktop solution designed for Algerian libraries and documentation centers. It provides specialized tools for inventory management, LAN-based synchronization, and barcode tracking. The system supports full English, French, and Arabic categorization following national standards.'**
  String get appDefinitionContent;
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
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
