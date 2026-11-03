import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';

/// Every change ever made to the book, newest first. Nothing is hidden.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.currency});
  final String currency;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final ev = await Api.instance.audit();
      if (mounted) setState(() => _events = ev);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  (IconData, String) _describe(Map<String, dynamic> ev) {
    String amt(dynamic m) => m is Map && m['amount_minor'] is int ? formatMoney(m['amount_minor'] as int, widget.currency) : '';
    final before = ev['before'], after = ev['after'];
    return switch (ev['action']) {
      'create' => (Icons.add_circle_outline, 'Entry #${ev['entry_id']} added · ${kindLabels[(after as Map)['kind']]} ${amt(after)}'),
      'edit' => (Icons.edit_outlined, 'Entry #${ev['entry_id']} edited · ${amt(before)} → ${amt(after)}'),
      'void' => (Icons.block_rounded, 'Entry #${ev['entry_id']} cancelled${(after as Map?)?['reason']?.toString().isNotEmpty == true ? ' · ${after!['reason']}' : ''}'),
      'party_create' => (Icons.person_add_alt_1_outlined, 'Customer added · ${(after as Map)['name']}'),
      'party_edit' => (Icons.manage_accounts_outlined, 'Customer updated · ${(after as Map)['name']}'),
      _ => (Icons.history, ev['action'] as String),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: innerBar('Activity log'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _events == null
              ? const Working('Loading activity…')
              : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                  Text('Every add, edit and cancel is recorded. Entries are never silently deleted.',
                      style: TextStyle(color: c.inkSoft)),
                  const SizedBox(height: 14),
                  if (_events!.isEmpty) Text('No activity yet.', style: TextStyle(color: c.inkFaint)),
                  for (final ev in _events!)
                    Builder(builder: (context) {
                      final (icon, text) = _describe(ev);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(radius: 17, backgroundColor: c.accentSoft, child: Icon(icon, size: 18, color: c.accent)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(text, style: const TextStyle(fontSize: 15)),
                              Text(whenLabel(ev['at'] as String), style: TextStyle(color: c.inkFaint, fontSize: 12.5)),
                            ]),
                          ),
                        ]),
                      );
                    }),
                ]),
    );
  }
}
