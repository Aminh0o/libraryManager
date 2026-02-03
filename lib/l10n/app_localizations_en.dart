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
  String get changePassword => 'Change Password';

  @override
  String get newPassword => 'New Password';

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
}
