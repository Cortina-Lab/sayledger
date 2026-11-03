import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows what the model heard (or the page it read) and what it proposes.
/// Nothing is saved until the shopkeeper taps Confirm.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen._(this.load, this.source, {this.photo});

  factory ConfirmScreen.fromText(String text) => ConfirmScreen._(() => Api.instance.proposeText(text), 'manual');

  factory ConfirmScreen.fromVoice(Uint8List wav) => ConfirmScreen._(() => Api.instance.proposeVoice(wav), 'voice');

  factory ConfirmScreen.fromPhoto(Uint8List image, String mime) => ConfirmScreen._(() async {
        final r = await Api.instance.readLedgerPhoto(image, mime);
        return {'heard': '', 'proposals': r['rows'], 'currency': r['currency'], 'unreadable': r['unreadable']};
      }, 'ledger_photo', photo: image);

  final Future<Map<String, dynamic>> Function() load;
  final String source;
  final Uint8List? photo;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _Draft {
  _Draft(Map<String, dynamic> p, String cur)
      : name = TextEditingController(text: (p['party_name'] ?? '') as String),
        amount = TextEditingController(text: majorText(p['amount_minor'] as int, cur)),
        note = TextEditingController(text: (p['note'] ?? '') as String),
        kind = p['kind'] as String,
        partyId = p['party_id'] as int?,
        originalName = (p['party_name'] ?? '') as String,
        doubt = List<String>.from(p['doubt'] ?? const []),
        confidence = (p['confidence'] as num?)?.toDouble(),
        date = p['date'] as String?;

  final TextEditingController name, amount, note;
  String kind;
  final int? partyId;
  final String originalName;
  final List<String> doubt;
  final double? confidence;
  final String? date;
  bool keep = true;
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  String _heard = '';
  String _cur = 'INR';
  int _unreadable = 0;
  List<_Draft>? _drafts;
  String? _error;
  bool _saving = false;

  bool get _isPhoto => widget.source == 'ledger_photo';

  @override
  void initState() {
    super.initState();
    _propose();
  }

  Future<void> _propose() async {
    setState(() => (_error = null, _drafts = null));
    try {
      final r = await widget.load();
      _cur = r['currency'] as String;
      _heard = (r['heard'] ?? '') as String;
      _unreadable = (r['unreadable'] ?? 0) as int;
      final list = (r['proposals'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _drafts = list.map((p) => _Draft(p, _cur)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _confirm() async {
    final out = <Map<String, dynamic>>[];
    for (final d in _drafts!.where((d) => d.keep)) {
      final minor = parseMinor(d.amount.text, _cur);
      final name = d.name.text.trim();
      if (minor == null) return showSnack(context, 'Please enter a valid amount on every selected card.');
      if ((d.kind == 'credit_given' || d.kind == 'payment_received') && name.isEmpty) {
        return showSnack(context, 'Credit and payments need a customer name.');
      }
      out.add({
        'party_name': name.isEmpty ? null : name,
        // Keep the matched customer only if the name wasn't edited.
        'party_id': name == d.originalName ? d.partyId : null,
        'kind': d.kind,
        'amount_minor': minor,
        'note': d.note.text.trim(),
        if (d.date != null) 'date': d.date,
      });
    }
    if (out.isEmpty) return showSnack(context, 'Nothing selected to save.');
    setState(() => _saving = true);
    try {
      await Api.instance.confirm(out, _heard, widget.source);
      if (!mounted) return;
      showSnack(context, out.length == 1 ? 'Saved 1 entry' : 'Saved ${out.length} entries');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: innerBar(_isPhoto ? 'Check the page' : 'Check before saving'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _propose)
          : _drafts == null
              ? Working(switch (widget.source) {
                  'voice' => 'Listening to your entry…',
                  'ledger_photo' => 'Reading the page… this can take 20–40 seconds',
                  _ => 'Understanding your entry…',
                })
              : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                  if (_isPhoto && widget.photo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(widget.photo!, height: 180, fit: BoxFit.cover),
                    )
                  else
                    Panel(
                      color: c.accentSoft,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Eyebrow('Heard'),
                        const SizedBox(height: 6),
                        Text('"$_heard"', style: display(context, 19, weight: FontWeight.w500)),
                      ]),
                    ),
                  if (_isPhoto) ...[
                    const SizedBox(height: 12),
                    Panel(
                      color: _unreadable > 0 ? c.doubtSoft : c.card,
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon(_unreadable > 0 ? Icons.help_outline_rounded : Icons.check_circle_outline_rounded,
                            color: _unreadable > 0 ? c.doubt : c.advance),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Read ${_drafts!.length} row${_drafts!.length == 1 ? '' : 's'}.'
                            '${_unreadable > 0 ? ' $_unreadable row${_unreadable == 1 ? '' : 's'} couldn\'t be read — add ${_unreadable == 1 ? 'it' : 'them'} by hand.' : ''}',
                            style: TextStyle(color: c.inkSoft),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_drafts!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _isPhoto
                            ? 'No rows could be read. Try a sharper photo in good light, flat and straight.'
                            : 'No ledger entry found in that. Try saying who, how much, and whether it was credit or a payment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: c.inkSoft),
                      ),
                    ),
                  for (final d in _drafts!) ...[_card(d), const SizedBox(height: 12)],
                ]),
      bottomNavigationBar: _drafts == null || _drafts!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context, false),
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _confirm,
                      child: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(_isPhoto ? 'Save selected' : 'Confirm all'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _card(_Draft d) {
    final c = context.c;
    InputDecoration deco(String label, String field) {
      final doubtful = d.doubt.contains(field);
      return InputDecoration(
        labelText: label,
        helperText: doubtful ? 'Please check' : null,
        helperStyle: TextStyle(color: c.doubt, fontWeight: FontWeight.w600),
        enabledBorder: doubtful
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.doubt, width: 1.8))
            : null,
        fillColor: doubtful ? c.doubtSoft : null,
      );
    }

    return AnimatedOpacity(
      opacity: d.keep ? 1 : 0.45,
      duration: const Duration(milliseconds: 180),
      child: Panel(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: d.kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: kindLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => d.kind = v ?? d.kind),
              ),
            ),
            Checkbox(value: d.keep, onChanged: (v) => setState(() => d.keep = v ?? true)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: d.name, decoration: deco('Customer', 'party_name')),
          if (d.doubt.contains('new_customer') || d.date != null || (d.confidence != null && d.confidence! < 0.6))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if (d.doubt.contains('new_customer')) TagChip('New customer', bg: c.accentSoft, fg: c.accent),
                if (d.date != null) TagChip('Dated ${d.date}', bg: c.paper, fg: c.inkSoft),
                if (d.confidence != null && d.confidence! < 0.6) TagChip('Low confidence', bg: c.doubtSoft, fg: c.doubt),
              ]),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: d.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: display(context, 26),
            decoration: deco('Amount ($_cur)', 'amount'),
          ),
          const SizedBox(height: 10),
          TextField(controller: d.note, decoration: deco('Note', 'note')),
        ]),
      ),
    );
  }
}
