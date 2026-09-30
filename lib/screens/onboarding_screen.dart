import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/onboarding_service.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';

/// Phase K (frontend reconstruction): the first-run setup wizard rebuilt on
/// the centralized design system -- scheme colors + text roles + tokens
/// instead of the old scattered `Colors.orange` / `fontSize:` literals. The
/// wizard LOGIC (page order, password-step validation, locale switching,
/// password save, setup-complete + navigation) is unchanged; only the
/// presentation moved onto the same tokens every other screen consumes.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _numPages = 4;

  // Step state
  final TextEditingController _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _pageController.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _numPages - 1) {
      if (_currentPage == 1) {
        // Password step
        if (!_formKey.currentState!.validate()) return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeSetup();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeSetup() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);

    // Save password if provided
    if (_passwordCtrl.text.isNotEmpty) {
      await provider.changePassword(_passwordCtrl.text);
    }

    await OnboardingService.markSetupComplete();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildWelcomeStep(l10n),
                  _buildPasswordStep(l10n),
                  _buildConfigSummaryStep(l10n),
                  _buildFinalStep(l10n),
                ],
              ),
            ),
            _buildBottomBar(l10n),
          ],
        ),
      ),
    );
  }

  /// Shared page chrome: centered, width-capped column with the theme's
  /// subtitle heading + muted description under a hero icon (§5/§8/§38).
  Widget _page({required Widget child, bool scrollable = false}) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
      child: child,
    );
    final padded = Padding(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          primary: false,
          // The inner Padding is outside this scroller so an overflowing
          // short window still reveals the bottom content when scrolled.
          child: SizedBox(height: constraints.maxHeight, child: padded),
        ),
      ),
    );
  }

  Widget _stepHeading(BuildContext context, String title, String message) {
    final txt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: txt.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: txt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildWelcomeStep(AppLocalizations l10n) {
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final currentLocale = provider.locale.languageCode;

    return _page(
      scrollable: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: AppIcon.hero,
            color: scheme.primary,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          // Triple-language greeting: the welcome itself stays in all three
          // scripts on purpose, so it is readable before a locale is chosen.
          Text(
            'Welcome',
            textAlign: TextAlign.center,
            style: txt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'Bienvenue',
            textAlign: TextAlign.center,
            style: txt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'مرحباً',
            textAlign: TextAlign.center,
            style: txt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _stepHeading(context, '', l10n.setupLanguageDesc),
          const SizedBox(height: AppSpacing.xxxl),
          // Language selector buttons
          _buildLanguageButton(
            context,
            provider,
            'English',
            'en',
            currentLocale == 'en',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildLanguageButton(
            context,
            provider,
            'Français',
            'fr',
            currentLocale == 'fr',
          ),
          const SizedBox(height: AppSpacing.md),
          _buildLanguageButton(
            context,
            provider,
            'العربية',
            'ar',
            currentLocale == 'ar',
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageButton(
    BuildContext context,
    LibraryProvider provider,
    String label,
    String code,
    bool isSelected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => provider.setLocale(Locale(code)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : AppBorder.width,
          ),
          backgroundColor: isSelected
              ? scheme.primary.withValues(alpha: 0.1)
              : null,
          foregroundColor: isSelected ? scheme.primary : scheme.onSurface,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        ),
        child: Text(
          label,
          style: txt.titleMedium?.copyWith(
            color: isSelected ? scheme.primary : scheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStep(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return _page(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.security_outlined,
            size: AppIcon.xl * 2,
            color: scheme.primary,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _stepHeading(context, l10n.stepSecurity, l10n.setupPasswordDesc),
          const SizedBox(height: AppSpacing.xxxl),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.password,
                prefixIcon: const Icon(Icons.lock_outline, size: AppIcon.md),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? l10n.requiredField : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSummaryStep(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return _page(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tune_outlined,
            size: AppIcon.xl * 2,
            color: scheme.primary,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _stepHeading(context, l10n.stepConfiguration, l10n.setupConfigDesc),
          const SizedBox(height: AppSpacing.xxxl),
          Card(
            child: Padding(
              padding: AppSpacing.allLg,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.category_outlined,
                      color: scheme.primary,
                      size: AppIcon.lg,
                    ),
                    title: Text(l10n.configPrefixesLabel),
                    subtitle: Text(l10n.configPrefixesDesc),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.place_outlined,
                      color: scheme.primary,
                      size: AppIcon.lg,
                    ),
                    title: Text(l10n.configAttributesLabel),
                    subtitle: Text(l10n.configAttributesDesc),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalStep(AppLocalizations l10n) {
    final txt = Theme.of(context).textTheme;
    return _page(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: AppIcon.hero,
            color: AppStatus.success,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            l10n.setupComplete,
            textAlign: TextAlign.center,
            style: txt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.setupCompleteDesc,
            textAlign: TextAlign.center,
            style: txt.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _numPages - 1;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xxxl,
        AppSpacing.lg,
        AppSpacing.xxxl,
        AppSpacing.xxl,
      ),
      child: Row(
        children: [
          // Previous (first/last steps have no where to go back to / the
          // finish action speaks for itself).
          if (_currentPage > 0 && !isLastPage)
            TextButton.icon(
              onPressed: _previousPage,
              icon: const Icon(Icons.arrow_back, size: AppIcon.md),
              label: Text(l10n.cancel), // Or use a 'Previous' key if available
            )
          else
            const SizedBox(width: AppSizing.topBarHeight),

          // Progress dots + step count (colorblind-safe: position is also
          // text, not just the highlighted dot).
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _numPages,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentPage == index
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${_currentPage + 1} / $_numPages',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Next / Finish
          FilledButton.icon(
            onPressed: _nextPage,
            icon: isLastPage
                ? const Icon(Icons.check, size: AppIcon.md)
                : const Icon(Icons.arrow_forward, size: AppIcon.md),
            label: Text(isLastPage ? l10n.finish : l10n.next),
          ),
        ],
      ),
    );
  }
}
