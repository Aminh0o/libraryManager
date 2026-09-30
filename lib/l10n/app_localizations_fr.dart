// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Gestionnaire de Bibliothèque';

  @override
  String get items => 'Éléments';

  @override
  String get addItem => 'Ajouter un élément';

  @override
  String get editItem => 'Modifier l\'élément';

  @override
  String get deleteItem => 'Supprimer l\'élément';

  @override
  String get code => 'Code';

  @override
  String get designation => 'Désignation';

  @override
  String get quantity => 'Quantité';

  @override
  String get location => 'Emplacement';

  @override
  String get rate => 'Taux';

  @override
  String get stockLocation => 'Emplacement Stock';

  @override
  String get stock => 'Stock';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get confirmDelete =>
      'Êtes-vous sûr de vouloir supprimer cet élément ?';

  @override
  String get search => 'Rechercher...';

  @override
  String get language => 'Langue';

  @override
  String get generateReport => 'Générer un rapport';

  @override
  String get codeRequired => 'Le code est requis';

  @override
  String get designationRequired => 'La désignation est requise';

  @override
  String get wholeNumberRequired => 'Nombre entier requis';

  @override
  String get numberRequired => 'Nombre requis';

  @override
  String get mustBeNonNegative => 'Doit etre superieur ou egal a 0';

  @override
  String get newValue => 'Nouvelle valeur';

  @override
  String get attributeOptionsNote =>
      'Ces options apparaîtront dans les listes déroulantes lors de l\'ajout ou de la modification d\'un livre.';

  @override
  String get usbScannerNote =>
      'Les lecteurs USB agissent comme des claviers. Il suffit de scanner !';

  @override
  String get settings => 'Paramètres';

  @override
  String get inventory => 'Inventaire';

  @override
  String get fullCodeLabel => 'Code Complet';

  @override
  String get typeLabel => 'Type';

  @override
  String get nationalLibrary => 'Bibliothèque Nationale';

  @override
  String get algerianSystem => 'Système de Gestion Algérien';

  @override
  String get dashboard => 'Tableau de Bord';

  @override
  String get quickActions => 'Actions Rapides';

  @override
  String get addNewBook => 'Nouveau Livre';

  @override
  String get refreshData => 'Rafraîchir';

  @override
  String get status => 'Statut';

  @override
  String get actions => 'Actions';

  @override
  String get dataProtection => 'Protection des Données';

  @override
  String get backupDatabase => 'Sauvegarder la base de données';

  @override
  String get selectBackupDatabase => 'Sélectionner la base de sauvegarde';

  @override
  String get restoreDatabase => 'Restaurer la base de données';

  @override
  String get manageVariables => 'Gérer les Variables';

  @override
  String get manageAttributes => 'Gérer les Attributs';

  @override
  String get variablesTitle => 'Variables & Attributs';

  @override
  String get manageVariablesDescription =>
      'Modifier les préfixes de code et catégories système (LIV, REV, etc.)';

  @override
  String get manageAttributesDescription =>
      'Modifier les listes pour Emplacements, Statuts et Stocks';

  @override
  String get backupDescription => 'Créer une copie de votre base de données';

  @override
  String get restoreDescription =>
      'Restaurer les données à partir d\'un fichier de sauvegarde';

  @override
  String get security => 'Sécurité';

  @override
  String get adminPassword => 'Mot de passe administrateur';

  @override
  String get changePassword => 'Modifier le mot de passe';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get wrongPassword => 'Mot de passe incorrect';

  @override
  String get passwordRequired => 'Le mot de passe est requis';

  @override
  String get dangerZone => 'Zone de Danger';

  @override
  String get eraseAllData => 'Effacer toute la base de données';

  @override
  String get eraseWarning =>
      'ATTENTION : Cela supprimera définitivement tous les éléments et réinitialisera les paramètres. Cette action est irréversible.';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get reconnecting => 'Reconnexion…';

  @override
  String get connectionType => 'Type de connexion';

  @override
  String get hostMode => 'Serveur (Hôte)';

  @override
  String get clientMode => 'Client';

  @override
  String get enterPassword => 'Entrer le mot de passe administrateur';

  @override
  String get historyTitle => 'Historique des Opérations';

  @override
  String get filter => 'Filtrer';

  @override
  String get all => 'Tous';

  @override
  String get operationAdd => 'Ajout';

  @override
  String get operationUpdate => 'Correction';

  @override
  String get operationDelete => 'Suppression';

  @override
  String get operationWipe => 'Réinitialisation';

  @override
  String get noHistoryFound => 'Aucun historique trouvé';

  @override
  String get by => 'Par';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get confirmNewPassword => 'Confirmer le nouveau mot de passe';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get passwordUpdated => 'Mot de passe mis à jour avec succès';

  @override
  String get minPasswordLength => 'Minimum 4 caractères';

  @override
  String get unlockSettings =>
      'Débloquer les modifications (requiert mot de passe)';

  @override
  String get showActionsLog => 'Voir le journal des actions';

  @override
  String get dataWiped => 'Toutes les données ont été effacées';

  @override
  String get validate => 'Valider';

  @override
  String get allStatuses => 'Tous les statuts';

  @override
  String get clearFilters => 'Vider les filtres';

  @override
  String get priceDzd => 'Prix (DZD)';

  @override
  String get loadMore => 'Charger plus d\'éléments';

  @override
  String get serverModeName => 'Mode Serveur';

  @override
  String get clientModeName => 'Mode Client';

  @override
  String get totalDocuments => 'Total Documents';

  @override
  String get inventoryValue => 'Valeur Inventaire';

  @override
  String get onLoan => 'En Emprunt';

  @override
  String get historyAction => 'Historique';

  @override
  String get exportCsv => 'Exporter CSV';

  @override
  String get exportSuccess => 'Exporté avec succès';

  @override
  String get exportError => 'Erreur d\'exportation';

  @override
  String get allTypes => 'Tous les types';

  @override
  String get noItemsFound => 'Aucun élément trouvé';

  @override
  String get backupSuccess => 'Sauvegarde créée avec succès !';

  @override
  String get backupFailed => 'Échec de la sauvegarde.';

  @override
  String get restoreFailed => 'Échec de la restauration.';

  @override
  String get retry => 'Réessayer';

  @override
  String get noPhone => 'Aucun téléphone';

  @override
  String scannerError(String code) {
    return 'Erreur du scanner : $code';
  }

  @override
  String selectedItemLabel(String name, String status) {
    return 'Sélectionné : $name ($status)';
  }

  @override
  String get restoreSuccess => 'Base de données restaurée avec succès !';

  @override
  String get setPassword => 'Définir un mot de passe';

  @override
  String get importExcel => 'Importer depuis Excel (.xlsx)';

  @override
  String get importSuccess => 'Données importées avec succès !';

  @override
  String get importError => 'Échec de l\'importation : ';

  @override
  String get scanBarcode => 'Scanner le code-barres';

  @override
  String get cameraPermissionRequired =>
      'L\'autorisation de la caméra est requise pour scanner les codes-barres.';

  @override
  String get cameraPermissionDenied =>
      'L\'autorisation de la caméra a été refusée.';

  @override
  String get barcode => 'Code à barres (ISBN/EAN)';

  @override
  String get barcodeHint => 'Scanner ou saisir le code';

  @override
  String get autoGenerated => 'Généré auto';

  @override
  String get required => 'Requis';

  @override
  String get statusDisponible => 'Disponible';

  @override
  String get statusEmprunte => 'Emprunté';

  @override
  String get statusReserve => 'Réservé';

  @override
  String get statusEndommage => 'Endommagé';

  @override
  String get statusEnReparation => 'En réparation';

  @override
  String get statusPerdu => 'Perdu';

  @override
  String get statusArchive => 'Archivé';

  @override
  String get itemCopies => 'Exemplaires';

  @override
  String copyNumberLabel(int n) {
    return 'Exemplaire $n';
  }

  @override
  String get copyBarcodeMissing => 'Aucun code-barres';

  @override
  String get changeCopyState => 'Changer l\'état';

  @override
  String get copyLockedTooltip =>
      'Les exemplaires empruntés ou réservés doivent être modifiés via les prêts / réservations';

  @override
  String get copyStateUpdated => 'Exemplaire mis à jour';

  @override
  String get addCopy => 'Ajouter un exemplaire';

  @override
  String get removeCopy => 'Retirer cet exemplaire';

  @override
  String get setCopyBarcode => 'Code-barres de l\'exemplaire';

  @override
  String get copyBarcodeSave => 'Enregistrer';

  @override
  String get removeCopyConfirm =>
      'Retirer cet exemplaire physique ? Cette action est irréversible.';

  @override
  String get copyAdded => 'Exemplaire ajouté';

  @override
  String get copyRemoved => 'Exemplaire retiré';

  @override
  String get copyBarcodeSaved => 'Code-barres de l\'exemplaire mis à jour';

  @override
  String get itemProfile => 'Profil de l\'élément';

  @override
  String get itemDetails => 'Détails de l\'élément';

  @override
  String get editItemDetails => 'Modifier les détails';

  @override
  String get locationInfo => 'Infos d\'emplacement';

  @override
  String get pricingInfo => 'Infos de prix';

  @override
  String get technicalInfo => 'Infos techniques';

  @override
  String get markAsAvailable => 'Marquer comme disponible';

  @override
  String get markAsBorrowed => 'Marquer comme emprunté';

  @override
  String get markAsReserved => 'Marquer comme réservé';

  @override
  String get markAsDamaged => 'Marquer comme endommagé';

  @override
  String get prefix => 'Préfixe';

  @override
  String get prefixHint => '3-4 lettres (ex: LIV, ARCH)';

  @override
  String get label => 'Libellé';

  @override
  String get labelHint => 'Libellé (ex: Livre, Archives)';

  @override
  String get saveDefinition => 'Enregistrer la variable';

  @override
  String get cancelEdit => 'Annuler la modification';

  @override
  String get confirmDeleteDefinition => 'Supprimer la variable ?';

  @override
  String get deleteDefinitionWarning =>
      'Voulez-vous vraiment supprimer cette variable ? Les articles existants resteront mais le filtrage pourra être affecté.';

  @override
  String get notePrefixChange =>
      'Note: Changer un préfixe mettra à jour tous les articles liés.';

  @override
  String get addVariable => 'Ajouter la variable';

  @override
  String get updateVariable => 'Mettre à jour';

  @override
  String get newVariable => 'Nouvelle Variable';

  @override
  String get editVariable => 'Modifier la Variable';

  @override
  String get savedSuccessfully => 'Enregistré avec succès';

  @override
  String get pairingCode => 'Code d\'Appairage';

  @override
  String get scanServerCode => 'Scanner le Code du Serveur';

  @override
  String get scanServerDescription =>
      'Connectez-vous automatiquement en scannant le QR code sur l\'écran de l\'hôte.';

  @override
  String get pairingCodeDescription =>
      'Permettez aux clients de se connecter en scannant ce code.';

  @override
  String get enterPairingCode => 'Saisir le code d\'appairage';

  @override
  String get enterPairingCodeDescription =>
      'Connexion sans caméra : saisissez le code à 6 chiffres affiché sur l\'Hôte.';

  @override
  String get pairingSearching => 'Recherche de l\'hôte sur le réseau local...';

  @override
  String get pairingIpSet => 'Hôte trouvé. Connexion configurée.';

  @override
  String get pairingHostNotFound =>
      'Aucun hôte trouvé. Vérifiez le code et que les deux appareils sont sur le même réseau.';

  @override
  String pairingValidMinutes(int minutes) {
    return 'Valide ~$minutes min';
  }

  @override
  String get connectedDevices => 'Appareils Connectés';

  @override
  String get connectedViaLan => 'Connecté via LAN';

  @override
  String get noConnectedDevices =>
      'Aucun appareil n\'est connecté actuellement.';

  @override
  String get noCopiesYet => 'Aucun exemplaire enregistré pour le moment.';

  @override
  String get memberIdAuto => 'ID (généré automatiquement)';

  @override
  String get memberIdCode => 'ID / Code';

  @override
  String get scanWithUsbOrType => 'Utilisez un scanner USB ou tapez le code';

  @override
  String get scanOrTypeHint => 'Scanner ou taper le code ici...';

  @override
  String get requiredField => 'Champ requis';

  @override
  String get members => 'Membres';

  @override
  String get loans => 'Prêts';

  @override
  String get memberManagement => 'Gestion des Membres';

  @override
  String get loanManagement => 'Gestion des Prêts';

  @override
  String get newLoan => 'Nouvel Emprunt';

  @override
  String get returnLoan => 'Retour';

  @override
  String get selectMember => '1. Sélectionner le Membre';

  @override
  String get selectItem => '2. Sélectionner l\'Article';

  @override
  String get validateLoan => 'Valider l\'Emprunt';

  @override
  String get memberSearchHint => 'Rechercher un membre (Nom ou ID)';

  @override
  String get itemSearchHint => 'Code Barre ou Titre';

  @override
  String get loanSuccess => 'Emprunt enregistré avec succès';

  @override
  String get returnSuccess => 'Retour enregistré avec succès';

  @override
  String get addMember => 'Ajouter Membre';

  @override
  String get editMember => 'Modifier Membre';

  @override
  String get firstName => 'Prénom';

  @override
  String get lastName => 'Nom';

  @override
  String get phone => 'Téléphone';

  @override
  String get email => 'Email';

  @override
  String get scanToReturn => 'Scanner l\'article pour le retourner';

  @override
  String get confirmReturn => 'Confirmer le Retour';

  @override
  String get itemNotFound => 'Article non trouvé';

  @override
  String get itemNotAvailable => 'Cet article n\'est pas disponible.';

  @override
  String get noActiveLoan => 'Aucun emprunt actif trouvé pour cet article.';

  @override
  String get activeLoans => 'Emprunts actifs';

  @override
  String get noActiveLoans => 'Aucun emprunt actif.';

  @override
  String get overdue => 'En retard';

  @override
  String get renew => 'Renouveler';

  @override
  String get renewSuccess => 'Emprunt renouvelé avec succès';

  @override
  String get colMember => 'Membre';

  @override
  String get colItem => 'Article';

  @override
  String get loanDateCol => 'Date de prêt';

  @override
  String get dueDateCol => 'Date d\'échéance';

  @override
  String get selectCamera => 'Sélectionner une caméra';

  @override
  String get cameraFront => 'Caméra avant';

  @override
  String get cameraBack => 'Caméra arrière';

  @override
  String get cameraExternal => 'Caméra externe (USB)';

  @override
  String get cameraUnknown => 'Caméra';

  @override
  String get flash => 'Flash';

  @override
  String get switchCamera => 'Intervertir';

  @override
  String get cameras => 'Caméras';

  @override
  String get helpCenter => 'Centre d\'Aide';

  @override
  String get setupRoadmap => 'Guide de Configuration';

  @override
  String get welcome => 'Bienvenue';

  @override
  String get getStarted => 'Commencer';

  @override
  String get next => 'Suivant';

  @override
  String get finish => 'Terminer';

  @override
  String get stepLanguage => 'Langue';

  @override
  String get stepSecurity => 'Sécurité';

  @override
  String get stepConfiguration => 'Configuration';

  @override
  String get setupLanguageDesc =>
      'Choisissez votre langue préférée pour l\'application.';

  @override
  String get setupPasswordDesc =>
      'Définissez un mot de passe administrateur pour protéger vos données.';

  @override
  String get setupConfigDesc =>
      'Configurez les préfixes et attributs de base de la bibliothèque.';

  @override
  String get configPrefixesLabel => 'Préfixes de code (LIV, REV, etc.)';

  @override
  String get configPrefixesDesc =>
      'Les valeurs par défaut seront initialisées.';

  @override
  String get configAttributesLabel => 'Attributs dynamiques';

  @override
  String get configAttributesDesc => 'Emplacements, statuts et stocks.';

  @override
  String get setupComplete => 'Configuration Terminée !';

  @override
  String get setupCompleteDesc =>
      'Vous êtes maintenant prêt à utiliser le Système de Gestion de Bibliothèque.';

  @override
  String get helpMembersTitle => 'Gestion des Membres';

  @override
  String get helpMembersContent =>
      '1. Allez dans l\'onglet \'Membres\' pour ajouter ou modifier des utilisateurs.\n2. Chaque membre reçoit un identifiant unique (ex: 260001) formaté pour l\'enregistrement national.\n3. Suivez l\'historique des prêts, les emprunts actifs et les dates d\'inscription.';

  @override
  String get helpLoansTitle => 'Système de Prêt';

  @override
  String get helpLoansContent =>
      '1. Scanner un article dans l\'écran \'Prêts\' lance le processus de sortie.\n2. Saisissez l\'ID du membre ou scannez sa carte pour lier le prêt.\n3. Retournez les articles en les scannant à nouveau dans la section \'Prêts\' ou manuellement via l\'historique.';

  @override
  String get helpSyncTitle => 'Synchronisation LAN';

  @override
  String get helpSyncContent =>
      '1. Une machine doit être configurée comme \'Hôte\' (Serveur) tandis que les autres sont \'Clients\'.\n2. Les Clients se connectent via l\'IP de l\'Hôte. Appariement automatique possible via QR code.\n3. Toute modification est répercutée sur le serveur via le réseau local en temps réel.';

  @override
  String get helpBarcodeTitle => 'Lecture de Codes-barres';

  @override
  String get helpBarcodeContent =>
      '1. Caméra intégrée : Supporte le basculement avant/arrière/externe avec flash LED.\n2. Lecteurs USB : Support Plug-and-play dans n\'importe quel champ de recherche.\n3. Multi-appareils : Basculez entre les caméras disponibles via le menu déroulant dans la fenêtre de scan.';

  @override
  String get documentation => 'Documentation et guides';

  @override
  String get resetOnboarding => 'Réinitialiser le Guide';

  @override
  String get resetOnboardingDesc =>
      'Réinitialiser l\'onboarding et la configuration';

  @override
  String get resetRestartApp =>
      'Guide de configuration réinitialisé. Redémarrez l\'application.';

  @override
  String get checkForUpdates => 'Vérifier les Mises à Jour';

  @override
  String get updateAvailable => 'Mise à Jour Disponible';

  @override
  String get noUpdateAvailable => 'Vous utilisez la dernière version.';

  @override
  String get updateNow => 'Mettre à Jour Maintenant';

  @override
  String get updateNotConfigured =>
      'La vérification automatique des mises à jour n\'est pas configurée pour ce déploiement.';

  @override
  String get updateCheckFailed =>
      'Impossible de joindre le serveur de mise à jour. Réessayez plus tard.';

  @override
  String updateFoundVersion(String version) {
    return 'La version $version est disponible.';
  }

  @override
  String get enableLanAccess => 'Activer l\'accès LAN';

  @override
  String get enableLanAccessDescription =>
      'Autoriser la connexion des autres PC en ajoutant des règles Windows Firewall (Admin requis).';

  @override
  String get lanAccessEnabled => 'Accès LAN activé.';

  @override
  String get lanAccessFailed =>
      'Impossible d\'ajouter les règles. Veuillez accepter la demande administrateur.';

  @override
  String get quickScan => 'Scan Rapide';

  @override
  String get appDefinitionTitle => 'C\'est quoi Library Manager ?';

  @override
  String get appDefinitionContent =>
      'Library Manager est une solution de bureau professionnelle conçue pour les bibliothèques et centres de documentation algériens. Il fournit des outils spécialisés pour la gestion des stocks, la synchronisation via LAN et le suivi par codes-barres. Le système prend en charge la catégorisation complète en anglais, français et arabe selon les normes nationales.';

  @override
  String get errNetwork =>
      'Serveur injoignable. Vérifiez la connexion et réessayez.';

  @override
  String get errAuth =>
      'Cette action nécessite une authentification administrateur.';

  @override
  String get errConflict =>
      'Conflit : l\'enregistrement a été modifié par quelqu\'un d\'autre ou existe déjà.';

  @override
  String get errNotFound => 'L\'enregistrement demandé est introuvable.';

  @override
  String get errBadRequest => 'La requête a été rejetée comme invalide.';

  @override
  String get errServerError =>
      'Le serveur a signalé une erreur. Veuillez réessayer.';

  @override
  String get errGeneric => 'Une erreur est survenue. Veuillez réessayer.';

  @override
  String get errServerNotInitialized =>
      'Aucun serveur LAN n\'a été configuré sur ce PC.';

  @override
  String get errServerStartFailed =>
      'Le serveur LAN n\'a pas pu démarrer. Un autre programme utilise peut-être déjà ce port.';

  @override
  String get errHostOnlyFeature =>
      'Cette fonctionnalité est disponible uniquement sur le PC hôte (celui qui gère la bibliothèque).';

  @override
  String get usersAndRoles => 'Utilisateurs et rôles';

  @override
  String get account => 'Compte';

  @override
  String get role => 'Rôle';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String get roleStaff => 'Personnel';

  @override
  String get roleViewer => 'Lecteur';

  @override
  String get roleAdminDescription =>
      'Accès complet, y compris la gestion des comptes et les paramètres';

  @override
  String get roleStaffDescription =>
      'Peut emprunter, retourner et modifier le catalogue, les membres et les prêts';

  @override
  String get roleViewerDescription =>
      'Lecture seule : peut consulter, ne peut rien modifier';

  @override
  String signedInAs(String user, String role) {
    return 'Connecté en tant que $user ($role)';
  }

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get removeAccount => 'Supprimer le compte';

  @override
  String get changeRole => 'Modifier le rôle';

  @override
  String removeAccountConfirm(String user) {
    return 'Supprimer le compte « $user » ? Tout appareil connecté avec ce compte sera déconnecté.';
  }

  @override
  String passwordMinLength(int n) {
    return 'Utilisez au moins $n caractères.';
  }

  @override
  String get usernameRules =>
      '3 à 32 caractères : lettres, chiffres, point, tiret bas ou trait d\'union ; doit commencer par une lettre ou un chiffre ; en minuscules.';

  @override
  String get onlyAdminManagesUsers =>
      'Seul un administrateur peut gérer les comptes et les rôles.';

  @override
  String get readOnlyMode =>
      'Vous êtes connecté avec un compte en lecture seule. Modification désactivée.';

  @override
  String get readAccountFailed => 'Impossible de charger la liste des comptes.';

  @override
  String get signInFailed =>
      'Échec de la connexion. Vérifiez le nom d\'utilisateur et le mot de passe.';

  @override
  String get pairAsRole =>
      'Accorder cet rôle à l\'appareil lors de l\'appairage';

  @override
  String get readOnlyAccount => 'Compte en lecture seule';

  @override
  String get noAccounts => 'Aucun compte pour le moment';

  @override
  String get fines => 'Amendes';

  @override
  String get fineNoFines => 'Aucune amende enregistrée';

  @override
  String get fineStatusPending => 'En attente';

  @override
  String get fineStatusPaid => 'Payée';

  @override
  String get fineStatusWaived => 'Annulée';

  @override
  String get fineCollectedBy => 'Traitée par';

  @override
  String get fineAmountLabel => 'Montant';

  @override
  String get fineMemberLabel => 'Membre';

  @override
  String get fineReasonLabel => 'Motif';

  @override
  String get fineDateLabel => 'Date';

  @override
  String get fineStatusLabel => 'Statut';

  @override
  String get fineCollect => 'Encaisser';

  @override
  String get fineWaive => 'Annuler';

  @override
  String get fineFilterAll => 'Toutes les amendes';

  @override
  String fineOutstanding(String amount) {
    return 'Reste dû : $amount';
  }

  @override
  String fineCollectConfirm(String amount) {
    return 'Enregistrer le paiement de $amount pour cette amende ?';
  }

  @override
  String fineWaiveConfirm(String amount) {
    return 'Annuler cette amende de $amount ? Aucun montant ne sera perçu.';
  }

  @override
  String get finePolicy => 'Politique des amendes';

  @override
  String get fineRatePerDay => 'Taux par jour de retard';

  @override
  String get fineCurrency => 'Devise';

  @override
  String get finePolicySaved => 'Politique des amendes mise à jour';

  @override
  String get finePolicyDisabledHint =>
      'Les amendes sont désactivées (taux 0). Définissez un taux pour facturer les retours en retard.';

  @override
  String get fineSettled => 'Amende mise à jour';

  @override
  String get finePolicyTooltip =>
      'Définir le taux de retard et la devise (administrateurs uniquement)';

  @override
  String get onlyStaffManageFines =>
      'Seuls le personnel peut voir ou régler les amendes.';

  @override
  String get fineViewFailed => 'Impossible de charger les amendes.';

  @override
  String get reservations => 'Réservations';

  @override
  String get holdNoHolds => 'Aucune réservation enregistrée';

  @override
  String get holdStatusQueued => 'En file d\'attente';

  @override
  String get holdStatusAvailable => 'Prêt à retirer';

  @override
  String get holdStatusFulfilled => 'Retirée';

  @override
  String get holdStatusCancelled => 'Annulée';

  @override
  String get holdStatusExpired => 'Expirée';

  @override
  String get holdPlace => 'Réserver';

  @override
  String get holdCancel => 'Annuler';

  @override
  String holdCancelConfirm(String member, String item) {
    return 'Annuler la réservation de $member pour $item ?';
  }

  @override
  String get holdPlaced => 'Réservation enregistrée';

  @override
  String get holdCancelled => 'Réservation annulée';

  @override
  String get holdViewFailed => 'Impossible de charger les réservations.';

  @override
  String get holdPlaceFailed => 'Impossible d\'enregistrer la réservation.';

  @override
  String get onlyStaffManageHolds =>
      'Seul le personnel peut gérer les réservations.';

  @override
  String get holdFilterAll => 'Toutes les réservations';

  @override
  String get holdFilterOpen => 'Réservations ouvertes';

  @override
  String get holdFilterReady => 'Prêtes à retirer';

  @override
  String holdQueuePosition(String position) {
    return 'N° $position dans la file';
  }

  @override
  String holdPickupBy(String date) {
    return 'À retirer avant le $date';
  }

  @override
  String get holdItemLabel => 'Ouvrage';

  @override
  String get holdMemberLabel => 'Membre';

  @override
  String get holdSelectItem => 'Sélectionner un ouvrage';

  @override
  String get holdSelectMember => 'Sélectionner un membre';

  @override
  String get holdNeedSelection => 'Choisissez un ouvrage et un membre.';

  @override
  String get holdNothingReady => 'Aucune réservation en attente de retrait';

  @override
  String get holdPolicy => 'Politique de réservation';

  @override
  String get holdPolicyTooltip =>
      'Définir le délai de retrait et la limite de file (administrateurs uniquement)';

  @override
  String get holdPolicySaved => 'Politique de réservation mise à jour';

  @override
  String get holdPickupDays => 'Délai de retrait (jours)';

  @override
  String get holdQueueCap => 'Réservations max par ouvrage';

  @override
  String get holdNoItems => 'Aucun ouvrage chargé pour créer une réservation.';

  @override
  String get holdNoMembers => 'Aucun membre chargé pour créer une réservation.';

  @override
  String get reports => 'Rapports';

  @override
  String get reportSelectKind => 'Type de rapport';

  @override
  String get reportKindCirculation => 'Circulation';

  @override
  String get reportKindOverdue => 'Articles en retard';

  @override
  String get reportKindInventory => 'Inventaire';

  @override
  String get reportKindFines => 'Amendes';

  @override
  String get reportKindMembers => 'Meilleurs emprunteurs';

  @override
  String get reportRun => 'Générer le rapport';

  @override
  String get reportFrom => 'Du';

  @override
  String get reportTo => 'Au';

  @override
  String get reportGeneratedLabel => 'Généré';

  @override
  String get reportPeriodLabel => 'Période';

  @override
  String get reportDateHint => 'AAAA-MM-JJ';

  @override
  String get reportWindowNote => 'Ce rapport couvre une période donnée.';

  @override
  String get reportInvalidDates => 'Saisissez une date valide (AAAA-MM-JJ).';

  @override
  String get reportNoData => 'Aucun enregistrement pour ce rapport';

  @override
  String get reportSummary => 'Résumé';

  @override
  String reportGeneratedAt(String when) {
    return 'Généré $when';
  }

  @override
  String get reportExportCsv => 'Exporter CSV';

  @override
  String get reportExportPdf => 'Exporter PDF';

  @override
  String reportSaved(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get reportFailed => 'Impossible d\'exécuter le rapport.';

  @override
  String get reportExportFailed => 'Impossible d\'exporter le rapport.';

  @override
  String get onlyStaffRunReports =>
      'Seul le personnel peut exécuter des rapports.';

  @override
  String get exportDiagnostics => 'Exporter les diagnostics';

  @override
  String diagnosticsSaved(String path) {
    return 'Diagnostics enregistrés dans $path';
  }

  @override
  String get diagnosticsFailed => 'Impossible d\'exporter les diagnostics.';

  @override
  String get connectionMode => 'Mode de connexion';

  @override
  String get hostModeOption => 'Hôte (PC principal — serveur)';

  @override
  String get clientModeOption => 'Client (PC agent)';

  @override
  String get hostIpLabel => 'Adresse IP de l\'hôte';

  @override
  String get hostIpHelper =>
      'Saisissez l\'adresse IP du PC principal (ex. : 192.168.1.50)';

  @override
  String get appearance => 'Apparence';

  @override
  String get appearanceHint =>
      'Thème et identité de cet appareil. Non partagés avec les autres PC.';

  @override
  String get themeLabel => 'Thème';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get accentColor => 'Couleur d\'accentuation';

  @override
  String get brandName => 'Nom de la marque';

  @override
  String get brandNameHint =>
      'Nom du produit affiché dans la barre de titre (administrateurs uniquement)';

  @override
  String get featuresTitle => 'Fonctionnalités';

  @override
  String get featureFlagsHint =>
      'Activez ou désactivez les écrans optionnels. Les changements s\'appliquent immédiatement.';

  @override
  String get brandNameUpdated => 'Nom de la marque mis à jour';

  @override
  String get commandPalette => 'Palette de commandes';

  @override
  String get paletteSearchHint => 'Tapez pour rechercher des commandes…';

  @override
  String get paletteNoMatches => 'Aucune commande correspondante';

  @override
  String get systemHealthTitle => 'État du système';

  @override
  String get healthAppVersion => 'Version de l\'application';

  @override
  String get healthDatabaseSchema => 'Version du schéma de base';

  @override
  String get healthOperatingMode => 'Mode de fonctionnement';

  @override
  String get healthLanServer => 'Serveur LAN';

  @override
  String get healthServerRunning => 'À l\'écoute';

  @override
  String get healthServerStopped => 'Non à l\'écoute';

  @override
  String get healthConnection => 'Connexion';

  @override
  String get healthConnectedClients => 'Clients connectés';

  @override
  String healthClientCount(int n) {
    return '$n actif(s)';
  }

  @override
  String get healthLastBackup => 'Dernière sauvegarde';

  @override
  String get healthNever => 'Jamais';

  @override
  String get healthBackupFresh => 'Récente';

  @override
  String get healthBackupStale => 'En retard';

  @override
  String get notifications => 'Notifications';

  @override
  String get notifNone => 'Rien ne nécessite votre attention';

  @override
  String get notifLoading => 'Vérification…';

  @override
  String notifOverdue(int n) {
    return '$n prêt(s) en retard';
  }

  @override
  String notifHoldsReady(int n) {
    return '$n réservation(s) prête(s) au retrait';
  }

  @override
  String notifFinesPending(int n) {
    return '$n amende(s) à régler';
  }

  @override
  String get chat => 'Messagerie du personnel';

  @override
  String get chatInputHint => 'Message…';

  @override
  String get chatSend => 'Envoyer';

  @override
  String get chatEmpty => 'Aucun message.';

  @override
  String get chatUnavailable =>
      'La messagerie est indisponible pour le moment.';

  @override
  String helpVersionFooter(String version) {
    return 'Gestionnaire de Bibliothèque v$version';
  }

  @override
  String get settingsCatGeneral => 'Général';

  @override
  String get settingsCatLibrary => 'Bibliothèque';

  @override
  String get settingsCatData => 'Données & Sauvegarde';

  @override
  String get settingsCatSecurity => 'Sécurité';

  @override
  String get settingsCatAdvanced => 'Avancé';

  @override
  String get settingsSearchHint => 'Rechercher dans les paramètres';

  @override
  String get settingsUnsaved => 'Modifications non enregistrées';

  @override
  String get settingsRevert => 'Annuler les modifications';

  @override
  String get memberDetail => 'Profil du membre';

  @override
  String get memberNotFound => 'Membre introuvable';

  @override
  String get registered => 'Inscrit le';

  @override
  String get memberLoans => 'Emprunts actifs';

  @override
  String memberOverdueAlert(int n) {
    return '$n article(s) en retard nécessitent une attention';
  }

  @override
  String get noLoansForMember => 'Aucun emprunt pour ce membre';

  @override
  String get dueDate => 'Échéance';

  @override
  String get renewLoan => 'Renouveler cet emprunt';

  @override
  String get memberFines => 'Amendes';

  @override
  String get finePending => 'En attente';

  @override
  String get noPendingFines => 'Aucune amende en attente';

  @override
  String get memberReservations => 'Réservations';

  @override
  String get noActiveReservations => 'Aucune réservation active';

  @override
  String get holdReadyForPickup => 'Prêt à retirer';

  @override
  String get holdQueued => 'En file d\'attente';

  @override
  String get statusAvailable => 'Disponible';

  @override
  String get statusQueued => 'En file';

  @override
  String get needsAttention => 'Nécessite une attention';

  @override
  String get checkoutAction => 'Emprunt';

  @override
  String get reserveAction => 'Réserver';

  @override
  String copiesAvailableLabel(int a, int t) {
    return '$a sur $t exemplaires disponibles';
  }

  @override
  String get noCopiesAvailableForCheckout =>
      'Aucun exemplaire disponible pour l\'emprunt.';

  @override
  String get reserveSuccess => 'Réservation effectuée.';

  @override
  String get noMembersMatchSearch =>
      'Aucun membre ne correspond à la recherche.';

  @override
  String paginationSummary(int from, int to, int total) {
    return 'Affichage $from–$to sur $total articles';
  }

  @override
  String get keyboardShortcutsTitle => 'Raccourcis clavier';

  @override
  String get keyboardShortcutsContent =>
      'Ctrl+K ouvre la palette de commandes. Entrée exécute le premier résultat. Échap ferme les dialogues. Tab passe entre les champs ; les flèches naviguent dans les listes.';

  @override
  String get historySubjectPlaceholder =>
      'Filtrer par code ou identifiant de membre...';

  @override
  String get seeAllHistory => 'Voir tout l\'historique';

  @override
  String get noHistoryForRecord => 'Aucune activité récente pour cette fiche.';

  @override
  String get queueMoveUp => 'Monter dans la file';

  @override
  String get queueMoveDown => 'Descendre dans la file';

  @override
  String get queueOrderByItem => 'Filtrer par article pour réordonner la file';

  @override
  String get queueMoved => 'Ordre de la file mis à jour.';

  @override
  String get queueMoveFailed => 'Impossible de réordonner la file.';

  @override
  String get navCollapse => 'Réduire le menu';

  @override
  String get navExpand => 'Développer le menu';

  @override
  String get deleteMember => 'Supprimer le membre';

  @override
  String get confirmDeleteMember =>
      'Voulez-vous vraiment supprimer ce membre ? Ses emprunts et réservations doivent être réglés d\'abord.';

  @override
  String confirmDeleteItemNamed(String item) {
    return 'Voulez-vous vraiment supprimer cet article ($item) ?';
  }

  @override
  String reportGeneratedOn(String when) {
    return 'Généré le $when';
  }

  @override
  String userJoinedOn(String when) {
    return 'Inscrit le $when';
  }

  @override
  String get noNamedAccounts => 'Aucun compte nommé pour le moment';

  @override
  String get noNamedAccountsHint =>
      'Vous êtes connecté en tant qu\'administrateur intégré. Créez ci-dessous des comptes staff ou viewer pour accorder un accès limité à d\'autres utilisateurs.';
}
