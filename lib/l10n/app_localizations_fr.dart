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
  String get changePassword => 'Changer le mot de passe';

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
  String get connectedDevices => 'Appareils Connectés';

  @override
  String get connectedViaLan => 'Connecté via LAN';

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
  String get quickScan => 'Scan Rapide';

  @override
  String get appDefinitionTitle => 'C\'est quoi Library Manager ?';

  @override
  String get appDefinitionContent =>
      'Library Manager est une solution de bureau professionnelle conçue pour les bibliothèques et centres de documentation algériens. Il fournit des outils spécialisés pour la gestion des stocks, la synchronisation via LAN et le suivi par codes-barres. Le système prend en charge la catégorisation complète en anglais, français et arabe selon les normes nationales.';
}
