import 'package:flutter/material.dart';
import '../config/app_info.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';

/// Phase L (frontend reconstruction): help center moved onto the design
/// system (themed AppBar, scheme-tinted definition card, token spacing, text
/// roles instead of fontSize/bold literals). Content and the ARC-08 honest
/// version footer are unchanged.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpCenter)),
      body: ListView(
        padding: AppSpacing.allXxl,
        children: [
          _buildAppDefinition(context, l10n),
          const SizedBox(height: AppSpacing.xxl),
          _buildTutorialMap(context),
          const SizedBox(height: AppSpacing.xxl),
          _buildHardwareGuide(context),
          const SizedBox(height: AppSpacing.xxl),
          _buildHelpSection(
            context,
            icon: Icons.people_outline,
            title: l10n.helpMembersTitle,
            content: l10n.helpMembersContent,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildHelpSection(
            context,
            icon: Icons.assignment_ind_outlined,
            title: l10n.helpLoansTitle,
            content: l10n.helpLoansContent,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildHelpSection(
            context,
            icon: Icons.sync,
            title: l10n.helpSyncTitle,
            content: l10n.helpSyncContent,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildHelpSection(
            context,
            icon: Icons.qr_code_scanner,
            title: l10n.helpBarcodeTitle,
            content: l10n.helpBarcodeContent,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Core Workflow Recovery: the shortcuts were real but invisible --
          // an operator only learned Ctrl+K existed by accident. Documenting
          // them in the same help center they already visit turns a hidden
          // efficiency into an obvious one.
          _buildHelpSection(
            context,
            icon: Icons.keyboard_outlined,
            title: l10n.keyboardShortcutsTitle,
            content: l10n.keyboardShortcutsContent,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Center(
            // ARC-08: this used to read 'v1.2.0' -- a version the product never
            // shipped, which misleads support and triage. It now reports the
            // SAME constant the diagnostics bundle and the health center print,
            // so the three can never drift apart again.
            child: Text(
              l10n.helpVersionFooter(kAppVersion),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppDefinition(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.dialog,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: AppSpacing.allXxl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: scheme.primary,
                  size: AppIcon.xl,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.appDefinitionTitle,
                    style: txt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.appDefinitionContent,
              style: txt.bodyLarge?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: scheme.primary, size: AppIcon.md),
        ),
        title: Text(
          title,
          style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Text(content, style: txt.bodyMedium?.copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialMap(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final steps = [
      (
        '1',
        'System Initialization & Admin Setup',
        'Complete first-run onboarding, establish a resilient administrator credential, and initialize the embedded SQLite engine.',
        Icons.admin_panel_settings,
      ),
      (
        '2',
        'Catalog & Inventory Management',
        'Add titles with ISBN-10/13 validation, generate unique barcodes, register individual copy condition notes, or bulk import via CSV.',
        Icons.library_books,
      ),
      (
        '3',
        'Member Registration & QR Cards',
        'Register patrons, configure borrowing tiers and limits, and generate official membership cards with opaque QR codes.',
        Icons.badge,
      ),
      (
        '4',
        'Circulation Desk (Checkout & Returns)',
        'Rapidly scan book barcodes via USB keyboard-wedge scanners, process returns, calculate overdue fines, and print official circulation receipts.',
        Icons.swap_horiz,
      ),
      (
        '5',
        'Reservation Queues & Hold Tickets',
        'Queue member reservations with FIFO ordering, automatic promotion upon return, walk-up protection, and printable hold pickup tickets.',
        Icons.bookmark_added,
      ),
      (
        '6',
        'Financial Auditing & Reporting',
        'Audit circulation history, track collected fines, and export injection-sanitized (CWE-1236) CSV and PDF analytics.',
        Icons.assessment,
      ),
      (
        '7',
        'Multi-Station Private LAN Mode',
        'Enable Windows Firewall rules to securely discover and sync workstations across the local subnet with Bearer authentication.',
        Icons.lan,
      ),
      (
        '8',
        'Disaster Recovery & Snapshots',
        'Create point-in-time database snapshots in WAL mode with pre-restore safety backups and zero data loss guarantees.',
        Icons.backup,
      ),
      (
        '9',
        'In-App Verification & Updates',
        'Check for official updates, stream downloads over HTTPS, and automatically verify SHA-256 integrity checksums.',
        Icons.system_update,
      ),
    ];

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.map_outlined,
            color: scheme.primary,
            size: AppIcon.md,
          ),
        ),
        title: Text(
          'Complete Operational Tutorial Map',
          style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Sequential 9-step guide from initial setup to day-to-day desk operations',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: steps.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primary,
                        child: Text(
                          s.$1,
                          style: txt.labelSmall?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.$2,
                              style: txt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.$3,
                              style: txt.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareGuide(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scheme.secondary.withValues(alpha: 0.12),
          child: Icon(
            Icons.print_outlined,
            color: scheme.secondary,
            size: AppIcon.md,
          ),
        ),
        title: Text(
          'Hardware Peripherals & Desk Setup Guide',
          style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Configuring USB Barcode Scanners, Thermal Receipt Printers, and Windows scaling',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Barcode & QR Scanner Configuration (USB / Bluetooth HID)',
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect any standard USB or wireless handheld barcode scanner in HID Keyboard Wedge mode. Ensure the scanner is configured to transmit a trailing Enter key (\\r or \\n) suffix after every scan. This allows instant book and patron identification without touching the mouse.',
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '2. Receipt Printer Setup (58mm / 80mm / A6 Office Paper)',
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Library Manager exports vector PDF slips for all loan receipts, return slips, hold pickup tickets, and member cards. To print directly to a thermal receipt printer (such as Epson POS or generic 80mm roll), set your printer default paper size to Roll Paper or A6 in Windows Settings > Printers.',
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '3. High-DPI Display Scaling (100% to 200%)',
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'The user interface dynamically adjusts to Windows display scaling (100%, 125%, 150%, 200%) and supports full window resizing, multi-monitor dragging, and Dark/Light themes without visual tearing.',
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
