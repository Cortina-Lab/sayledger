import 'package:flutter/material.dart';

import '../api.dart';
import '../money.dart';
import '../pdf_docs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Period report: totals, money in/out, per-customer movement.
/// Share or print as PDF, or export the whole book as CSV.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.presets()[2];
  Map<String, dynamic>? _r;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => (_error = null, _r = null));
    try {
      final r = await Api.instance.report(ymd(_period.start), ymd(_period.end));
      if (mounted) setState(() => _r = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String get _fileStem => 'sayledger-report-${ymd(_period.start)}-to-${ymd(_period.end)}';

  Future<void> _pdf({required bool print}) async {
    setState(() => _busy = true);
    try {
      final bytes = await reportPdf(_r!);
      if (print) {
        await printPdf(bytes, _fileStem);
      } else {
        await sharePdf(bytes, '$_fileStem.pdf');
      }
    } catch (e) {
      if (mounted) showSnack(context, "Couldn't make the PDF. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _csv() async {
    setState(() => _busy = true);
    try {
      final bytes = await Api.instance.exportCsv(start: ymd(_period.start), end: ymd(_period.end));
      if (mounted) await shareFile(context, bytes, '$_fileStem.csv', 'text/csv');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _r;
    return Scaffold(
      appBar: innerBar('Reports'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: PeriodBar(value: _period, onChanged: (p) {
            _period = p;
            _load();
          }),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : r == null
                  ? const Working('Adding it up…')
                  : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: _content(r)),
        ),
      ]),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _pdf(print: false),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Share PDF'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Print',
                    onPressed: _busy ? null : () => _pdf(print: true),
                    icon: Icon(Icons.print_outlined, color: c.ink),
                    style: IconButton.styleFrom(side: BorderSide(color: c.line), minimumSize: const Size(54, 54)),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Export CSV',
                    onPressed: _busy ? null : _csv,
                    icon: Icon(Icons.table_view_outlined, color: c.ink),
                    style: IconButton.styleFrom(side: BorderSide(color: c.line), minimumSize: const Size(54, 54)),
                  ),
                ]),
              ),
            ),
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final c = context.c;
    final cur = r['currency'] as String;
    String m(String k) => formatMoney(r[k] as int, cur);
    Widget cell(String label, String key, {Color? tone}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(label),
            const SizedBox(height: 3),
            Text(m(key), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tone ?? c.ink)),
          ]),
        );
    final parties = (r['parties'] as List).cast<Map<String, dynamic>>();
    return [
      Text('Net cash', style: TextStyle(color: c.inkSoft, fontSize: 15)),
      Text(m('net_cash_minor'), style: display(context, 42)),
      Text('Money in ${m('cash_in_minor')} · Money out ${m('cash_out_minor')} · ${r['entries']} entries',
          style: TextStyle(color: c.inkFaint)),
      const SizedBox(height: 16),
      Panel(
        child: Column(children: [
          Row(children: [cell('Credit given', 'credit_given_minor', tone: c.owes), cell('Payments', 'payment_received_minor', tone: c.advance)]),
          const SizedBox(height: 14),
          Row(children: [cell('Cash sales', 'cash_sale_minor'), cell('Expenses', 'expense_minor')]),
          const SizedBox(height: 14),
          Row(children: [cell('Owed to you now', 'outstanding_total_minor', tone: c.owes), cell('Advances held', 'advance_total_minor')]),
        ]),
      ),
      const SizedBox(height: 20),
      Text('Customers', style: display(context, 20)),
      const SizedBox(height: 8),
      if (parties.isEmpty) Text('No customer activity in this period.', style: TextStyle(color: c.inkSoft)),
      for (final p in parties)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('+${formatMoney(p['credit_given_minor'] as int, cur)} credit · −${formatMoney(p['payment_received_minor'] as int, cur)} paid',
                      style: TextStyle(color: c.inkFaint, fontSize: 13)),
                ]),
              ),
              Text(formatMoney((p['balance_minor'] as int).abs(), cur),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: (p['balance_minor'] as int) > 0 ? c.owes : (p['balance_minor'] as int) < 0 ? c.advance : c.inkFaint,
                  )),
            ]),
          ),
        ),
    ];
  }
}
