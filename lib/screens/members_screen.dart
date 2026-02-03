import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/member.dart';
import '../l10n/app_localizations.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMemberDialog({Member? member}) {
    showDialog(
      context: context,
      builder: (context) => _MemberDialog(member: member),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final members = provider.members;
    
    // Simple client-side search for members
    final filteredMembers = _searchController.text.isEmpty
        ? members
        : members.where((m) => 
            m.firstName.toLowerCase().contains(_searchController.text.toLowerCase()) || 
            m.lastName.toLowerCase().contains(_searchController.text.toLowerCase()) ||
            m.memberId.toLowerCase().contains(_searchController.text.toLowerCase())
          ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.memberManagement), // TODO: Localize
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.search,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          Expanded(
            child: filteredMembers.isEmpty
                ? Center(child: Text(l10n.noItemsFound))
                : ListView.builder(
                    itemCount: filteredMembers.length,
                    itemBuilder: (context, index) {
                      final member = filteredMembers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: Text(member.firstName[0].toUpperCase()),
                          ),
                          title: Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('ID: ${member.memberId} • ${member.phone ?? "No Phone"}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showMemberDialog(member: member),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(l10n.deleteItem),
                                      content: Text(l10n.confirmDelete),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.deleteItem, style: const TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirm == true) {
                                    await provider.deleteMember(member.memberId);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMemberDialog(),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _MemberDialog extends StatefulWidget {
  final Member? member;

  const _MemberDialog({this.member});

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _idCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.member?.firstName);
    _lastNameCtrl = TextEditingController(text: widget.member?.lastName);
    _idCtrl = TextEditingController(text: widget.member?.memberId);
    _phoneCtrl = TextEditingController(text: widget.member?.phone);
    _emailCtrl = TextEditingController(text: widget.member?.email);
  }
  
  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<LibraryProvider>(context, listen: false);
      
      final member = Member(
        id: widget.member?.id,
        firstName: _firstNameCtrl.text,
        lastName: _lastNameCtrl.text,
        memberId: widget.member == null ? 'AUTO' : _idCtrl.text, // Auto-generate for new members
        phone: _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
        email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
        registeredAt: widget.member?.registeredAt ?? DateTime.now(),
      );

      try {
        if (widget.member == null) {
          await provider.addMember(member);
        } else {
          await provider.updateMember(member);
        }
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.member == null ? AppLocalizations.of(context)!.addMember : AppLocalizations.of(context)!.editMember),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _idCtrl,
                decoration: InputDecoration(
                  labelText: widget.member == null ? 'ID (Auto-généré)' : 'ID / Code',
                  border: const OutlineInputBorder(),
                  suffixIcon: widget.member == null ? const Icon(Icons.auto_awesome, color: Colors.orange) : null,
                ),
                readOnly: widget.member == null, // Read-only for new members
                enabled: widget.member != null, // Disabled for new members
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      decoration: InputDecoration(labelText: '${AppLocalizations.of(context)!.firstName}*', border: const OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      decoration: InputDecoration(labelText: '${AppLocalizations.of(context)!.lastName}*', border: const OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.phone, border: const OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.email, border: const OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          child: Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }
}
