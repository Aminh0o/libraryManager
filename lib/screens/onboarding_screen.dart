import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/onboarding_service.dart';
import '../providers/library_provider.dart';

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
      if (_currentPage == 1) { // Password step
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

  Widget _buildWelcomeStep(AppLocalizations l10n) {
    final provider = Provider.of<LibraryProvider>(context);
    final currentLocale = provider.locale.languageCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_books, size: 100, color: Colors.orange),
          const SizedBox(height: 32),
          // Triple language welcome
          const Text(
            'Welcome',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Bienvenue',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const Text(
            'مرحباً',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.setupLanguageDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          // Language selector buttons
          _buildLanguageButton(context, provider, 'English', 'en', currentLocale == 'en'),
          const SizedBox(height: 12),
          _buildLanguageButton(context, provider, 'Français', 'fr', currentLocale == 'fr'),
          const SizedBox(height: 12),
          _buildLanguageButton(context, provider, 'العربية', 'ar', currentLocale == 'ar'),
        ],
      ),
    );
  }

  Widget _buildLanguageButton(BuildContext context, LibraryProvider provider, String label, String code, bool isSelected) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => provider.setLocale(Locale(code)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: isSelected ? Colors.orange : Colors.grey.shade300, width: 2),
          backgroundColor: isSelected ? Colors.orange.withValues(alpha: 0.1) : null,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            color: isSelected ? Colors.orange : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStep(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.orange),
            const SizedBox(height: 32),
            Text(
              l10n.stepSecurity,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.setupPasswordDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              validator: (v) => (v == null || v.isEmpty) ? l10n.requiredField : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSummaryStep(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.settings, size: 80, color: Colors.orange),
          const SizedBox(height: 32),
          Text(
            l10n.stepConfiguration,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.setupConfigDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                   ListTile(
                    leading: Icon(Icons.category, color: Colors.orange),
                    title: Text('Code Prefixes (LIV, REV, etc.)'),
                    subtitle: Text('Default values will be initialized.'),
                  ),
                   ListTile(
                    leading: Icon(Icons.place, color: Colors.orange),
                    title: Text('Dynamic Attributes'),
                    subtitle: Text('Locations, Statuses, and Stocks.'),
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
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 100, color: Colors.green),
          const SizedBox(height: 32),
          Text(
            l10n.setupComplete,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.setupCompleteDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button
          _currentPage > 0 
              ? TextButton(
                  onPressed: _previousPage,
                  child: Text(
                    l10n.cancel, // Or use a 'Previous' key if available
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : const SizedBox(width: 80), // Spacer
          
          // Dots indicator
          Row(
            children: List.generate(
              _numPages,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index ? Colors.orange : Colors.grey.shade300,
                ),
              ),
            ),
          ),
          
          // Next Button
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _currentPage == _numPages - 1 ? l10n.finish : l10n.next,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
