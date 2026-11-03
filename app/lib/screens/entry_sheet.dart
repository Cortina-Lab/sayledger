import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';

/// Bottom sheet for one entry: details, edit, cancel (void) and its change log.
/// Returns true when the entry changed.
Future<bool> showEntrySheet(BuildContext context, Map<String, dynamic> entry, String currency) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _EntrySheet(entry: entry, currency: currency),
  );
  return changed ?? false;
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.entry, required this.currency});
  final Map<String, dynamic> entry;
  final String currency;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _amount = TextEditingController(text: majorText(widget.entry['amount_minor'] as int, widget.currency));
  late final _note = TextEditingController(text: widget.entry['note'] as String);
  late String _kind = widget.entry['kind'] as String;
  bool _editing = false;
  bool _busy = false;
  List<Map<String, dynamic>>? _history;

  Map<String, dynamic> get e => widget.entry;
  bool get _voided => e['voided_at'] != null;

  @override
  void initState() {
    super.initState();
    Api.instance.audit(entryId: e['id'] as int).then((h) {
      if (mounted) setState(() => _history = h);
    }).catchError((_) {});
  }

  Future<void> _save() async {
    final minor = parseMinor(_amount.text, widget.currency);
    if (minor == null) return showSnack(context, 'Enter a valid amount.');
    setState(() => _busy = true);
    try {
      await Api.instance.editEntry(e['id'] as int, {'amount_minor': minor, 'kind': _kind, 'note': _note.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (err) {
      if (mounted) showSnack(context, err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this entry?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('It stays in your book marked "Cancelled" and stops counting in every total.'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel entry')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.instance.voidEntry(e['id'] as int, reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (err) {
      if (mounted) showSnack(context, err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Map<String, dynamic> ev) {
    final cur = widget.currency;
    String amt(Map? m) => m?['amount_minor'] is int ? formatMoney(m!['amount_minor'] as int, cur) : '';
    return switch (ev['action']) {
      'create' => 'Added · ${amt(ev['after'] as Map?)}',
      'edit' => 'Edited · ${[
          if ((ev['before'] as Map)['amount_minor'] != (ev['after'] as Map)['amount_minor'])
            '${amt(ev['before'] as Map)} → ${amt(ev['after'] as Map)}',
          if ((ev['before'] as Map)['kind'] != (ev['after'] as Map)['kind'])
            '${kindLabels[(ev['before'] as Map)['kind']]} → ${kindLabels[(ev['after'] as Map)['kind']]}',
          if ((ev['before'] as Map)['note'] != (ev['after'] as Map)['note']) 'note changed',
        ].join(', ')}',
      'void' => 'Cancelled${((ev['after'] as Map?)?['reason'] ?? '').toString().isNotEmpty ? ' · ${(ev['after'] as Map)['reason']}' : ''}',
      _ => ev['action'] as String,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cur = widget.currency;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(kindLabels[e['kind']] ?? '', style: display(context, 22))),
            if (_voided) TagChip('Cancelled', bg: c.doubtSoft, fg: c.doubt),
          ]),
          const SizedBox(height: 4),
          Text(
            [if (e['party_name'] != null) e['party_name'], whenLabel(e['created_at'] as String), 'via ${e['source'] == 'ledger_photo' ? 'ledger photo' : e['source']}']
                .join(' · '),
            style: TextStyle(color: c.inkFaint),
          ),
          const SizedBox(height: 14),
          if (!_editing) ...[
            Text(formatMoney(e['amount_minor'] as int, cur),
                style: display(context, 38, color: _voided ? c.inkFaint : c.ink).copyWith(
                  decoration: _voided ? TextDecoration.lineThrough : null,
                )),
            if ((e['note'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(e['note'] as String, style: TextStyle(fontSize: 16, color: c.inkSoft)),
            ],
            if ((e['raw_text'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Panel(
                color: c.paper,
                padding: const EdgeInsets.all(12),
                child: Text('Heard: "${e['raw_text']}"', style: TextStyle(color: c.inkSoft, fontStyle: FontStyle.italic)),
              ),
            ],
            if (!_voided) ...[
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _void,
                    icon: Icon(Icons.block_rounded, size: 18, color: c.owes),
                    label: Text('Cancel', style: TextStyle(color: c.owes)),
                  ),
                ),
              ]),
            ],
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: kindLabels.entries.map((k) => DropdownMenuItem(value: k.key, child: Text(k.value))).toList(),
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: display(context, 24),
              decoration: InputDecoration(labelText: 'Amount ($cur)'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: 14),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Save changes')),
            TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Back')),
          ],
          const SizedBox(height: 20),
          const Eyebrow('Change log'),
          const SizedBox(height: 8),
          if (_history == null)
            Text('Loading…', style: TextStyle(color: c.inkFaint))
          else
            for (final ev in _history!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.circle, size: 7, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_describe(ev), style: TextStyle(color: c.inkSoft))),
                  Text(whenLabel(ev['at'] as String), style: TextStyle(color: c.inkFaint, fontSize: 12.5)),
                ]),
              ),
        ]),
      ),
    );
  }
}
