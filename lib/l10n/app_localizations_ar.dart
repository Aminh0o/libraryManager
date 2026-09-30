// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مدير المكتبة';

  @override
  String get items => 'العناصر';

  @override
  String get addItem => 'إضافة عنصر';

  @override
  String get editItem => 'تعديل العنصر';

  @override
  String get deleteItem => 'حذف العنصر';

  @override
  String get code => 'الرمز';

  @override
  String get designation => 'التسمية';

  @override
  String get quantity => 'الكمية';

  @override
  String get location => 'الموقع';

  @override
  String get rate => 'المعدل';

  @override
  String get stockLocation => 'موقع المخزن';

  @override
  String get stock => 'المخزن';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get confirmDelete => 'هل أنت متأكد من حذف هذا العنصر؟';

  @override
  String get search => 'بحث...';

  @override
  String get language => 'اللغة';

  @override
  String get generateReport => 'توليد تقرير';

  @override
  String get codeRequired => 'الرمز مطلوب';

  @override
  String get designationRequired => 'التسمية مطلوبة';

  @override
  String get wholeNumberRequired => 'عدد صحيح مطلوب';

  @override
  String get numberRequired => 'رقم مطلوب';

  @override
  String get mustBeNonNegative => 'يجب أن يكون أكبر من أو يساوي 0';

  @override
  String get newValue => 'قيمة جديدة';

  @override
  String get attributeOptionsNote =>
      'تظهر هذه الخيارات في القوائم المنسدلة عند إضافة كتاب أو تعديلَه.';

  @override
  String get usbScannerNote =>
      'أجهزة قراءة USB تعمل كلوحة مفاتيح. ما عليك سوى المسح!';

  @override
  String get settings => 'الإعدادات';

  @override
  String get inventory => 'المخزون';

  @override
  String get fullCodeLabel => 'الرمز الكامل';

  @override
  String get typeLabel => 'النوع';

  @override
  String get nationalLibrary => 'المكتبة الوطنية';

  @override
  String get algerianSystem => 'نظام الإدارة الجزائري';

  @override
  String get dashboard => 'لوحة المعلومات';

  @override
  String get quickActions => 'إجراءات سريعة';

  @override
  String get addNewBook => 'كتاب جديد';

  @override
  String get refreshData => 'تحديث';

  @override
  String get status => 'الحالة';

  @override
  String get actions => 'الإجراءات';

  @override
  String get dataProtection => 'حماية البيانات';

  @override
  String get backupDatabase => 'نسخ احتياطي لقاعدة البيانات';

  @override
  String get selectBackupDatabase => 'اختر قاعدة البيانات للنسخ الاحتياطي';

  @override
  String get restoreDatabase => 'استعادة قاعدة البيانات';

  @override
  String get manageVariables => 'إدارة المتغيرات';

  @override
  String get manageAttributes => 'إدارة الخصائص';

  @override
  String get variablesTitle => 'المتغيرات والخصائص';

  @override
  String get manageVariablesDescription =>
      'تعديل بادئات الكود والفئات (LIV، REV، إلخ)';

  @override
  String get manageAttributesDescription =>
      'تعديل قوائم المواقع والحالات والمخزون';

  @override
  String get backupDescription => 'إنشاء نسخة من قاعدة البيانات الخاصة بك';

  @override
  String get restoreDescription => 'استعادة البيانات من ملف نسخة احتياطية';

  @override
  String get security => 'الأمن';

  @override
  String get adminPassword => 'كلمة مرور المسؤول';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String get newPassword => 'كلمة المرور الجديدة';

  @override
  String get wrongPassword => 'كلمة مرور خاطئة';

  @override
  String get passwordRequired => 'كلمة المرور مطلوبة';

  @override
  String get dangerZone => 'منطقة الخطر';

  @override
  String get eraseAllData => 'مسح قاعدة البيانات بالكامل';

  @override
  String get eraseWarning =>
      'تحذير: سيؤدي هذا إلى حذف جميع العناصر نهائيًا وإعادة ضبط الإعدادات. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get connected => 'متصل';

  @override
  String get disconnected => 'غير متصل';

  @override
  String get reconnecting => 'إعادة الاتصال…';

  @override
  String get connectionType => 'نوع الاتصال';

  @override
  String get hostMode => 'خادم (مضيف)';

  @override
  String get clientMode => 'عميل';

  @override
  String get enterPassword => 'أدخل كلمة مرور المسؤول';

  @override
  String get historyTitle => 'سجل العمليات';

  @override
  String get filter => 'تصفية';

  @override
  String get all => 'الكل';

  @override
  String get operationAdd => 'إضافة';

  @override
  String get operationUpdate => 'تصحيح';

  @override
  String get operationDelete => 'حذف';

  @override
  String get operationWipe => 'إعادة ضبط';

  @override
  String get noHistoryFound => 'لم يتم العثور على سجلات';

  @override
  String get by => 'بواسطة';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get confirmNewPassword => 'تأكيد كلمة المرور الجديدة';

  @override
  String get passwordsDoNotMatch => 'كلمات المرور غير متطابقة';

  @override
  String get passwordUpdated => 'تم تحديث كلمة المرور بنجاح';

  @override
  String get minPasswordLength => '4 أحرف على الأقل';

  @override
  String get unlockSettings => 'إلغاء قفل التعديل (يتطلب كلمة مرور)';

  @override
  String get showActionsLog => 'عرض سجل العمليات';

  @override
  String get dataWiped => 'تم مسح جميع البيانات';

  @override
  String get validate => 'تأكيد';

  @override
  String get allStatuses => 'جميع الحالات';

  @override
  String get clearFilters => 'مسح الفلاتر';

  @override
  String get priceDzd => 'السعر (د.ج)';

  @override
  String get loadMore => 'تحميل المزيد من العناصر';

  @override
  String get serverModeName => 'وضع الخادم';

  @override
  String get clientModeName => 'وضع العميل';

  @override
  String get totalDocuments => 'إجمالي المستندات';

  @override
  String get inventoryValue => 'قيمة المخزون';

  @override
  String get onLoan => 'قيد الإعارة';

  @override
  String get historyAction => 'السجل';

  @override
  String get exportCsv => 'تصدير CSV';

  @override
  String get exportSuccess => 'تم التصدير بنجاح';

  @override
  String get exportError => 'خطأ في التصدير';

  @override
  String get allTypes => 'جميع الأنواع';

  @override
  String get noItemsFound => 'لم يتم العثور على عناصر';

  @override
  String get backupSuccess => 'تم إنشاء النسخة الاحتياطية بنجاح!';

  @override
  String get backupFailed => 'فشل النسخ الاحتياطي.';

  @override
  String get restoreFailed => 'فشل الاستعادة.';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get noPhone => 'لا يوجد هاتف';

  @override
  String scannerError(String code) {
    return 'خطأ في الماسح: $code';
  }

  @override
  String selectedItemLabel(String name, String status) {
    return 'المحدد: $name ($status)';
  }

  @override
  String get restoreSuccess => 'تم استعادة قاعدة البيانات بنجاح!';

  @override
  String get setPassword => 'تعيين كلمة المرور';

  @override
  String get importExcel => 'استيراد من Excel (.xlsx)';

  @override
  String get importSuccess => 'تم استيراد البيانات بنجاح!';

  @override
  String get importError => 'فشل الاستيراد: ';

  @override
  String get scanBarcode => 'مسح الرمز البارcode';

  @override
  String get cameraPermissionRequired =>
      'مطلوب إذن الكاميرا لمسح الرموز الشريطية.';

  @override
  String get cameraPermissionDenied => 'تم رفض إذن الكاميرا.';

  @override
  String get barcode => 'باركود (ISBN/EAN)';

  @override
  String get barcodeHint => 'امسح أو أدخل الباركود';

  @override
  String get autoGenerated => 'توليد تلقائي';

  @override
  String get required => 'مطلوب';

  @override
  String get statusDisponible => 'متاح';

  @override
  String get statusEmprunte => 'معار';

  @override
  String get statusReserve => 'محجوز';

  @override
  String get statusEndommage => 'تالف';

  @override
  String get statusEnReparation => 'قيد الإصلاح';

  @override
  String get statusPerdu => 'مفقود';

  @override
  String get statusArchive => 'مؤرشف';

  @override
  String get itemCopies => 'النسخ';

  @override
  String copyNumberLabel(int n) {
    return 'نسخة $n';
  }

  @override
  String get copyBarcodeMissing => 'لا يوجد رمز شريطي';

  @override
  String get changeCopyState => 'تغيير الحالة';

  @override
  String get copyLockedTooltip =>
      'يجب تغيير النسخ المستعارة أو المحجوزة عبر الإعارة/الحجز';

  @override
  String get copyStateUpdated => 'تم تحديث النسخة';

  @override
  String get addCopy => 'إضافة نسخة';

  @override
  String get removeCopy => 'إزالة هذه النسخة';

  @override
  String get setCopyBarcode => 'رمز النسخة';

  @override
  String get copyBarcodeSave => 'حفظ';

  @override
  String get removeCopyConfirm =>
      'هل تريد إزالة هذه النسخة المادية؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get copyAdded => 'تمت إضافة النسخة';

  @override
  String get copyRemoved => 'تمت إزالة النسخة';

  @override
  String get copyBarcodeSaved => 'تم تحديث رمز النسخة';

  @override
  String get itemProfile => 'ملف تعريف العنصر';

  @override
  String get itemDetails => 'تفاصيل العنصر';

  @override
  String get editItemDetails => 'تعديل التفاصيل';

  @override
  String get locationInfo => 'معلومات الموقع';

  @override
  String get pricingInfo => 'معلومات التسعير';

  @override
  String get technicalInfo => 'المعلومات التقنية';

  @override
  String get markAsAvailable => 'تعيين كمتاح';

  @override
  String get markAsBorrowed => 'تعيين كمعار';

  @override
  String get markAsReserved => 'تعيين كمحجوز';

  @override
  String get markAsDamaged => 'تعيين كتالف';

  @override
  String get prefix => 'البادئة';

  @override
  String get prefixHint => '3-4 أحرف (مثال: LIV, ARCH)';

  @override
  String get label => 'التسمية';

  @override
  String get labelHint => 'التسمية (مثال: كتاب، أرشيف)';

  @override
  String get saveDefinition => 'حفظ المتغير';

  @override
  String get cancelEdit => 'إلغاء التعديل';

  @override
  String get confirmDeleteDefinition => 'حذف المتغير؟';

  @override
  String get deleteDefinitionWarning =>
      'هل أنت متأكد من حذف هذا المتغير؟ ستبقى العناصر الموجودة ولكن قد يتأثر التصفية.';

  @override
  String get notePrefixChange =>
      'ملاحظة: تغيير البادئة سيؤدي إلى تحديث جميع العناصر المرتبطة.';

  @override
  String get addVariable => 'إضافة متغير';

  @override
  String get updateVariable => 'تحديث';

  @override
  String get newVariable => 'متغير جديد';

  @override
  String get editVariable => 'تعديل المتغير';

  @override
  String get savedSuccessfully => 'تم الحفظ بنجاح';

  @override
  String get pairingCode => 'رمز الاقتران';

  @override
  String get scanServerCode => 'مسح رمز الخادم';

  @override
  String get scanServerDescription =>
      'اتصل تلقائيًا عن طريق مسح رمز QR على شاشة المضيف.';

  @override
  String get pairingCodeDescription =>
      'السماح للعملاء بالاتصال عن طريق مسح هذا الرمز.';

  @override
  String get enterPairingCode => 'إدخال رمز الاقتران';

  @override
  String get enterPairingCodeDescription =>
      'للاتصال بدون كاميرا: أدخل الرمز المكوّن من 6 أرقام المعروض على المضيف.';

  @override
  String get pairingSearching => 'جاري البحث عن المضيف على الشبكة المحلية...';

  @override
  String get pairingIpSet => 'تم العثور على المضيف. تم إعداد الاتصال.';

  @override
  String get pairingHostNotFound =>
      'لم يتم العثور على مضيف. تحقق من الرمز وأن الجهازين على نفس الشبكة.';

  @override
  String pairingValidMinutes(int minutes) {
    return 'صالح لمدة حوالي $minutes دقيقة';
  }

  @override
  String get connectedDevices => 'الأجهزة المتصلة';

  @override
  String get connectedViaLan => 'متصل عبر الشبكة المحلية';

  @override
  String get noConnectedDevices => 'لا توجد أجهزة متصلة الآن.';

  @override
  String get noCopiesYet => 'لا توجد نسخ مسجلة بعد.';

  @override
  String get memberIdAuto => 'المعرّف (تلقائي)';

  @override
  String get memberIdCode => 'المعرّف / الرمز';

  @override
  String get scanWithUsbOrType => 'استخدم ماسح USB أو اكتب الرمز';

  @override
  String get scanOrTypeHint => 'امسح الرمز أو اكتب هنا...';

  @override
  String get requiredField => 'حقل مطلوب';

  @override
  String get members => 'الأعضاء';

  @override
  String get loans => 'الإعارات';

  @override
  String get memberManagement => 'إدارة الأعضاء';

  @override
  String get loanManagement => 'إدارة الإعارات';

  @override
  String get newLoan => 'إعارة جديدة';

  @override
  String get returnLoan => 'إرجاع';

  @override
  String get selectMember => '1. اختيار العضو';

  @override
  String get selectItem => '2. اختيار العنصر';

  @override
  String get validateLoan => 'تأكيد الإعارة';

  @override
  String get memberSearchHint => 'بحث عن عضو (الاسم أو المعرف)';

  @override
  String get itemSearchHint => 'الكود الشريطي أو العنوان';

  @override
  String get loanSuccess => 'تم تسجيل الإعارة بنجاح';

  @override
  String get returnSuccess => 'تم تسجيل الإرجاع بنجاح';

  @override
  String get addMember => 'إضافة عضو';

  @override
  String get editMember => 'تعديل العضو';

  @override
  String get firstName => 'الاسم الأول';

  @override
  String get lastName => 'اللقب';

  @override
  String get phone => 'الهاتف';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get scanToReturn => 'امسح العنصر للإرجاع';

  @override
  String get confirmReturn => 'تأكيد الإرجاع';

  @override
  String get itemNotFound => 'العنصر غير موجود';

  @override
  String get itemNotAvailable => 'هذا العنصر غير متاح';

  @override
  String get noActiveLoan => 'لا يوجد إعارة نشطة لهذا العنصر';

  @override
  String get activeLoans => 'الإعارات النشطة';

  @override
  String get noActiveLoans => 'لا توجد إعارات نشطة.';

  @override
  String get overdue => 'متأخر';

  @override
  String get renew => 'تجديد';

  @override
  String get renewSuccess => 'تم تجديد الإعارة بنجاح';

  @override
  String get colMember => 'العضو';

  @override
  String get colItem => 'العنصر';

  @override
  String get loanDateCol => 'تاريخ الإعارة';

  @override
  String get dueDateCol => 'تاريخ الاستحقاق';

  @override
  String get selectCamera => 'اختر الكاميرا';

  @override
  String get cameraFront => 'الكاميرا الأمامية';

  @override
  String get cameraBack => 'الكاميرا الخلفية';

  @override
  String get cameraExternal => 'كاميرا خارجية (USB)';

  @override
  String get cameraUnknown => 'كاميرا';

  @override
  String get flash => 'وميض';

  @override
  String get switchCamera => 'تبديل';

  @override
  String get cameras => 'الكاميرات';

  @override
  String get helpCenter => 'مركز المساعدة';

  @override
  String get setupRoadmap => 'خارطة طريق الإعداد';

  @override
  String get welcome => 'مرحباً بك';

  @override
  String get getStarted => 'ابدأ الآن';

  @override
  String get next => 'التالي';

  @override
  String get finish => 'إنهاء';

  @override
  String get stepLanguage => 'اللغة';

  @override
  String get stepSecurity => 'الأمان';

  @override
  String get stepConfiguration => 'التكوين';

  @override
  String get setupLanguageDesc => 'اختر لغتك المفضلة للتطبيق.';

  @override
  String get setupPasswordDesc => 'تعيين كلمة مرور إدارية لحماية بياناتك.';

  @override
  String get setupConfigDesc => 'تكوين البادئات والسمات الأساسية للمكتبة.';

  @override
  String get configPrefixesLabel => 'بادئات الرموز (LIV، REV، إلخ)';

  @override
  String get configPrefixesDesc => 'سيتم تهيئة القيم الافتراضية.';

  @override
  String get configAttributesLabel => 'السمات الديناميكية';

  @override
  String get configAttributesDesc => 'المواقع والحالات والمخزون.';

  @override
  String get setupComplete => 'اكتمل الإعداد!';

  @override
  String get setupCompleteDesc => 'أنت الآن جاهز لاستخدام نظام إدارة المكتبة.';

  @override
  String get helpMembersTitle => 'إدارة الأعضاء';

  @override
  String get helpMembersContent =>
      '1. انتقل إلى علامة التبويب \'الأعضاء\' لإضافة أو تعديل المستخدمين.\n2. يتم تعيين معرف فريد لكل عضو (مثلاً 260001) منسق للتسجيل الوطني.\n3. تتبع سجل الإعارات، والكتب المستعارة حالياً، وتواريخ التسجيل لكل عضو.';

  @override
  String get helpLoansTitle => 'نظام الإعارة';

  @override
  String get helpLoansContent =>
      '1. مسح كتاب في شاشة \'القروض\' يبدأ عملية الإعارة.\n2. أدخل معرف العضو أو امسح بطاقتهم لربط الإعارة.\n3. أعد الكتب بمسحها مرة أخرى في قسم \'Prêts\' أو وضع علامة \'تم الإرجاع\' يدوياً في السجل.';

  @override
  String get helpSyncTitle => 'المزامنة عبر الشبكة المحلية (LAN)';

  @override
  String get helpSyncContent =>
      '1. يجب إعداد جهاز واحد كـ \'مضيف\' (جهاز رئيسي) بينما تكون الأجهزة الأخرى \'عملاء\'.\n2. يتصل العملاء عبر عنوان IP الخاص بالمضيف. يمكن الاقتران تلقائياً بمسح رمز QR.\n3. تنعكس التغييرات من أي جهاز على الخادم عبر الشبكة المحلية في الوقت الفعلي.';

  @override
  String get helpBarcodeTitle => 'مسح الباركود';

  @override
  String get helpBarcodeContent =>
      '1. الكاميرا المدمجة: تدعم التبديل بين الكاميرات الأمامية/الخلفية/الخارجية مع دعم الفلاش.\n2. الماسحات الضوئية USB: دعم التوصيل والتشغيل المباشر في أي حقل بحث.\n3. أجهزة متعددة: التبديل بين الكاميرات المتاحة عبر القائمة المنسدلة في نافذة مسح الباركود.';

  @override
  String get documentation => 'الوثائق والأدلة';

  @override
  String get resetOnboarding => 'إعادة تعيين خارطة طريق الإعداد';

  @override
  String get resetOnboardingDesc =>
      'إعادة تعيين الإعداد والتهيئة (للاختبار فقط)';

  @override
  String get resetRestartApp =>
      'تم إعادة تعيين خارطة طريق الإعداد. أعد تشغيل التطبيق.';

  @override
  String get checkForUpdates => 'التحقق من التحديثات';

  @override
  String get updateAvailable => 'تحديث متاح';

  @override
  String get noUpdateAvailable => 'أنت تستخدم أحدث إصدار.';

  @override
  String get updateNow => 'تحديث الآن';

  @override
  String get updateNotConfigured =>
      'التحقق التلقائي من التحديثات غير مُهيَّأ لهذا النشر.';

  @override
  String get updateCheckFailed =>
      'تعذر الوصول إلى خادم التحديث. حاول مرة أخرى لاحقًا.';

  @override
  String updateFoundVersion(String version) {
    return 'الإصدار $version متاح الآن.';
  }

  @override
  String get enableLanAccess => 'تفعيل الوصول عبر الشبكة المحلية';

  @override
  String get enableLanAccessDescription =>
      'السماح لأجهزة أخرى بالاتصال عبر إضافة قواعد جدار حماية ويندوز (يتطلب صلاحيات المسؤول).';

  @override
  String get lanAccessEnabled => 'تم تفعيل الوصول عبر الشبكة المحلية.';

  @override
  String get lanAccessFailed =>
      'فشل إضافة قواعد الجدار الناري. الرجاء قبول نافذة صلاحيات المسؤول.';

  @override
  String get quickScan => 'مسح سريع';

  @override
  String get appDefinitionTitle => 'ما هو مدير المكتبة؟';

  @override
  String get appDefinitionContent =>
      'مدير المكتبة هو حل مكتبي احترافي مصمم للمكتبات ومراكز التوثيق الجزائرية. يوفر أدوات متخصصة لإدارة المخزون والمزامنة عبر الشبكة المحلية (LAN) وتتبع الباركود. يدعم النظام التصنيف الكامل باللغات الإنجليزية والفرنسية والعربية وفقاً للمعايير الوطنية.';

  @override
  String get errNetwork =>
      'لا يمكن الوصول إلى الخادم. تحقق من الاتصال وحاول مرة أخرى.';

  @override
  String get errAuth => 'يتطلب هذا الإجراء مصادقة المسؤول.';

  @override
  String get errConflict =>
      'تعارض: تم تعديل السجل بواسطة شخص آخر أو أنه موجود بالفعل.';

  @override
  String get errNotFound => 'السجل المطلوب غير موجود.';

  @override
  String get errBadRequest => 'تم رفض الطلب لأنه غير صالح.';

  @override
  String get errServerError => 'أبلغ الخادم عن خطأ. يرجى المحاولة مرة أخرى.';

  @override
  String get errGeneric => 'حدث خطأ ما. يرجى المحاولة مرة أخرى.';

  @override
  String get errServerNotInitialized =>
      'لم يتم إعداد أي خادم على الشبكة المحلية في هذا الجهاز.';

  @override
  String get errServerStartFailed =>
      'تعذّر تشغيل خادم الشبكة المحلية. قد يكون برنامج آخر يستخدم هذا المنفذ بالفعل.';

  @override
  String get errHostOnlyFeature =>
      'هذه الميزة متاحة على جهاز المضيف فقط (الجهاز الذي يدير المكتبة).';

  @override
  String get usersAndRoles => 'المستخدمون والأدوار';

  @override
  String get account => 'الحساب';

  @override
  String get role => 'الدور';

  @override
  String get roleAdmin => 'مدير';

  @override
  String get roleStaff => 'موظف';

  @override
  String get roleViewer => 'قارئ';

  @override
  String get roleAdminDescription =>
      'وصول كامل، بما في ذلك إدارة الحسابات والإعدادات';

  @override
  String get roleStaffDescription =>
      'يمكنه الإعارة والإرجاع وتعديل الفهرس والأعضاء والقروض';

  @override
  String get roleViewerDescription =>
      'للقراءة فقط: يمكنه العرض، لا يمكنه تعديل أي شيء';

  @override
  String signedInAs(String user, String role) {
    return 'تم تسجيل الدخول كـ $user ($role)';
  }

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get password => 'كلمة المرور';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get removeAccount => 'إزالة الحساب';

  @override
  String get changeRole => 'تغيير الدور';

  @override
  String removeAccountConfirm(String user) {
    return 'إزالة الحساب \"$user\"؟ سيتم فصل أي جهاز مسجّل الدخول به.';
  }

  @override
  String passwordMinLength(int n) {
    return 'استخدم $n أحرف على الأقل.';
  }

  @override
  String get usernameRules =>
      '3-32 حرفًا: أحرف وأرقام ونقطة وشرطة سفلية وشرطة؛ يجب أن يبدأ بحرف أو رقم؛ بأحرف صغيرة.';

  @override
  String get onlyAdminManagesUsers =>
      'يمكن للمدير فقط إدارة الحسابات والأدوار.';

  @override
  String get readOnlyMode =>
      'أنت مسجّل الدخول بحساب للقراءة فقط. التحرير معطّل.';

  @override
  String get readAccountFailed => 'تعذّر تحميل قائمة الحسابات.';

  @override
  String get signInFailed =>
      'فشل تسجيل الدخول. تحقق من اسم المستخدم وكلمة المرور.';

  @override
  String get pairAsRole => 'امنح هذا الجهاز الدور المحدد عند الاقتران';

  @override
  String get readOnlyAccount => 'حساب للقراءة فقط';

  @override
  String get noAccounts => 'لا يوجد أي حساب بعد';

  @override
  String get fines => 'الغرامات';

  @override
  String get fineNoFines => 'لا توجد غرامات مسجّلة';

  @override
  String get fineStatusPending => 'قيد الانتظار';

  @override
  String get fineStatusPaid => 'مدفوعة';

  @override
  String get fineStatusWaived => 'معفّى عنها';

  @override
  String get fineCollectedBy => 'أنجزها';

  @override
  String get fineAmountLabel => 'المبلغ';

  @override
  String get fineMemberLabel => 'العضو';

  @override
  String get fineReasonLabel => 'السبب';

  @override
  String get fineDateLabel => 'التاريخ';

  @override
  String get fineStatusLabel => 'الحالة';

  @override
  String get fineCollect => 'تحصيل';

  @override
  String get fineWaive => 'إعفاء';

  @override
  String get fineFilterAll => 'كل الغرامات';

  @override
  String fineOutstanding(String amount) {
    return 'المتبقي: $amount';
  }

  @override
  String fineCollectConfirm(String amount) {
    return 'تسجيل دفعة قدرها $amount لهذه الغرامة؟';
  }

  @override
  String fineWaiveConfirm(String amount) {
    return 'الإعفاء من هذه الغرامة البالغة $amount؟ لن يتم تحصيل أي مبلغ.';
  }

  @override
  String get finePolicy => 'سياسة الغرامات';

  @override
  String get fineRatePerDay => 'المعدل عن كل يوم تأخير';

  @override
  String get fineCurrency => 'العملة';

  @override
  String get finePolicySaved => 'تم تحديث سياسة الغرامات';

  @override
  String get finePolicyDisabledHint =>
      'الغرامات معطّلة (المعدل 0). حدّد معدلاً لبدء احتساب الإرجاعات المتأخرة.';

  @override
  String get fineSettled => 'تم تحديث الغرامة';

  @override
  String get finePolicyTooltip => 'تعيين معدل التأخير والعملة (المديرون فقط)';

  @override
  String get onlyStaffManageFines =>
      'يمكن للموظفين فقط عرض الغرامات أو تسويتها.';

  @override
  String get fineViewFailed => 'تعذّر تحميل الغرامات.';

  @override
  String get reservations => 'الحجوزات';

  @override
  String get holdNoHolds => 'لا توجد حجوزات مسجّلة';

  @override
  String get holdStatusQueued => 'في قائمة الانتظار';

  @override
  String get holdStatusAvailable => 'جاهز للاستلام';

  @override
  String get holdStatusFulfilled => 'تم الاستلام';

  @override
  String get holdStatusCancelled => 'ملغى';

  @override
  String get holdStatusExpired => 'منتهي';

  @override
  String get holdPlace => 'حجز';

  @override
  String get holdCancel => 'إلغاء';

  @override
  String holdCancelConfirm(String member, String item) {
    return 'هل تريد إلغاء حجز $member للعنوان $item؟';
  }

  @override
  String get holdPlaced => 'تم تسجيل الحجز';

  @override
  String get holdCancelled => 'تم إلغاء الحجز';

  @override
  String get holdViewFailed => 'تعذّر تحميل الحجوزات.';

  @override
  String get holdPlaceFailed => 'تعذّر تسجيل الحجز.';

  @override
  String get onlyStaffManageHolds => 'يمكن للموظفين فقط إدارة الحجوزات.';

  @override
  String get holdFilterAll => 'كل الحجوزات';

  @override
  String get holdFilterOpen => 'الحجوزات المفتوحة';

  @override
  String get holdFilterReady => 'جاهزة للاستلام';

  @override
  String holdQueuePosition(String position) {
    return 'الترقية #$position في القائمة';
  }

  @override
  String holdPickupBy(String date) {
    return 'يُستلم قبل $date';
  }

  @override
  String get holdItemLabel => 'العنوان';

  @override
  String get holdMemberLabel => 'العضو';

  @override
  String get holdSelectItem => 'اختر عنوانًا';

  @override
  String get holdSelectMember => 'اختر عضوًا';

  @override
  String get holdNeedSelection => 'اختر عنوانًا وعضوًا.';

  @override
  String get holdNothingReady => 'لا يوجد حجز بانتظار الاستلام';

  @override
  String get holdPolicy => 'سياسة الحجز';

  @override
  String get holdPolicyTooltip =>
      'تعيين مهلة الاستلام والحد الأقصى للقائمة (المديرون فقط)';

  @override
  String get holdPolicySaved => 'تم تحديث سياسة الحجز';

  @override
  String get holdPickupDays => 'مهلة الاستلام (بالأيام)';

  @override
  String get holdQueueCap => 'أقصى حجوزات لكل عنوان';

  @override
  String get holdNoItems => 'لا توجد عناوين محمّلة لإنشاء حجز.';

  @override
  String get holdNoMembers => 'لا يوجد أعضاء محمّلون لإنشاء حجز.';

  @override
  String get reports => 'التقارير';

  @override
  String get reportSelectKind => 'نوع التقرير';

  @override
  String get reportKindCirculation => 'التداول';

  @override
  String get reportKindOverdue => 'العناصر المتأخرة';

  @override
  String get reportKindInventory => 'المخزون';

  @override
  String get reportKindFines => 'الغرامات';

  @override
  String get reportKindMembers => 'أكثر الأعضاء استعارة';

  @override
  String get reportRun => 'إنشاء التقرير';

  @override
  String get reportFrom => 'من';

  @override
  String get reportTo => 'إلى';

  @override
  String get reportGeneratedLabel => 'تم الإنشاء';

  @override
  String get reportPeriodLabel => 'الفترة';

  @override
  String get reportDateHint => 'سنة-شهر-يوم';

  @override
  String get reportWindowNote => 'يشمل هذا التقرير نطاقًا زمنيًا.';

  @override
  String get reportInvalidDates => 'أدخل تاريخًا صالحًا (سنة-شهر-يوم).';

  @override
  String get reportNoData => 'لا توجد سجلات لهذا التقرير';

  @override
  String get reportSummary => 'الملخص';

  @override
  String reportGeneratedAt(String when) {
    return 'تم الإنشاء $when';
  }

  @override
  String get reportExportCsv => 'تصدير CSV';

  @override
  String get reportExportPdf => 'تصدير PDF';

  @override
  String reportSaved(String path) {
    return 'تم الحفظ في $path';
  }

  @override
  String get reportFailed => 'تعذر إنشاء التقرير.';

  @override
  String get reportExportFailed => 'تعذر تصدير التقرير.';

  @override
  String get onlyStaffRunReports => 'الموظفون فقط يمكنهم إنشاء التقارير.';

  @override
  String get exportDiagnostics => 'تصدير التشخيصات';

  @override
  String diagnosticsSaved(String path) {
    return 'تم حفظ التشخيصات في $path';
  }

  @override
  String get diagnosticsFailed => 'تعذر تصدير التشخيصات.';

  @override
  String get connectionMode => 'وضع الاتصال';

  @override
  String get hostModeOption => 'المضيف (الحاسوب الرئيسي — الخادم)';

  @override
  String get clientModeOption => 'العميل (حاسوب الموظف)';

  @override
  String get hostIpLabel => 'عنوان IP للمضيف';

  @override
  String get hostIpHelper =>
      'أدخل عنوان IP للحاسوب الرئيسي (مثال: 192.168.1.50)';

  @override
  String get appearance => 'المظهر';

  @override
  String get appearanceHint =>
      'السمة وهوية هذا الجهاز. غير مشتركة مع أجهزة أخرى.';

  @override
  String get themeLabel => 'السمة';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get accentColor => 'لون التمييز';

  @override
  String get brandName => 'اسم العلامة';

  @override
  String get brandNameHint =>
      'اسم المنتج المعروض في شريط العنوان (المسؤولون فقط)';

  @override
  String get featuresTitle => 'الميزات';

  @override
  String get featureFlagsHint =>
      'فعّل أو عطّل الشاشات الاختيارية. التغييرات تُطبَّق فورًا.';

  @override
  String get brandNameUpdated => 'تم تحديث اسم العلامة';

  @override
  String get commandPalette => 'لوحة الأوامر';

  @override
  String get paletteSearchHint => 'اكتب للبحث عن أوامر…';

  @override
  String get paletteNoMatches => 'لا توجد أوامر مطابقة';

  @override
  String get systemHealthTitle => 'صحة النظام';

  @override
  String get healthAppVersion => 'إصدار التطبيق';

  @override
  String get healthDatabaseSchema => 'إصدار مخطط قاعدة البيانات';

  @override
  String get healthOperatingMode => 'وضع التشغيل';

  @override
  String get healthLanServer => 'خادم الشبكة المحلية';

  @override
  String get healthServerRunning => 'يُصغي';

  @override
  String get healthServerStopped => 'لا يُصغي';

  @override
  String get healthConnection => 'الاتصال';

  @override
  String get healthConnectedClients => 'العملاء المتصلون';

  @override
  String healthClientCount(int n) {
    return '$n نشط';
  }

  @override
  String get healthLastBackup => 'آخر نسخة احتياطية';

  @override
  String get healthNever => 'أبدًا';

  @override
  String get healthBackupFresh => 'حديثة';

  @override
  String get healthBackupStale => 'متأخرة';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get notifNone => 'لا شيء يتطلب انتباهك';

  @override
  String get notifLoading => 'جارٍ التحقق…';

  @override
  String notifOverdue(int n) {
    return '$n إعارة متأخرة';
  }

  @override
  String notifHoldsReady(int n) {
    return '$n حجز جاهز للاستلام';
  }

  @override
  String notifFinesPending(int n) {
    return '$n غرامة بانتظار السداد';
  }

  @override
  String get chat => 'دردشة الموظفين';

  @override
  String get chatInputHint => 'رسالة…';

  @override
  String get chatSend => 'إرسال';

  @override
  String get chatEmpty => 'لا توجد رسائل بعد.';

  @override
  String get chatUnavailable => 'الدردشة غير متاحة الآن.';

  @override
  String helpVersionFooter(String version) {
    return 'مدير المكتبة v$version';
  }

  @override
  String get settingsCatGeneral => 'عام';

  @override
  String get settingsCatLibrary => 'المكتبة';

  @override
  String get settingsCatData => 'البيانات والنسخ الاحتياطي';

  @override
  String get settingsCatSecurity => 'الأمان';

  @override
  String get settingsCatAdvanced => 'متقدم';

  @override
  String get settingsSearchHint => 'البحث في الإعدادات';

  @override
  String get settingsUnsaved => 'تغييرات غير محفوظة';

  @override
  String get settingsRevert => 'تراجع';

  @override
  String get memberDetail => 'ملف العضو';

  @override
  String get memberNotFound => 'العضو غير موجود';

  @override
  String get registered => 'تاريخ التسجيل';

  @override
  String get memberLoans => 'الاستعارات النشطة';

  @override
  String memberOverdueAlert(int n) {
    return '$n عنصر(عناصر) متأخرة تحتاج انتباه';
  }

  @override
  String get noLoansForMember => 'لا توجد استعارات لهذا العضو';

  @override
  String get dueDate => 'الاستحقاق';

  @override
  String get renewLoan => 'تجديد هذا القرض';

  @override
  String get memberFines => 'الغرامات';

  @override
  String get finePending => 'معلقة';

  @override
  String get noPendingFines => 'لا توجد غرامات معلقة';

  @override
  String get memberReservations => 'الحجوزات';

  @override
  String get noActiveReservations => 'لا توجد حجوزات نشطة';

  @override
  String get holdReadyForPickup => 'جاهز للاستلام';

  @override
  String get holdQueued => 'في الانتظار';

  @override
  String get statusAvailable => 'متاح';

  @override
  String get statusQueued => 'مؤجل';

  @override
  String get needsAttention => 'يحتاج انتباه';

  @override
  String get checkoutAction => 'إعارة';

  @override
  String get reserveAction => 'حجز';

  @override
  String copiesAvailableLabel(int a, int t) {
    return '$a من $t نسخ متاحة';
  }

  @override
  String get noCopiesAvailableForCheckout =>
      'لا توجد نسخ متاحة للإعارة حالياً.';

  @override
  String get reserveSuccess => 'تم إنشاء الحجز.';

  @override
  String get noMembersMatchSearch => 'لا يوجد أعضاء مطابقون للبحث.';

  @override
  String paginationSummary(int from, int to, int total) {
    return 'عرض $from–$to من $total عنصر';
  }

  @override
  String get keyboardShortcutsTitle => 'اختصارات لوحة المفاتيح';

  @override
  String get keyboardShortcutsContent =>
      'Ctrl+K يفتح لوحة الأوامر. Enter ينفذ أعلى نتيجة. Esc يغلب النوافذ. Tab ينتقل بين الحقول؛ الأسهم تتنقل في القوائم.';

  @override
  String get historySubjectPlaceholder => 'تصفية حسب الرمز أو هوية العضو...';

  @override
  String get seeAllHistory => 'عرض كل السجل';

  @override
  String get noHistoryForRecord => 'لا يوجد نشاط حديث لهذا السجل.';

  @override
  String get queueMoveUp => 'تحريك لأعلى في الطابور';

  @override
  String get queueMoveDown => 'تحريك لأسفل في الطابور';

  @override
  String get queueOrderByItem => 'رشح حسب العنصر لإعادة ترتيب الطابور';

  @override
  String get queueMoved => 'تم تحديث ترتيب الطابور.';

  @override
  String get queueMoveFailed => 'تعذر إعادة ترتيب الطابور.';

  @override
  String get navCollapse => 'طي القائمة';

  @override
  String get navExpand => 'توسيع القائمة';

  @override
  String get deleteMember => 'حذف العضو';

  @override
  String get confirmDeleteMember =>
      'هل أنت متأكد من حذف هذا العضو؟ يجب تسديد القراءات والحجوزات أولاً.';

  @override
  String confirmDeleteItemNamed(String item) {
    return 'هل أنت متأكد من حذف هذا العنصر ($item)؟';
  }

  @override
  String reportGeneratedOn(String when) {
    return 'تم الإنشاء في $when';
  }

  @override
  String userJoinedOn(String when) {
    return 'انضم في $when';
  }

  @override
  String get noNamedAccounts => 'لا توجد حسابات مسماة بعد';

  @override
  String get noNamedAccountsHint =>
      'أنت مسجل الدخول كمسؤول مدمج. أنشئ حسابات موظفين أو عرض أدناه لمنح وصول محدود لمستخدمين آخرين.';
}
