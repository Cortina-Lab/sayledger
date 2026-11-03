import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customer_detail.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map<String, dynamic>>? _parties;
  String _cur = 'INR';
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.instance.parties();
      _cur = r['currency'] as String;
      final list = (r['parties'] as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (b['balance_minor'] as int).compareTo(a['balance_minor'] as int));
      if (mounted) setState(() => _parties = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = (_parties ?? []).where((p) => (p['name'] as String).toLowerCase().contains(_query)).toList();
    return Scaffold(
      appBar: innerBar('Customers'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _parties == null
              ? const Working('Loading customers…')
              : RefreshIndicator(
                  color: context.c.accent,
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search customers'),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    if (_parties!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No customers yet. They appear here after you confirm your first entry.', textAlign: TextAlign.center),
                      ),
                    for (final p in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Panel(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: CircleAvatar(backgroundColor: context.c.accentSoft, foregroundColor: context.c.accent, child: Text((p['name'] as String).characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700))),
                            title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                            subtitle: Text(_status(p['balance_minor'] as int), style: TextStyle(color: context.c.inkFaint)),
                            trailing: Text(formatMoney((p['balance_minor'] as int).abs(), _cur),
                                style: display(context, 20, color: _color(p['balance_minor'] as int))),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(partyId: p['id'] as int)));
                              _load();
                            },
                          ),
                        ),
                      ),
                  ]),
                ),
    );
  }

  String _status(int b) => b > 0 ? 'Owes you' : b < 0 ? 'Paid in advance' : 'Settled';
  Color _color(int b) => b > 0 ? context.c.owes : b < 0 ? context.c.advance : context.c.inkFaint;
}
