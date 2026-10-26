import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_info.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import 'onboarding_screen.dart';

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
          const SizedBox(height: AppSpacing.xl),
          _brandFooter(context, l10n),
        ],
      ),
    );
  }

  /// Phase 11 branding: "Powered by Evenlio" with the verified contact details
  /// (website + email) as tappable rows. Only the two fields Evenlio actually
  /// publishes are shown; the postal address / phone are withheld until the
  /// brand lists them (see app_info.dart) rather than invented.
  Widget _brandFooter(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    Future<void> open(String url) async {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    Widget row(IconData icon, String label, String url) => InkWell(
      borderRadius: AppRadius.tile,
      onTap: () => open(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIcon.md, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                // DEF-05 discipline: a URL / email is machine-format text and
                // must stay LTR even under an Arabic RTL layout.
                textDirection: TextDirection.ltr,
                style: txt.bodyMedium?.copyWith(color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );

    return Center(
      child: Column(
        children: [
          Text(
            l10n.poweredByEvenlio(kBrandName),
            style: txt.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          row(Icons.language_outlined, kBrandUrl, kBrandUrl),
          row(Icons.mail_outline, kBrandEmail, 'mailto:$kBrandEmail'),
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

    // Phase 15: the tutorial map now mirrors the product spec's eighteen
    // learning paths, grouped into six themes, instead of the old nine ad-hoc
    // steps. Every title/body is a localized ARB key (EN/FR/AR) so the map both
    // covers the whole product and reads in the operator's own language. The
    // path number is the shared 1..19 ordinal across all groups.
    final groups = <_TutorialGroup>[
      _TutorialGroup(l10n.tgroupStart, [
        _TutorialPath(
          l10n.tstep1Title,
          l10n.tstep1Body,
          Icons.admin_panel_settings,
        ),
        _TutorialPath(
          l10n.tstep2Title,
          l10n.tstep2Body,
          Icons.space_dashboard_outlined,
        ),
      ]),
      _TutorialGroup(l10n.tgroupCatalog, [
        _TutorialPath(
          l10n.tstep3Title,
          l10n.tstep3Body,
          Icons.library_add_outlined,
        ),
        _TutorialPath(l10n.tstep4Title, l10n.tstep4Body, Icons.badge_outlined),
        _TutorialPath(l10n.tstep5Title, l10n.tstep5Body, Icons.qr_code_scanner),
      ]),
      _TutorialGroup(l10n.tgroupCirc, [
        _TutorialPath(l10n.tstep6Title, l10n.tstep6Body, Icons.swap_horiz),
        _TutorialPath(
          l10n.tstep7Title,
          l10n.tstep7Body,
          Icons.event_busy_outlined,
        ),
        _TutorialPath(l10n.tstep8Title, l10n.tstep8Body, Icons.bookmark_added),
        _TutorialPath(
          l10n.tstep9Title,
          l10n.tstep9Body,
          Icons.inventory_outlined,
        ),
      ]),
      _TutorialGroup(l10n.tgroupData, [
        _TutorialPath(l10n.tstep10Title, l10n.tstep10Body, Icons.search),
        _TutorialPath(l10n.tstep11Title, l10n.tstep11Body, Icons.assessment),
      ]),
      _TutorialGroup(l10n.tgroupLan, [
        _TutorialPath(l10n.tstep12Title, l10n.tstep12Body, Icons.lan_outlined),
        _TutorialPath(
          l10n.tstep13Title,
          l10n.tstep13Body,
          Icons.settings_ethernet,
        ),
        _TutorialPath(
          l10n.tstep14Title,
          l10n.tstep14Body,
          Icons.print_outlined,
        ),
      ]),
      _TutorialGroup(l10n.tgroupMaint, [
        _TutorialPath(
          l10n.tstep15Title,
          l10n.tstep15Body,
          Icons.backup_outlined,
        ),
        _TutorialPath(
          l10n.tstep16Title,
          l10n.tstep16Body,
          Icons.shield_outlined,
        ),
        _TutorialPath(l10n.tstep17Title, l10n.tstep17Body, Icons.tune),
        _TutorialPath(
          l10n.tstep18Title,
          l10n.tstep18Body,
          Icons.system_update_alt,
        ),
        _TutorialPath(
          l10n.tstep19Title,
          l10n.tstep19Body,
          Icons.monitor_heart_outlined,
        ),
      ]),
    ];

    // A global ordinal so the six groups still read as one 1..19 sequence.
    var ordinal = 0;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Card(
          elevation: 0,
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            leading: CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: const Icon(Icons.play_arrow),
            ),
            title: Text(
              l10n.launchWalkthrough,
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(l10n.walkthroughDescription, style: txt.bodySmall),
            trailing: Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
                    );
                  },
                  child: Text(l10n.setupRoadmap),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
    for (final group in groups) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.lg,
            bottom: AppSpacing.sm,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              group.label,
              style: txt.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
      for (final path in group.paths) {
        ordinal++;
        final number = '$ordinal';
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              key: Key('tutorialPath-$ordinal'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text(
                    number,
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
                      Row(
                        children: [
                          Icon(
                            path.icon,
                            size: AppIcon.sm,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              path.title,
                              style: txt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        path.body,
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
          ),
        );
      }
    }

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
            child: Column(children: children),
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

/// One learning path in the tutorial map. The title/body are the localized ARB
/// strings resolved for the current locale; [icon] is the visual anchor.
class _TutorialPath {
  const _TutorialPath(this.title, this.body, this.icon);
  final String title;
  final String body;
  final IconData icon;
}

/// A themed group of [paths] under a localized [label].
class _TutorialGroup {
  const _TutorialGroup(this.label, this.paths);
  final String label;
  final List<_TutorialPath> paths;
}
