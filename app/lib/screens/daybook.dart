import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_sheet.dart';

/// Every entry in the book, newest first, with period + type filters.
class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});

  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  Period _period = Period.presets()[1];
  String? _kind;
  bool _showCancelled = false;
  List<Map<String, dynamic>>? _rows;
  String _cur = 'INR';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => (_error = null, _rows = null));
    try {
      final r = await Api.instance.entries(
          start: ymd(_period.start), end: ymd(_period.end), kind: _kind, includeVoided: _showCancelled);
      _cur = r['currency'] as String;
      if (mounted) setState(() => _rows = (r['entries'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = _rows;
    final live = rows?.where((e) => e['voided_at'] == null) ?? const [];
    int sum(String k) => live.where((e) => e['kind'] == k).fold(0, (a, e) => a + (e['amount_minor'] as int));
    return Scaffold(
      appBar: innerBar('Day book'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: PeriodBar(value: _period, onChanged: (p) {
            _period = p;
            _load();
          }),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final k in [null, ...kindLabels.keys])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(k == null ? 'All types' : kindLabels[k]!),
                  selected: _kind == k,
                  showCheckmark: false,
                  selectedColor: c.accentSoft,
                  backgroundColor: c.card,
                  side: BorderSide(color: _kind == k ? c.accent : c.line),
                  shape: const StadiumBorder(),
                  onSelected: (_) {
                    _kind = k;
                    _load();
                  },
                ),
              ),
            FilterChip(
              label: const Text('Show cancelled'),
              selected: _showCancelled,
              selectedColor: c.doubtSoft,
              backgroundColor: c.card,
              side: BorderSide(color: c.line),
              shape: const StadiumBorder(),
              onSelected: (v) {
                _showCancelled = v;
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : rows == null
                  ? const Working('Opening the day book…')
                  : RefreshIndicator(
                      color: c.accent,
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                        Panel(
                          padding: const EdgeInsets.all(14),
                          child: Column(children: [
                            Row(children: [
                              Expanded(child: _mini('Credit given', sum('credit_given'))),
                              Expanded(child: _mini('Payments', sum('payment_received'))),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: _mini('Cash sales', sum('cash_sale'))),
                              Expanded(child: _mini('Expenses', sum('expense'))),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Text('${live.length} entr${live.length == 1 ? 'y' : 'ies'} · totals exclude cancelled',
                            style: TextStyle(color: c.inkFaint, fontSize: 13)),
                        const SizedBox(height: 10),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('No entries in this period.', textAlign: TextAlign.center, style: TextStyle(color: c.inkSoft)),
                          ),
                        for (final e in rows) EntryTile(entry: e, currency: _cur, onChanged: _load),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _mini(String label, int minor) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(label),
        const SizedBox(height: 2),
        Text(formatMoney(minor, _cur), style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
      ]);
}

/// One row in a list of entries; tap opens the entry sheet.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.currency, required this.onChanged, this.showParty = true});
  final Map<String, dynamic> entry;
  final String currency;
  final VoidCallback onChanged;
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = entry;
    final voided = e['voided_at'] != null;
    final kind = e['kind'] as String;
    final inflow = kind == 'payment_received' || kind == 'cash_sale';
    final tone = voided ? c.inkFaint : kind == 'credit_given' ? c.owes : inflow ? c.advance : c.inkSoft;
    final sign = kind == 'payment_received' ? '−' : kind == 'credit_given' ? '+' : '';
    final title = showParty && e['party_name'] != null ? '${e['party_name']}' : kindLabels[kind]!;
    final sub = [
      if (showParty && e['party_name'] != null) kindLabels[kind],
      if ((e['note'] as String).isNotEmpty) e['note'],
      whenLabel(e['created_at'] as String),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: voided ? 0.6 : 1,
        child: Panel(
          padding: EdgeInsets.zero,
          onTap: () async {
            if (await showEntrySheet(context, e, currency)) onChanged();
          },
          child: ListTile(
            leading: CircleAvatar(backgroundColor: c.paper, child: Icon(sourceIcon(e['source'] as String), color: c.inkSoft, size: 20)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(voided ? 'Cancelled · $sub' : sub, style: TextStyle(color: c.inkFaint), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Text(
              '$sign${formatMoney(e['amount_minor'] as int, currency)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tone,
                decoration: voided ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
