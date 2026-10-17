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
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    // TUTORIAL-11n: the step text used to be hardcoded English, so French and
    // Arabic operators opened the one screen meant to TEACH them the product and
    // got a wall of a language they may not read. Every label now comes from the
    // localized ARB (EN/FR/AR) so the tutorial actually tutorials, in the
    // operator's own language and text direction.
    final steps = [
      ('1', l10n.tstep1Title, l10n.tstep1Body, Icons.admin_panel_settings),
      ('2', l10n.tstep2Title, l10n.tstep2Body, Icons.library_books),
      ('3', l10n.tstep3Title, l10n.tstep3Body, Icons.badge),
      ('4', l10n.tstep4Title, l10n.tstep4Body, Icons.swap_horiz),
      ('5', l10n.tstep5Title, l10n.tstep5Body, Icons.bookmark_added),
      ('6', l10n.tstep6Title, l10n.tstep6Body, Icons.assessment),
      ('7', l10n.tstep7Title, l10n.tstep7Body, Icons.lan),
      ('8', l10n.tstep8Title, l10n.tstep8Body, Icons.backup),
      ('9', l10n.tstep9Title, l10n.tstep9Body, Icons.system_update),
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
          l10n.tutorialMapTitle,
          style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(l10n.tutorialMapSubtitle),
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
    final l10n = AppLocalizations.of(context)!;
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
          l10n.hardwareGuideTitle,
          style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(l10n.hardwareGuideSubtitle),
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
                  l10n.hwScanTitle,
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.hwScanBody,
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.hwPrintTitle,
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.hwPrintBody,
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.hwDpiTitle,
                  style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.hwDpiBody,
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
