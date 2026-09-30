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

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

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

  /// No description provided for @wholeNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Whole number required'**
  String get wholeNumberRequired;

  /// No description provided for @numberRequired.
  ///
  /// In en, this message translates to:
  /// **'Number required'**
  String get numberRequired;

  /// No description provided for @mustBeNonNegative.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than or equal to 0'**
  String get mustBeNonNegative;

  /// No description provided for @newValue.
  ///
  /// In en, this message translates to:
  /// **'New Value'**
  String get newValue;

  /// No description provided for @attributeOptionsNote.
  ///
  /// In en, this message translates to:
  /// **'These options appear in the dropdowns when adding or editing a book.'**
  String get attributeOptionsNote;

  /// No description provided for @usbScannerNote.
  ///
  /// In en, this message translates to:
  /// **'USB scanners act as keyboards. Just scan!'**
  String get usbScannerNote;

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

  /// No description provided for @selectBackupDatabase.
  ///
  /// In en, this message translates to:
  /// **'Select Backup Database'**
  String get selectBackupDatabase;

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
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
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

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting;

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

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed.'**
  String get backupFailed;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed.'**
  String get restoreFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone'**
  String get noPhone;

  /// No description provided for @scannerError.
  ///
  /// In en, this message translates to:
  /// **'Scanner error: {code}'**
  String scannerError(String code);

  /// No description provided for @selectedItemLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected: {name} ({status})'**
  String selectedItemLabel(String name, String status);

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

  /// No description provided for @statusEnReparation.
  ///
  /// In en, this message translates to:
  /// **'In repair'**
  String get statusEnReparation;

  /// No description provided for @statusPerdu.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get statusPerdu;

  /// No description provided for @statusArchive.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get statusArchive;

  /// No description provided for @itemCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get itemCopies;

  /// No description provided for @copyNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy {n}'**
  String copyNumberLabel(int n);

  /// No description provided for @copyBarcodeMissing.
  ///
  /// In en, this message translates to:
  /// **'No copy barcode'**
  String get copyBarcodeMissing;

  /// No description provided for @changeCopyState.
  ///
  /// In en, this message translates to:
  /// **'Change condition'**
  String get changeCopyState;

  /// No description provided for @copyLockedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Checked-out or reserved copies must be changed via loans / holds'**
  String get copyLockedTooltip;

  /// No description provided for @copyStateUpdated.
  ///
  /// In en, this message translates to:
  /// **'Copy updated'**
  String get copyStateUpdated;

  /// No description provided for @addCopy.
  ///
  /// In en, this message translates to:
  /// **'Add copy'**
  String get addCopy;

  /// No description provided for @removeCopy.
  ///
  /// In en, this message translates to:
  /// **'Remove copy'**
  String get removeCopy;

  /// No description provided for @setCopyBarcode.
  ///
  /// In en, this message translates to:
  /// **'Set copy barcode'**
  String get setCopyBarcode;

  /// No description provided for @copyBarcodeSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get copyBarcodeSave;

  /// No description provided for @removeCopyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this physical copy? This cannot be undone.'**
  String get removeCopyConfirm;

  /// No description provided for @copyAdded.
  ///
  /// In en, this message translates to:
  /// **'Copy added'**
  String get copyAdded;

  /// No description provided for @copyRemoved.
  ///
  /// In en, this message translates to:
  /// **'Copy removed'**
  String get copyRemoved;

  /// No description provided for @copyBarcodeSaved.
  ///
  /// In en, this message translates to:
  /// **'Copy barcode updated'**
  String get copyBarcodeSaved;

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

  /// No description provided for @noConnectedDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices are connected right now.'**
  String get noConnectedDevices;

  /// No description provided for @noCopiesYet.
  ///
  /// In en, this message translates to:
  /// **'No copies recorded yet.'**
  String get noCopiesYet;

  /// No description provided for @memberIdAuto.
  ///
  /// In en, this message translates to:
  /// **'ID (auto-generated)'**
  String get memberIdAuto;

  /// No description provided for @memberIdCode.
  ///
  /// In en, this message translates to:
  /// **'ID / Code'**
  String get memberIdCode;

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

  /// No description provided for @activeLoans.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get activeLoans;

  /// No description provided for @noActiveLoans.
  ///
  /// In en, this message translates to:
  /// **'No active loans.'**
  String get noActiveLoans;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @renew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renew;

  /// No description provided for @renewSuccess.
  ///
  /// In en, this message translates to:
  /// **'Loan renewed successfully'**
  String get renewSuccess;

  /// No description provided for @colMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get colMember;

  /// No description provided for @colItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get colItem;

  /// No description provided for @loanDateCol.
  ///
  /// In en, this message translates to:
  /// **'Loan Date'**
  String get loanDateCol;

  /// No description provided for @dueDateCol.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get dueDateCol;

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

  /// No description provided for @configPrefixesLabel.
  ///
  /// In en, this message translates to:
  /// **'Code prefixes (LIV, REV, etc.)'**
  String get configPrefixesLabel;

  /// No description provided for @configPrefixesDesc.
  ///
  /// In en, this message translates to:
  /// **'Default values will be initialized.'**
  String get configPrefixesDesc;

  /// No description provided for @configAttributesLabel.
  ///
  /// In en, this message translates to:
  /// **'Dynamic attributes'**
  String get configAttributesLabel;

  /// No description provided for @configAttributesDesc.
  ///
  /// In en, this message translates to:
  /// **'Locations, statuses, and stocks.'**
  String get configAttributesDesc;

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

  /// No description provided for @updateNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Automatic update checking is not configured for this deployment.'**
  String get updateNotConfigured;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the update server. Please try again later.'**
  String get updateCheckFailed;

  /// No description provided for @updateFoundVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is now available.'**
  String updateFoundVersion(String version);

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

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check the connection and try again.'**
  String get errNetwork;

  /// No description provided for @errAuth.
  ///
  /// In en, this message translates to:
  /// **'This action requires administrator authentication.'**
  String get errAuth;

  /// No description provided for @errConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict: the record was changed by someone else or already exists.'**
  String get errConflict;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested record was not found.'**
  String get errNotFound;

  /// No description provided for @errBadRequest.
  ///
  /// In en, this message translates to:
  /// **'The request was rejected as invalid.'**
  String get errBadRequest;

  /// No description provided for @errServerError.
  ///
  /// In en, this message translates to:
  /// **'The server reported an error. Please try again.'**
  String get errServerError;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errGeneric;

  /// No description provided for @errServerNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'No LAN server has been set up on this PC.'**
  String get errServerNotInitialized;

  /// No description provided for @errServerStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The LAN server could not be started. Another program may already be using this port.'**
  String get errServerStartFailed;

  /// No description provided for @errHostOnlyFeature.
  ///
  /// In en, this message translates to:
  /// **'This is available only on the host PC (the one running the library).'**
  String get errHostOnlyFeature;

  /// No description provided for @usersAndRoles.
  ///
  /// In en, this message translates to:
  /// **'Users & Roles'**
  String get usersAndRoles;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get roleStaff;

  /// No description provided for @roleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get roleViewer;

  /// No description provided for @roleAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Full access, including user management and settings'**
  String get roleAdminDescription;

  /// No description provided for @roleStaffDescription.
  ///
  /// In en, this message translates to:
  /// **'Can borrow, return and edit catalogue, members and loans'**
  String get roleStaffDescription;

  /// No description provided for @roleViewerDescription.
  ///
  /// In en, this message translates to:
  /// **'Read-only: can look, cannot change anything'**
  String get roleViewerDescription;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {user} ({role})'**
  String signedInAs(String user, String role);

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccount;

  /// No description provided for @changeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get changeRole;

  /// No description provided for @removeAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the account \"{user}\"? Any device signed in with it will be disconnected.'**
  String removeAccountConfirm(String user);

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Use at least {n} characters.'**
  String passwordMinLength(int n);

  /// No description provided for @usernameRules.
  ///
  /// In en, this message translates to:
  /// **'3-32 characters: letters, digits, dot, underscore or hyphen; must start with a letter or digit; lowercase.'**
  String get usernameRules;

  /// No description provided for @onlyAdminManagesUsers.
  ///
  /// In en, this message translates to:
  /// **'Only an administrator can manage accounts and roles.'**
  String get onlyAdminManagesUsers;

  /// No description provided for @readOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'You are signed in with a read-only account. Editing is disabled.'**
  String get readOnlyMode;

  /// No description provided for @readAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the account list.'**
  String get readAccountFailed;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check the username and password.'**
  String get signInFailed;

  /// No description provided for @pairAsRole.
  ///
  /// In en, this message translates to:
  /// **'Grant this device the selected role when it pairs'**
  String get pairAsRole;

  /// No description provided for @readOnlyAccount.
  ///
  /// In en, this message translates to:
  /// **'Read-only account'**
  String get readOnlyAccount;

  /// No description provided for @noAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get noAccounts;

  /// No description provided for @fines.
  ///
  /// In en, this message translates to:
  /// **'Fines'**
  String get fines;

  /// No description provided for @fineNoFines.
  ///
  /// In en, this message translates to:
  /// **'No fines recorded'**
  String get fineNoFines;

  /// No description provided for @fineStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get fineStatusPending;

  /// No description provided for @fineStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get fineStatusPaid;

  /// No description provided for @fineStatusWaived.
  ///
  /// In en, this message translates to:
  /// **'Waived'**
  String get fineStatusWaived;

  /// No description provided for @fineCollectedBy.
  ///
  /// In en, this message translates to:
  /// **'Handled by'**
  String get fineCollectedBy;

  /// No description provided for @fineAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get fineAmountLabel;

  /// No description provided for @fineMemberLabel.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get fineMemberLabel;

  /// No description provided for @fineReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get fineReasonLabel;

  /// No description provided for @fineDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get fineDateLabel;

  /// No description provided for @fineStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get fineStatusLabel;

  /// No description provided for @fineCollect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get fineCollect;

  /// No description provided for @fineWaive.
  ///
  /// In en, this message translates to:
  /// **'Waive'**
  String get fineWaive;

  /// No description provided for @fineFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All fines'**
  String get fineFilterAll;

  /// No description provided for @fineOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding: {amount}'**
  String fineOutstanding(String amount);

  /// No description provided for @fineCollectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Record payment of {amount} for this fine?'**
  String fineCollectConfirm(String amount);

  /// No description provided for @fineWaiveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Waive this fine of {amount}? No money will be collected.'**
  String fineWaiveConfirm(String amount);

  /// No description provided for @finePolicy.
  ///
  /// In en, this message translates to:
  /// **'Fine policy'**
  String get finePolicy;

  /// No description provided for @fineRatePerDay.
  ///
  /// In en, this message translates to:
  /// **'Rate per overdue day'**
  String get fineRatePerDay;

  /// No description provided for @fineCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get fineCurrency;

  /// No description provided for @finePolicySaved.
  ///
  /// In en, this message translates to:
  /// **'Fine policy updated'**
  String get finePolicySaved;

  /// No description provided for @finePolicyDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Fines are disabled (rate 0). Set a rate to start charging overdue returns.'**
  String get finePolicyDisabledHint;

  /// No description provided for @fineSettled.
  ///
  /// In en, this message translates to:
  /// **'Fine updated'**
  String get fineSettled;

  /// No description provided for @finePolicyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set the overdue rate and currency (administrators only)'**
  String get finePolicyTooltip;

  /// No description provided for @onlyStaffManageFines.
  ///
  /// In en, this message translates to:
  /// **'Only staff can view or settle fines.'**
  String get onlyStaffManageFines;

  /// No description provided for @fineViewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load fines.'**
  String get fineViewFailed;

  /// No description provided for @reservations.
  ///
  /// In en, this message translates to:
  /// **'Reservations'**
  String get reservations;

  /// No description provided for @holdNoHolds.
  ///
  /// In en, this message translates to:
  /// **'No holds recorded'**
  String get holdNoHolds;

  /// No description provided for @holdStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'In line'**
  String get holdStatusQueued;

  /// No description provided for @holdStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get holdStatusAvailable;

  /// No description provided for @holdStatusFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get holdStatusFulfilled;

  /// No description provided for @holdStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get holdStatusCancelled;

  /// No description provided for @holdStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get holdStatusExpired;

  /// No description provided for @holdPlace.
  ///
  /// In en, this message translates to:
  /// **'Place hold'**
  String get holdPlace;

  /// No description provided for @holdCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get holdCancel;

  /// No description provided for @holdCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel the hold for {member} on {item}?'**
  String holdCancelConfirm(String member, String item);

  /// No description provided for @holdPlaced.
  ///
  /// In en, this message translates to:
  /// **'Hold placed'**
  String get holdPlaced;

  /// No description provided for @holdCancelled.
  ///
  /// In en, this message translates to:
  /// **'Hold cancelled'**
  String get holdCancelled;

  /// No description provided for @holdViewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load holds.'**
  String get holdViewFailed;

  /// No description provided for @holdPlaceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not place the hold.'**
  String get holdPlaceFailed;

  /// No description provided for @onlyStaffManageHolds.
  ///
  /// In en, this message translates to:
  /// **'Only staff can view or manage holds.'**
  String get onlyStaffManageHolds;

  /// No description provided for @holdFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All holds'**
  String get holdFilterAll;

  /// No description provided for @holdFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open holds'**
  String get holdFilterOpen;

  /// No description provided for @holdFilterReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get holdFilterReady;

  /// No description provided for @holdQueuePosition.
  ///
  /// In en, this message translates to:
  /// **'#{position} in line'**
  String holdQueuePosition(String position);

  /// No description provided for @holdPickupBy.
  ///
  /// In en, this message translates to:
  /// **'Pick up by {date}'**
  String holdPickupBy(String date);

  /// No description provided for @holdItemLabel.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get holdItemLabel;

  /// No description provided for @holdMemberLabel.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get holdMemberLabel;

  /// No description provided for @holdSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select an item'**
  String get holdSelectItem;

  /// No description provided for @holdSelectMember.
  ///
  /// In en, this message translates to:
  /// **'Select a member'**
  String get holdSelectMember;

  /// No description provided for @holdNeedSelection.
  ///
  /// In en, this message translates to:
  /// **'Choose both an item and a member.'**
  String get holdNeedSelection;

  /// No description provided for @holdNothingReady.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting for pickup'**
  String get holdNothingReady;

  /// No description provided for @holdPolicy.
  ///
  /// In en, this message translates to:
  /// **'Hold policy'**
  String get holdPolicy;

  /// No description provided for @holdPolicyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set the pickup window and queue cap (administrators only)'**
  String get holdPolicyTooltip;

  /// No description provided for @holdPolicySaved.
  ///
  /// In en, this message translates to:
  /// **'Hold policy updated'**
  String get holdPolicySaved;

  /// No description provided for @holdPickupDays.
  ///
  /// In en, this message translates to:
  /// **'Pickup window (days)'**
  String get holdPickupDays;

  /// No description provided for @holdQueueCap.
  ///
  /// In en, this message translates to:
  /// **'Max holds per title'**
  String get holdQueueCap;

  /// No description provided for @holdNoItems.
  ///
  /// In en, this message translates to:
  /// **'No catalogue items are loaded to place a hold.'**
  String get holdNoItems;

  /// No description provided for @holdNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No members are loaded to place a hold.'**
  String get holdNoMembers;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @reportSelectKind.
  ///
  /// In en, this message translates to:
  /// **'Report type'**
  String get reportSelectKind;

  /// No description provided for @reportKindCirculation.
  ///
  /// In en, this message translates to:
  /// **'Circulation'**
  String get reportKindCirculation;

  /// No description provided for @reportKindOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue items'**
  String get reportKindOverdue;

  /// No description provided for @reportKindInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get reportKindInventory;

  /// No description provided for @reportKindFines.
  ///
  /// In en, this message translates to:
  /// **'Fines'**
  String get reportKindFines;

  /// No description provided for @reportKindMembers.
  ///
  /// In en, this message translates to:
  /// **'Top borrowers'**
  String get reportKindMembers;

  /// No description provided for @reportRun.
  ///
  /// In en, this message translates to:
  /// **'Run report'**
  String get reportRun;

  /// No description provided for @reportFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get reportFrom;

  /// No description provided for @reportTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get reportTo;

  /// No description provided for @reportGeneratedLabel.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get reportGeneratedLabel;

  /// No description provided for @reportPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get reportPeriodLabel;

  /// No description provided for @reportDateHint.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD'**
  String get reportDateHint;

  /// No description provided for @reportWindowNote.
  ///
  /// In en, this message translates to:
  /// **'This report covers a date range.'**
  String get reportWindowNote;

  /// No description provided for @reportInvalidDates.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date (YYYY-MM-DD).'**
  String get reportInvalidDates;

  /// No description provided for @reportNoData.
  ///
  /// In en, this message translates to:
  /// **'No records for this report'**
  String get reportNoData;

  /// No description provided for @reportSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get reportSummary;

  /// No description provided for @reportGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated {when}'**
  String reportGeneratedAt(String when);

  /// No description provided for @reportExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get reportExportCsv;

  /// No description provided for @reportExportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get reportExportPdf;

  /// No description provided for @reportSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String reportSaved(String path);

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not run the report.'**
  String get reportFailed;

  /// No description provided for @reportExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the report.'**
  String get reportExportFailed;

  /// No description provided for @onlyStaffRunReports.
  ///
  /// In en, this message translates to:
  /// **'Only staff can run reports.'**
  String get onlyStaffRunReports;

  /// No description provided for @exportDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics'**
  String get exportDiagnostics;

  /// No description provided for @diagnosticsSaved.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics saved to {path}'**
  String diagnosticsSaved(String path);

  /// No description provided for @diagnosticsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export diagnostics.'**
  String get diagnosticsFailed;

  /// No description provided for @connectionMode.
  ///
  /// In en, this message translates to:
  /// **'Connection mode'**
  String get connectionMode;

  /// No description provided for @hostModeOption.
  ///
  /// In en, this message translates to:
  /// **'Host (main PC — server)'**
  String get hostModeOption;

  /// No description provided for @clientModeOption.
  ///
  /// In en, this message translates to:
  /// **'Client (staff PC)'**
  String get clientModeOption;

  /// No description provided for @hostIpLabel.
  ///
  /// In en, this message translates to:
  /// **'Host IP address'**
  String get hostIpLabel;

  /// No description provided for @hostIpHelper.
  ///
  /// In en, this message translates to:
  /// **'Enter the IP address of the main PC (e.g., 192.168.1.50)'**
  String get hostIpHelper;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceHint.
  ///
  /// In en, this message translates to:
  /// **'Theme and branding for this device. These are not shared with other PCs.'**
  String get appearanceHint;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'Brand name'**
  String get brandName;

  /// No description provided for @brandNameHint.
  ///
  /// In en, this message translates to:
  /// **'Product name shown in the title bar (administrators only)'**
  String get brandNameHint;

  /// No description provided for @featuresTitle.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get featuresTitle;

  /// No description provided for @featureFlagsHint.
  ///
  /// In en, this message translates to:
  /// **'Turn optional screens on or off. Changes apply immediately.'**
  String get featureFlagsHint;

  /// No description provided for @brandNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Brand name updated'**
  String get brandNameUpdated;

  /// No description provided for @commandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get commandPalette;

  /// No description provided for @paletteSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Type to search commands…'**
  String get paletteSearchHint;

  /// No description provided for @paletteNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get paletteNoMatches;

  /// No description provided for @systemHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'System health'**
  String get systemHealthTitle;

  /// No description provided for @healthAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get healthAppVersion;

  /// No description provided for @healthDatabaseSchema.
  ///
  /// In en, this message translates to:
  /// **'Database schema version'**
  String get healthDatabaseSchema;

  /// No description provided for @healthOperatingMode.
  ///
  /// In en, this message translates to:
  /// **'Operating mode'**
  String get healthOperatingMode;

  /// No description provided for @healthLanServer.
  ///
  /// In en, this message translates to:
  /// **'LAN server'**
  String get healthLanServer;

  /// No description provided for @healthServerRunning.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get healthServerRunning;

  /// No description provided for @healthServerStopped.
  ///
  /// In en, this message translates to:
  /// **'Not listening'**
  String get healthServerStopped;

  /// No description provided for @healthConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get healthConnection;

  /// No description provided for @healthConnectedClients.
  ///
  /// In en, this message translates to:
  /// **'Connected clients'**
  String get healthConnectedClients;

  /// No description provided for @healthClientCount.
  ///
  /// In en, this message translates to:
  /// **'{n} active'**
  String healthClientCount(int n);

  /// No description provided for @healthLastBackup.
  ///
  /// In en, this message translates to:
  /// **'Last backup'**
  String get healthLastBackup;

  /// No description provided for @healthNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get healthNever;

  /// No description provided for @healthBackupFresh.
  ///
  /// In en, this message translates to:
  /// **'Fresh'**
  String get healthBackupFresh;

  /// No description provided for @healthBackupStale.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get healthBackupStale;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notifNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention'**
  String get notifNone;

  /// No description provided for @notifLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get notifLoading;

  /// No description provided for @notifOverdue.
  ///
  /// In en, this message translates to:
  /// **'{n} overdue loan(s)'**
  String notifOverdue(int n);

  /// No description provided for @notifHoldsReady.
  ///
  /// In en, this message translates to:
  /// **'{n} hold(s) ready for pickup'**
  String notifHoldsReady(int n);

  /// No description provided for @notifFinesPending.
  ///
  /// In en, this message translates to:
  /// **'{n} fine(s) awaiting settlement'**
  String notifFinesPending(int n);

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Staff chat'**
  String get chat;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get chatInputHint;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get chatEmpty;

  /// No description provided for @chatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Chat is unavailable right now.'**
  String get chatUnavailable;

  /// No description provided for @helpVersionFooter.
  ///
  /// In en, this message translates to:
  /// **'Library Manager v{version}'**
  String helpVersionFooter(String version);

  /// No description provided for @settingsCatGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsCatGeneral;

  /// No description provided for @settingsCatLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get settingsCatLibrary;

  /// No description provided for @settingsCatData.
  ///
  /// In en, this message translates to:
  /// **'Data & Backup'**
  String get settingsCatData;

  /// No description provided for @settingsCatSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsCatSecurity;

  /// No description provided for @settingsCatAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsCatAdvanced;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// No description provided for @settingsUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get settingsUnsaved;

  /// No description provided for @settingsRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get settingsRevert;

  /// No description provided for @memberDetail.
  ///
  /// In en, this message translates to:
  /// **'Member Profile'**
  String get memberDetail;

  /// No description provided for @memberNotFound.
  ///
  /// In en, this message translates to:
  /// **'Member not found'**
  String get memberNotFound;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registered;

  /// No description provided for @memberLoans.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get memberLoans;

  /// No description provided for @memberOverdueAlert.
  ///
  /// In en, this message translates to:
  /// **'{n} overdue item(s) need attention'**
  String memberOverdueAlert(int n);

  /// No description provided for @noLoansForMember.
  ///
  /// In en, this message translates to:
  /// **'No loans for this member'**
  String get noLoansForMember;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get dueDate;

  /// No description provided for @renewLoan.
  ///
  /// In en, this message translates to:
  /// **'Renew this loan'**
  String get renewLoan;

  /// No description provided for @memberFines.
  ///
  /// In en, this message translates to:
  /// **'Fines'**
  String get memberFines;

  /// No description provided for @finePending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get finePending;

  /// No description provided for @noPendingFines.
  ///
  /// In en, this message translates to:
  /// **'No pending fines'**
  String get noPendingFines;

  /// No description provided for @memberReservations.
  ///
  /// In en, this message translates to:
  /// **'Reservations'**
  String get memberReservations;

  /// No description provided for @noActiveReservations.
  ///
  /// In en, this message translates to:
  /// **'No active reservations'**
  String get noActiveReservations;

  /// No description provided for @holdReadyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get holdReadyForPickup;

  /// No description provided for @holdQueued.
  ///
  /// In en, this message translates to:
  /// **'In queue'**
  String get holdQueued;

  /// No description provided for @statusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get statusAvailable;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @checkoutAction.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkoutAction;

  /// No description provided for @reserveAction.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get reserveAction;

  /// No description provided for @copiesAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'{a} of {t} copies available'**
  String copiesAvailableLabel(int a, int t);

  /// No description provided for @noCopiesAvailableForCheckout.
  ///
  /// In en, this message translates to:
  /// **'No copies currently available for checkout.'**
  String get noCopiesAvailableForCheckout;

  /// No description provided for @reserveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Reservation placed.'**
  String get reserveSuccess;

  /// No description provided for @noMembersMatchSearch.
  ///
  /// In en, this message translates to:
  /// **'No members match your search.'**
  String get noMembersMatchSearch;

  /// No description provided for @paginationSummary.
  ///
  /// In en, this message translates to:
  /// **'Showing {from}–{to} of {total} items'**
  String paginationSummary(int from, int to, int total);

  /// No description provided for @keyboardShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcutsTitle;

  /// No description provided for @keyboardShortcutsContent.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+K opens the command palette. Enter runs the top result. Esc closes dialogs. Tab moves between fields; arrow keys navigate lists.'**
  String get keyboardShortcutsContent;

  /// No description provided for @historySubjectPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Filter by code or member ID...'**
  String get historySubjectPlaceholder;

  /// No description provided for @seeAllHistory.
  ///
  /// In en, this message translates to:
  /// **'See all history'**
  String get seeAllHistory;

  /// No description provided for @noHistoryForRecord.
  ///
  /// In en, this message translates to:
  /// **'No recent activity for this record.'**
  String get noHistoryForRecord;

  /// No description provided for @queueMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up in queue'**
  String get queueMoveUp;

  /// No description provided for @queueMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down in queue'**
  String get queueMoveDown;

  /// No description provided for @queueOrderByItem.
  ///
  /// In en, this message translates to:
  /// **'Filter by item to reorder the queue'**
  String get queueOrderByItem;

  /// No description provided for @queueMoved.
  ///
  /// In en, this message translates to:
  /// **'Queue order updated.'**
  String get queueMoved;

  /// No description provided for @queueMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reorder the queue.'**
  String get queueMoveFailed;

  /// No description provided for @navCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse menu'**
  String get navCollapse;

  /// No description provided for @navExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand menu'**
  String get navExpand;

  /// No description provided for @deleteMember.
  ///
  /// In en, this message translates to:
  /// **'Delete Member'**
  String get deleteMember;

  /// No description provided for @confirmDeleteMember.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this member? Their loans and holds must be settled first.'**
  String get confirmDeleteMember;

  /// No description provided for @confirmDeleteItemNamed.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this item ({item})?'**
  String confirmDeleteItemNamed(String item);

  /// No description provided for @reportGeneratedOn.
  ///
  /// In en, this message translates to:
  /// **'Generated {when}'**
  String reportGeneratedOn(String when);

  /// No description provided for @userJoinedOn.
  ///
  /// In en, this message translates to:
  /// **'Joined {when}'**
  String userJoinedOn(String when);

  /// No description provided for @noNamedAccounts.
  ///
  /// In en, this message translates to:
  /// **'No named accounts yet'**
  String get noNamedAccounts;

  /// No description provided for @noNamedAccountsHint.
  ///
  /// In en, this message translates to:
  /// **'You are signed in as the built-in administrator. Create staff or viewer accounts below to grant scoped access to other users.'**
  String get noNamedAccountsHint;
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
