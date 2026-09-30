// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Library Manager';

  @override
  String get items => 'Items';

  @override
  String get addItem => 'Add Item';

  @override
  String get editItem => 'Edit Item';

  @override
  String get deleteItem => 'Delete Item';

  @override
  String get code => 'Code';

  @override
  String get designation => 'Designation';

  @override
  String get quantity => 'Quantity';

  @override
  String get location => 'Location';

  @override
  String get rate => 'Rate';

  @override
  String get stockLocation => 'Stock Location';

  @override
  String get stock => 'Stock';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmDelete => 'Are you sure you want to delete this item?';

  @override
  String get search => 'Search...';

  @override
  String get language => 'Language';

  @override
  String get generateReport => 'Generate Report';

  @override
  String get codeRequired => 'Code is required';

  @override
  String get designationRequired => 'Designation is required';

  @override
  String get wholeNumberRequired => 'Whole number required';

  @override
  String get numberRequired => 'Number required';

  @override
  String get mustBeNonNegative => 'Must be greater than or equal to 0';

  @override
  String get newValue => 'New Value';

  @override
  String get attributeOptionsNote =>
      'These options appear in the dropdowns when adding or editing a book.';

  @override
  String get usbScannerNote => 'USB scanners act as keyboards. Just scan!';

  @override
  String get settings => 'Settings';

  @override
  String get inventory => 'Inventory';

  @override
  String get fullCodeLabel => 'Full Code';

  @override
  String get typeLabel => 'Type';

  @override
  String get nationalLibrary => 'National Library';

  @override
  String get algerianSystem => 'Algerian Management System';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get addNewBook => 'New Book';

  @override
  String get refreshData => 'Refresh';

  @override
  String get status => 'Status';

  @override
  String get actions => 'Actions';

  @override
  String get dataProtection => 'Data Protection';

  @override
  String get backupDatabase => 'Backup Database';

  @override
  String get selectBackupDatabase => 'Select Backup Database';

  @override
  String get restoreDatabase => 'Restore Database';

  @override
  String get manageVariables => 'Manage Variables';

  @override
  String get manageAttributes => 'Manage Attributes';

  @override
  String get variablesTitle => 'Variables & Attributes';

  @override
  String get manageVariablesDescription =>
      'Modify code prefixes and system categories (LIV, REV, etc.)';

  @override
  String get manageAttributesDescription =>
      'Modify lookups for Locations, Statuses, and Stock Locations';

  @override
  String get backupDescription => 'Create a copy of your database';

  @override
  String get restoreDescription => 'Restore data from a backup file';

  @override
  String get security => 'Security';

  @override
  String get adminPassword => 'Admin Password';

  @override
  String get changePassword => 'Change password';

  @override
  String get newPassword => 'New password';

  @override
  String get wrongPassword => 'Wrong Password';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get dangerZone => 'Danger Zone';

  @override
  String get eraseAllData => 'Erase All Database';

  @override
  String get eraseWarning =>
      'WARNING: This will permanently delete all items and reset settings. This action cannot be undone.';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get reconnecting => 'Reconnecting…';

  @override
  String get connectionType => 'Connection Type';

  @override
  String get hostMode => 'Server (Host)';

  @override
  String get clientMode => 'Client';

  @override
  String get enterPassword => 'Enter Admin Password';

  @override
  String get historyTitle => 'Operation History';

  @override
  String get filter => 'Filter';

  @override
  String get all => 'All';

  @override
  String get operationAdd => 'Add';

  @override
  String get operationUpdate => 'Update';

  @override
  String get operationDelete => 'Delete';

  @override
  String get operationWipe => 'Reset';

  @override
  String get noHistoryFound => 'No history items found';

  @override
  String get by => 'By';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get confirmNewPassword => 'Confirm New Password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordUpdated => 'Password updated successfully';

  @override
  String get minPasswordLength => 'Minimum 4 characters';

  @override
  String get unlockSettings => 'Unlock edit (requires password)';

  @override
  String get showActionsLog => 'View operation history';

  @override
  String get dataWiped => 'All data has been erased';

  @override
  String get validate => 'Validate';

  @override
  String get allStatuses => 'All Statuses';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get priceDzd => 'Price (DZD)';

  @override
  String get loadMore => 'Load More Items';

  @override
  String get serverModeName => 'Server Mode';

  @override
  String get clientModeName => 'Client Mode';

  @override
  String get totalDocuments => 'Total Documents';

  @override
  String get inventoryValue => 'Inventory Value';

  @override
  String get onLoan => 'On Loan';

  @override
  String get historyAction => 'History';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get exportSuccess => 'Exported successfully';

  @override
  String get exportError => 'Export error';

  @override
  String get allTypes => 'All Types';

  @override
  String get noItemsFound => 'No items found';

  @override
  String get backupSuccess => 'Backup created successfully!';

  @override
  String get backupFailed => 'Backup failed.';

  @override
  String get restoreFailed => 'Restore failed.';

  @override
  String get retry => 'Retry';

  @override
  String get noPhone => 'No phone';

  @override
  String scannerError(String code) {
    return 'Scanner error: $code';
  }

  @override
  String selectedItemLabel(String name, String status) {
    return 'Selected: $name ($status)';
  }

  @override
  String get restoreSuccess => 'Database restored successfully!';

  @override
  String get setPassword => 'Set a password';

  @override
  String get importExcel => 'Import from Excel (.xlsx)';

  @override
  String get importSuccess => 'Data imported successfully!';

  @override
  String get importError => 'Import failed: ';

  @override
  String get scanBarcode => 'Scan Barcode';

  @override
  String get cameraPermissionRequired =>
      'Camera permission is required to scan barcodes.';

  @override
  String get cameraPermissionDenied => 'Camera permission was denied.';

  @override
  String get barcode => 'Barcode (ISBN/EAN)';

  @override
  String get barcodeHint => 'Scan or enter barcode';

  @override
  String get autoGenerated => 'Auto-generated';

  @override
  String get required => 'Required';

  @override
  String get statusDisponible => 'Available';

  @override
  String get statusEmprunte => 'Borrowed';

  @override
  String get statusReserve => 'Reserved';

  @override
  String get statusEndommage => 'Damaged';

  @override
  String get statusEnReparation => 'In repair';

  @override
  String get statusPerdu => 'Lost';

  @override
  String get statusArchive => 'Archived';

  @override
  String get itemCopies => 'Copies';

  @override
  String copyNumberLabel(int n) {
    return 'Copy $n';
  }

  @override
  String get copyBarcodeMissing => 'No copy barcode';

  @override
  String get changeCopyState => 'Change condition';

  @override
  String get copyLockedTooltip =>
      'Checked-out or reserved copies must be changed via loans / holds';

  @override
  String get copyStateUpdated => 'Copy updated';

  @override
  String get addCopy => 'Add copy';

  @override
  String get removeCopy => 'Remove copy';

  @override
  String get setCopyBarcode => 'Set copy barcode';

  @override
  String get copyBarcodeSave => 'Save';

  @override
  String get removeCopyConfirm =>
      'Remove this physical copy? This cannot be undone.';

  @override
  String get copyAdded => 'Copy added';

  @override
  String get copyRemoved => 'Copy removed';

  @override
  String get copyBarcodeSaved => 'Copy barcode updated';

  @override
  String get itemProfile => 'Item Profile';

  @override
  String get itemDetails => 'Item Details';

  @override
  String get editItemDetails => 'Edit Details';

  @override
  String get locationInfo => 'Location Info';

  @override
  String get pricingInfo => 'Pricing Info';

  @override
  String get technicalInfo => 'Technical Info';

  @override
  String get markAsAvailable => 'Mark as Available';

  @override
  String get markAsBorrowed => 'Mark as Borrowed';

  @override
  String get markAsReserved => 'Mark as Reserved';

  @override
  String get markAsDamaged => 'Mark as Damaged';

  @override
  String get prefix => 'Prefix';

  @override
  String get prefixHint => '3-4 letters (e.g., LIV, ARCH)';

  @override
  String get label => 'Label';

  @override
  String get labelHint => 'Label (e.g., Book, Archives)';

  @override
  String get saveDefinition => 'Save Variable';

  @override
  String get cancelEdit => 'Cancel Edit';

  @override
  String get confirmDeleteDefinition => 'Delete Variable?';

  @override
  String get deleteDefinitionWarning =>
      'Are you sure you want to delete this variable? Existing items will remain but filtering might be affected.';

  @override
  String get notePrefixChange =>
      'Note: Changing a prefix will update all linked items.';

  @override
  String get addVariable => 'Add Variable';

  @override
  String get updateVariable => 'Update';

  @override
  String get newVariable => 'New Variable';

  @override
  String get editVariable => 'Edit Variable';

  @override
  String get savedSuccessfully => 'Saved successfully';

  @override
  String get pairingCode => 'Pairing Code';

  @override
  String get scanServerCode => 'Scan Server Code';

  @override
  String get scanServerDescription =>
      'Connect automatically by scanning the QR code on the host screen.';

  @override
  String get pairingCodeDescription =>
      'Allow clients to connect by scanning this code.';

  @override
  String get enterPairingCode => 'Enter Pairing Code';

  @override
  String get enterPairingCodeDescription =>
      'Connect without a camera by typing the 6-digit code from the Host.';

  @override
  String get pairingSearching => 'Searching for host on the LAN...';

  @override
  String get pairingIpSet => 'Host found. Connection configured.';

  @override
  String get pairingHostNotFound =>
      'No host found. Check the code and that both devices are on the same LAN.';

  @override
  String pairingValidMinutes(int minutes) {
    return 'Valid for about $minutes min';
  }

  @override
  String get connectedDevices => 'Connected Devices';

  @override
  String get connectedViaLan => 'Connected via LAN';

  @override
  String get noConnectedDevices => 'No devices are connected right now.';

  @override
  String get noCopiesYet => 'No copies recorded yet.';

  @override
  String get memberIdAuto => 'ID (auto-generated)';

  @override
  String get memberIdCode => 'ID / Code';

  @override
  String get scanWithUsbOrType => 'Use a USB Scanner or type code';

  @override
  String get scanOrTypeHint => 'Scan code or type here...';

  @override
  String get requiredField => 'Required field';

  @override
  String get members => 'Members';

  @override
  String get loans => 'Loans';

  @override
  String get memberManagement => 'Member Management';

  @override
  String get loanManagement => 'Loan Management';

  @override
  String get newLoan => 'New Loan';

  @override
  String get returnLoan => 'Return';

  @override
  String get selectMember => '1. Select Member';

  @override
  String get selectItem => '2. Select Item';

  @override
  String get validateLoan => 'Validate Loan';

  @override
  String get memberSearchHint => 'Search Member (Name or ID)';

  @override
  String get itemSearchHint => 'Barcode or Title';

  @override
  String get loanSuccess => 'Loan recorded successfully';

  @override
  String get returnSuccess => 'Return recorded successfully';

  @override
  String get addMember => 'Add Member';

  @override
  String get editMember => 'Edit Member';

  @override
  String get firstName => 'First Name';

  @override
  String get lastName => 'Last Name';

  @override
  String get phone => 'Phone';

  @override
  String get email => 'Email';

  @override
  String get scanToReturn => 'Scan item to return';

  @override
  String get confirmReturn => 'Confirm Return';

  @override
  String get itemNotFound => 'Item not found';

  @override
  String get itemNotAvailable => 'Item is not available.';

  @override
  String get noActiveLoan => 'No active loan found for this item.';

  @override
  String get activeLoans => 'Active Loans';

  @override
  String get noActiveLoans => 'No active loans.';

  @override
  String get overdue => 'Overdue';

  @override
  String get renew => 'Renew';

  @override
  String get renewSuccess => 'Loan renewed successfully';

  @override
  String get colMember => 'Member';

  @override
  String get colItem => 'Item';

  @override
  String get loanDateCol => 'Loan Date';

  @override
  String get dueDateCol => 'Due Date';

  @override
  String get selectCamera => 'Select Camera';

  @override
  String get cameraFront => 'Front Camera';

  @override
  String get cameraBack => 'Back Camera';

  @override
  String get cameraExternal => 'External Camera (USB)';

  @override
  String get cameraUnknown => 'Camera';

  @override
  String get flash => 'Flash';

  @override
  String get switchCamera => 'Switch';

  @override
  String get cameras => 'Cameras';

  @override
  String get helpCenter => 'Help Center';

  @override
  String get setupRoadmap => 'Setup Roadmap';

  @override
  String get welcome => 'Welcome';

  @override
  String get getStarted => 'Get Started';

  @override
  String get next => 'Next';

  @override
  String get finish => 'Finish';

  @override
  String get stepLanguage => 'Language';

  @override
  String get stepSecurity => 'Security';

  @override
  String get stepConfiguration => 'Configuration';

  @override
  String get setupLanguageDesc =>
      'Choose your preferred language for the application.';

  @override
  String get setupPasswordDesc =>
      'Set an administrative password to protect your data.';

  @override
  String get setupConfigDesc =>
      'Configure basic library prefixes and attributes.';

  @override
  String get configPrefixesLabel => 'Code prefixes (LIV, REV, etc.)';

  @override
  String get configPrefixesDesc => 'Default values will be initialized.';

  @override
  String get configAttributesLabel => 'Dynamic attributes';

  @override
  String get configAttributesDesc => 'Locations, statuses, and stocks.';

  @override
  String get setupComplete => 'Setup Complete!';

  @override
  String get setupCompleteDesc =>
      'You are now ready to use the Library Management System.';

  @override
  String get helpMembersTitle => 'Member Management';

  @override
  String get helpMembersContent =>
      '1. Go to the \'Members\' tab to add or edit registered users.\n2. Each member is assigned a unique ID (e.g., 260001) formatted for national registration.\n3. Track loan history, active borrows, and registration dates per member.';

  @override
  String get helpLoansTitle => 'Loan System';

  @override
  String get helpLoansContent =>
      '1. Scanning an item in the \'Loans\' screen starts the checkout process.\n2. Enter the member ID or scan their membership card to link the loan.\n3. Return items by scanning them again in the \'Prêts\' section or manually marking them as returned in history.';

  @override
  String get helpSyncTitle => 'LAN Synchronization';

  @override
  String get helpSyncContent =>
      '1. One machine must be set as the \'Host\' (Server) while others are \'Clients\'.\n2. Clients connect using the Host\'s IP address. Pair automatically by scanning the Host\'s sync QR code.\n3. Changes on any device are mirrored to the server via local network protocols.';

  @override
  String get helpBarcodeTitle => 'Barcode Scanning';

  @override
  String get helpBarcodeContent =>
      '1. Integrated Camera: Supports front/back/external camera toggling with LED flash support.\n2. USB Scanners: Plug-and-play support in any search field.\n3. Multiple Devices: Switch between available cameras using the device selection dropdown in the scanner window.';

  @override
  String get documentation => 'Documentation and guides';

  @override
  String get resetOnboarding => 'Reset Setup Roadmap';

  @override
  String get resetOnboardingDesc =>
      'Reset onboarding and setup roadmap (Testing only)';

  @override
  String get resetRestartApp => 'Setup roadmap reset. Restart the app.';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String get noUpdateAvailable => 'You are using the latest version.';

  @override
  String get updateNow => 'Update Now';

  @override
  String get updateNotConfigured =>
      'Automatic update checking is not configured for this deployment.';

  @override
  String get updateCheckFailed =>
      'Could not reach the update server. Please try again later.';

  @override
  String updateFoundVersion(String version) {
    return 'Version $version is now available.';
  }

  @override
  String get enableLanAccess => 'Enable LAN Access';

  @override
  String get enableLanAccessDescription =>
      'Allow other PCs to connect by adding Windows Firewall rules (requires Admin).';

  @override
  String get lanAccessEnabled => 'LAN access enabled.';

  @override
  String get lanAccessFailed =>
      'Failed to add firewall rules. Please approve the Admin prompt.';

  @override
  String get quickScan => 'Quick Scan';

  @override
  String get appDefinitionTitle => 'What is Library Manager?';

  @override
  String get appDefinitionContent =>
      'Library Manager is a professional desktop solution designed for Algerian libraries and documentation centers. It provides specialized tools for inventory management, LAN-based synchronization, and barcode tracking. The system supports full English, French, and Arabic categorization following national standards.';

  @override
  String get errNetwork =>
      'Cannot reach the server. Check the connection and try again.';

  @override
  String get errAuth => 'This action requires administrator authentication.';

  @override
  String get errConflict =>
      'Conflict: the record was changed by someone else or already exists.';

  @override
  String get errNotFound => 'The requested record was not found.';

  @override
  String get errBadRequest => 'The request was rejected as invalid.';

  @override
  String get errServerError =>
      'The server reported an error. Please try again.';

  @override
  String get errGeneric => 'Something went wrong. Please try again.';

  @override
  String get errServerNotInitialized =>
      'No LAN server has been set up on this PC.';

  @override
  String get errServerStartFailed =>
      'The LAN server could not be started. Another program may already be using this port.';

  @override
  String get errHostOnlyFeature =>
      'This is available only on the host PC (the one running the library).';

  @override
  String get usersAndRoles => 'Users & Roles';

  @override
  String get account => 'Account';

  @override
  String get role => 'Role';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleStaff => 'Staff';

  @override
  String get roleViewer => 'Viewer';

  @override
  String get roleAdminDescription =>
      'Full access, including user management and settings';

  @override
  String get roleStaffDescription =>
      'Can borrow, return and edit catalogue, members and loans';

  @override
  String get roleViewerDescription =>
      'Read-only: can look, cannot change anything';

  @override
  String signedInAs(String user, String role) {
    return 'Signed in as $user ($role)';
  }

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get createAccount => 'Create account';

  @override
  String get removeAccount => 'Remove account';

  @override
  String get changeRole => 'Change role';

  @override
  String removeAccountConfirm(String user) {
    return 'Remove the account \"$user\"? Any device signed in with it will be disconnected.';
  }

  @override
  String passwordMinLength(int n) {
    return 'Use at least $n characters.';
  }

  @override
  String get usernameRules =>
      '3-32 characters: letters, digits, dot, underscore or hyphen; must start with a letter or digit; lowercase.';

  @override
  String get onlyAdminManagesUsers =>
      'Only an administrator can manage accounts and roles.';

  @override
  String get readOnlyMode =>
      'You are signed in with a read-only account. Editing is disabled.';

  @override
  String get readAccountFailed => 'Could not load the account list.';

  @override
  String get signInFailed => 'Sign-in failed. Check the username and password.';

  @override
  String get pairAsRole => 'Grant this device the selected role when it pairs';

  @override
  String get readOnlyAccount => 'Read-only account';

  @override
  String get noAccounts => 'No accounts yet';

  @override
  String get fines => 'Fines';

  @override
  String get fineNoFines => 'No fines recorded';

  @override
  String get fineStatusPending => 'Pending';

  @override
  String get fineStatusPaid => 'Paid';

  @override
  String get fineStatusWaived => 'Waived';

  @override
  String get fineCollectedBy => 'Handled by';

  @override
  String get fineAmountLabel => 'Amount';

  @override
  String get fineMemberLabel => 'Member';

  @override
  String get fineReasonLabel => 'Reason';

  @override
  String get fineDateLabel => 'Date';

  @override
  String get fineStatusLabel => 'Status';

  @override
  String get fineCollect => 'Collect';

  @override
  String get fineWaive => 'Waive';

  @override
  String get fineFilterAll => 'All fines';

  @override
  String fineOutstanding(String amount) {
    return 'Outstanding: $amount';
  }

  @override
  String fineCollectConfirm(String amount) {
    return 'Record payment of $amount for this fine?';
  }

  @override
  String fineWaiveConfirm(String amount) {
    return 'Waive this fine of $amount? No money will be collected.';
  }

  @override
  String get finePolicy => 'Fine policy';

  @override
  String get fineRatePerDay => 'Rate per overdue day';

  @override
  String get fineCurrency => 'Currency';

  @override
  String get finePolicySaved => 'Fine policy updated';

  @override
  String get finePolicyDisabledHint =>
      'Fines are disabled (rate 0). Set a rate to start charging overdue returns.';

  @override
  String get fineSettled => 'Fine updated';

  @override
  String get finePolicyTooltip =>
      'Set the overdue rate and currency (administrators only)';

  @override
  String get onlyStaffManageFines => 'Only staff can view or settle fines.';

  @override
  String get fineViewFailed => 'Could not load fines.';

  @override
  String get reservations => 'Reservations';

  @override
  String get holdNoHolds => 'No holds recorded';

  @override
  String get holdStatusQueued => 'In line';

  @override
  String get holdStatusAvailable => 'Ready for pickup';

  @override
  String get holdStatusFulfilled => 'Collected';

  @override
  String get holdStatusCancelled => 'Cancelled';

  @override
  String get holdStatusExpired => 'Expired';

  @override
  String get holdPlace => 'Place hold';

  @override
  String get holdCancel => 'Cancel';

  @override
  String holdCancelConfirm(String member, String item) {
    return 'Cancel the hold for $member on $item?';
  }

  @override
  String get holdPlaced => 'Hold placed';

  @override
  String get holdCancelled => 'Hold cancelled';

  @override
  String get holdViewFailed => 'Could not load holds.';

  @override
  String get holdPlaceFailed => 'Could not place the hold.';

  @override
  String get onlyStaffManageHolds => 'Only staff can view or manage holds.';

  @override
  String get holdFilterAll => 'All holds';

  @override
  String get holdFilterOpen => 'Open holds';

  @override
  String get holdFilterReady => 'Ready for pickup';

  @override
  String holdQueuePosition(String position) {
    return '#$position in line';
  }

  @override
  String holdPickupBy(String date) {
    return 'Pick up by $date';
  }

  @override
  String get holdItemLabel => 'Item';

  @override
  String get holdMemberLabel => 'Member';

  @override
  String get holdSelectItem => 'Select an item';

  @override
  String get holdSelectMember => 'Select a member';

  @override
  String get holdNeedSelection => 'Choose both an item and a member.';

  @override
  String get holdNothingReady => 'Nothing is waiting for pickup';

  @override
  String get holdPolicy => 'Hold policy';

  @override
  String get holdPolicyTooltip =>
      'Set the pickup window and queue cap (administrators only)';

  @override
  String get holdPolicySaved => 'Hold policy updated';

  @override
  String get holdPickupDays => 'Pickup window (days)';

  @override
  String get holdQueueCap => 'Max holds per title';

  @override
  String get holdNoItems => 'No catalogue items are loaded to place a hold.';

  @override
  String get holdNoMembers => 'No members are loaded to place a hold.';

  @override
  String get reports => 'Reports';

  @override
  String get reportSelectKind => 'Report type';

  @override
  String get reportKindCirculation => 'Circulation';

  @override
  String get reportKindOverdue => 'Overdue items';

  @override
  String get reportKindInventory => 'Inventory';

  @override
  String get reportKindFines => 'Fines';

  @override
  String get reportKindMembers => 'Top borrowers';

  @override
  String get reportRun => 'Run report';

  @override
  String get reportFrom => 'From';

  @override
  String get reportTo => 'To';

  @override
  String get reportGeneratedLabel => 'Generated';

  @override
  String get reportPeriodLabel => 'Period';

  @override
  String get reportDateHint => 'YYYY-MM-DD';

  @override
  String get reportWindowNote => 'This report covers a date range.';

  @override
  String get reportInvalidDates => 'Enter a valid date (YYYY-MM-DD).';

  @override
  String get reportNoData => 'No records for this report';

  @override
  String get reportSummary => 'Summary';

  @override
  String reportGeneratedAt(String when) {
    return 'Generated $when';
  }

  @override
  String get reportExportCsv => 'Export CSV';

  @override
  String get reportExportPdf => 'Export PDF';

  @override
  String reportSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String get reportFailed => 'Could not run the report.';

  @override
  String get reportExportFailed => 'Could not export the report.';

  @override
  String get onlyStaffRunReports => 'Only staff can run reports.';

  @override
  String get exportDiagnostics => 'Export diagnostics';

  @override
  String diagnosticsSaved(String path) {
    return 'Diagnostics saved to $path';
  }

  @override
  String get diagnosticsFailed => 'Could not export diagnostics.';

  @override
  String get connectionMode => 'Connection mode';

  @override
  String get hostModeOption => 'Host (main PC — server)';

  @override
  String get clientModeOption => 'Client (staff PC)';

  @override
  String get hostIpLabel => 'Host IP address';

  @override
  String get hostIpHelper =>
      'Enter the IP address of the main PC (e.g., 192.168.1.50)';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceHint =>
      'Theme and branding for this device. These are not shared with other PCs.';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accentColor => 'Accent color';

  @override
  String get brandName => 'Brand name';

  @override
  String get brandNameHint =>
      'Product name shown in the title bar (administrators only)';

  @override
  String get featuresTitle => 'Features';

  @override
  String get featureFlagsHint =>
      'Turn optional screens on or off. Changes apply immediately.';

  @override
  String get brandNameUpdated => 'Brand name updated';

  @override
  String get commandPalette => 'Command palette';

  @override
  String get paletteSearchHint => 'Type to search commands…';

  @override
  String get paletteNoMatches => 'No matching commands';

  @override
  String get systemHealthTitle => 'System health';

  @override
  String get healthAppVersion => 'App version';

  @override
  String get healthDatabaseSchema => 'Database schema version';

  @override
  String get healthOperatingMode => 'Operating mode';

  @override
  String get healthLanServer => 'LAN server';

  @override
  String get healthServerRunning => 'Listening';

  @override
  String get healthServerStopped => 'Not listening';

  @override
  String get healthConnection => 'Connection';

  @override
  String get healthConnectedClients => 'Connected clients';

  @override
  String healthClientCount(int n) {
    return '$n active';
  }

  @override
  String get healthLastBackup => 'Last backup';

  @override
  String get healthNever => 'Never';

  @override
  String get healthBackupFresh => 'Fresh';

  @override
  String get healthBackupStale => 'Overdue';

  @override
  String get notifications => 'Notifications';

  @override
  String get notifNone => 'Nothing needs attention';

  @override
  String get notifLoading => 'Checking…';

  @override
  String notifOverdue(int n) {
    return '$n overdue loan(s)';
  }

  @override
  String notifHoldsReady(int n) {
    return '$n hold(s) ready for pickup';
  }

  @override
  String notifFinesPending(int n) {
    return '$n fine(s) awaiting settlement';
  }

  @override
  String get chat => 'Staff chat';

  @override
  String get chatInputHint => 'Message…';

  @override
  String get chatSend => 'Send';

  @override
  String get chatEmpty => 'No messages yet.';

  @override
  String get chatUnavailable => 'Chat is unavailable right now.';

  @override
  String helpVersionFooter(String version) {
    return 'Library Manager v$version';
  }

  @override
  String get settingsCatGeneral => 'General';

  @override
  String get settingsCatLibrary => 'Library';

  @override
  String get settingsCatData => 'Data & Backup';

  @override
  String get settingsCatSecurity => 'Security';

  @override
  String get settingsCatAdvanced => 'Advanced';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String get settingsUnsaved => 'Unsaved changes';

  @override
  String get settingsRevert => 'Revert';

  @override
  String get memberDetail => 'Member Profile';

  @override
  String get memberNotFound => 'Member not found';

  @override
  String get registered => 'Registered';

  @override
  String get memberLoans => 'Active Loans';

  @override
  String memberOverdueAlert(int n) {
    return '$n overdue item(s) need attention';
  }

  @override
  String get noLoansForMember => 'No loans for this member';

  @override
  String get dueDate => 'Due';

  @override
  String get renewLoan => 'Renew this loan';

  @override
  String get memberFines => 'Fines';

  @override
  String get finePending => 'Pending';

  @override
  String get noPendingFines => 'No pending fines';

  @override
  String get memberReservations => 'Reservations';

  @override
  String get noActiveReservations => 'No active reservations';

  @override
  String get holdReadyForPickup => 'Ready for pickup';

  @override
  String get holdQueued => 'In queue';

  @override
  String get statusAvailable => 'Available';

  @override
  String get statusQueued => 'Queued';

  @override
  String get needsAttention => 'Needs attention';

  @override
  String get checkoutAction => 'Checkout';

  @override
  String get reserveAction => 'Reserve';

  @override
  String copiesAvailableLabel(int a, int t) {
    return '$a of $t copies available';
  }

  @override
  String get noCopiesAvailableForCheckout =>
      'No copies currently available for checkout.';

  @override
  String get reserveSuccess => 'Reservation placed.';

  @override
  String get noMembersMatchSearch => 'No members match your search.';

  @override
  String paginationSummary(int from, int to, int total) {
    return 'Showing $from–$to of $total items';
  }

  @override
  String get keyboardShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsContent =>
      'Ctrl+K opens the command palette. Enter runs the top result. Esc closes dialogs. Tab moves between fields; arrow keys navigate lists.';

  @override
  String get historySubjectPlaceholder => 'Filter by code or member ID...';

  @override
  String get seeAllHistory => 'See all history';

  @override
  String get noHistoryForRecord => 'No recent activity for this record.';

  @override
  String get queueMoveUp => 'Move up in queue';

  @override
  String get queueMoveDown => 'Move down in queue';

  @override
  String get queueOrderByItem => 'Filter by item to reorder the queue';

  @override
  String get queueMoved => 'Queue order updated.';

  @override
  String get queueMoveFailed => 'Could not reorder the queue.';

  @override
  String get navCollapse => 'Collapse menu';

  @override
  String get navExpand => 'Expand menu';

  @override
  String get deleteMember => 'Delete Member';

  @override
  String get confirmDeleteMember =>
      'Are you sure you want to delete this member? Their loans and holds must be settled first.';

  @override
  String confirmDeleteItemNamed(String item) {
    return 'Are you sure you want to delete this item ($item)?';
  }

  @override
  String reportGeneratedOn(String when) {
    return 'Generated $when';
  }

  @override
  String userJoinedOn(String when) {
    return 'Joined $when';
  }

  @override
  String get noNamedAccounts => 'No named accounts yet';

  @override
  String get noNamedAccountsHint =>
      'You are signed in as the built-in administrator. Create staff or viewer accounts below to grant scoped access to other users.';
}
