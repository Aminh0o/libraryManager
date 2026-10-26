import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../providers/library_provider.dart';
import '../services/receipt_payload.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/password_dialog.dart';

/// Self-Service Checkout Kiosk Mode.
/// A touch-friendly, high-contrast, locked-down kiosk interface allowing library
/// patrons to independently scan their card and check out or return books.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  Member? _activeMember;
  final List<LibraryItem> _sessionItems = [];
  final TextEditingController _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _onInputSubmitted(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    if (_activeMember == null) {
      // Step 1: Scanning member card
      final memberId = parseScannedMemberId(text);
      final match = provider.members
          .where(
            (m) =>
                m.memberId.toLowerCase() == memberId.toLowerCase() ||
                m.memberId.toLowerCase() == text.toLowerCase(),
          )
          .firstOrNull;

      if (match != null) {
        setState(() => _activeMember = match);
        showAppToast(context, match.fullName, kind: ToastKind.success);
      } else {
        showAppToast(
          context,
          l10n.noMembersMatchSearch,
          kind: ToastKind.warning,
        );
      }
    } else {
      // Step 2: Scanning books to checkout
      final item = provider.items
          .where(
            (i) => i.code == text || i.barcode == text || i.fullCode == text,
          )
          .firstOrNull;

      if (item != null) {
        if (_sessionItems.any((i) => i.code == item.code)) {
          showAppToast(
            context,
            'Book already scanned in this session',
            kind: ToastKind.info,
          );
        } else {
          setState(() => _sessionItems.add(item));
          showAppToast(context, item.designation, kind: ToastKind.success);
        }
      } else {
        showAppToast(context, l10n.itemNotFound, kind: ToastKind.warning);
      }
    }
  }

  Future<void> _scanViaCamera() async {
    final code = await showBarcodeScanner(context);
    if (code != null && mounted) {
      _onInputSubmitted(code);
    }
  }

  Future<void> _exitKiosk() async {
    final l10n = AppLocalizations.of(context)!;
    final passed = await showPasswordPrompt(context, title: l10n.exitKiosk);
    if (passed && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.local_library_outlined),
            const SizedBox(width: AppSpacing.sm),
            Text(l10n.selfCheckoutKiosk),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _exitKiosk,
            icon: const Icon(Icons.lock_outline),
            label: Text(l10n.exitKiosk),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: AppSpacing.allXxl,
            child: _activeMember == null
                ? _buildMemberScanStage(l10n, scheme, txt)
                : _buildBookCheckoutStage(l10n, scheme, txt),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberScanStage(
    AppLocalizations l10n,
    ColorScheme scheme,
    TextTheme txt,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_scanner, size: 100, color: scheme.primary),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          l10n.kioskWelcome,
          textAlign: TextAlign.center,
          style: txt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Hold your student / member ID card in front of the scanner',
          textAlign: TextAlign.center,
          style: txt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                autofocus: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l10n.scanBarcode,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    onPressed: _scanViaCamera,
                  ),
                ),
                onSubmitted: (val) {
                  _onInputSubmitted(val);
                  _inputCtrl.clear();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                _onInputSubmitted(_inputCtrl.text);
                _inputCtrl.clear();
              },
              icon: const Icon(Icons.check),
              label: Text(l10n.scanBarcode),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBookCheckoutStage(
    AppLocalizations l10n,
    ColorScheme scheme,
    TextTheme txt,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Member Welcome Banner
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    _activeMember!.avatarInitial,
                    style: txt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeMember!.fullName,
                        style: txt.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${l10n.colMember}: ${_activeMember!.memberId} | ${_activeMember!.memberType ?? ""}',
                        style: txt.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _activeMember = null;
                      _sessionItems.clear();
                    });
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Book Scan Bar
        Text(
          l10n.kioskScanBook,
          style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                autofocus: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: l10n.barcodeHint,
                  prefixIcon: const Icon(Icons.view_week_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    onPressed: _scanViaCamera,
                  ),
                ),
                onSubmitted: (val) {
                  _onInputSubmitted(val);
                  _inputCtrl.clear();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                _onInputSubmitted(_inputCtrl.text);
                _inputCtrl.clear();
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.scanBarcode),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // Scanned Books List
        Expanded(
          child: _sessionItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 64,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.kioskScanBook,
                        style: txt.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : Card(
                  child: ListView.separated(
                    itemCount: _sessionItems.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = _sessionItems[idx];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${idx + 1}')),
                        title: Text(item.designation),
                        subtitle: Text(
                          '${l10n.barcode}: ${item.barcode ?? item.code}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            setState(() => _sessionItems.removeAt(idx));
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Finish Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
          onPressed: _sessionItems.isEmpty
              ? null
              : () async {
                  final provider = Provider.of<LibraryProvider>(
                    context,
                    listen: false,
                  );
                  for (final item in _sessionItems) {
                    try {
                      await provider.checkOutItem(item, _activeMember!);
                    } catch (_) {}
                  }
                  if (mounted) {
                    showAppToast(
                      context,
                      'Checkout completed successfully!',
                      kind: ToastKind.success,
                    );
                    setState(() {
                      _activeMember = null;
                      _sessionItems.clear();
                    });
                  }
                },
          icon: const Icon(Icons.done_all),
          label: Text(
            'Complete Checkout (${_sessionItems.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
