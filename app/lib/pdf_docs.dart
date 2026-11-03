import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'money.dart';

// Customer statements and period reports as A4 PDFs. Every number comes from
// the backend's /statement and /report responses — nothing is recomputed here.

const _maroon = PdfColor.fromInt(0xFF7B1E2C);
const _ink = PdfColor.fromInt(0xFF1C1915);
const _faint = PdfColor.fromInt(0xFF8C8478);
const _line = PdfColor.fromInt(0xFFDDD5C7);
const _paper = PdfColor.fromInt(0xFFF7F3EA);

Future<pw.ThemeData> _theme() async {
  final base = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  // Fallbacks so Hindi / other scripts in names and notes still render.
  final deva = await PdfGoogleFonts.notoSansDevanagariRegular();
  return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [deva]);
}

Future<pw.Font> _serif() => PdfGoogleFonts.notoSansBold();

String _d(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}

pw.Widget _header(pw.Font serif, String shop, String title, String sub) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _maroon, width: 2))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(shop, style: pw.TextStyle(font: serif, fontSize: 20, color: _ink)),
            pw.SizedBox(height: 4),
            pw.Text(title.toUpperCase(), style: const pw.TextStyle(fontSize: 9, color: _maroon, letterSpacing: 1.5)),
          ]),
        ),
        pw.Text(sub, style: const pw.TextStyle(fontSize: 9, color: _faint)),
      ]),
    );

pw.Widget _footer(pw.Context ctx) => pw.Row(children: [
      pw.Text('Made with SayLedger by Cortina', style: const pw.TextStyle(fontSize: 8, color: _faint)),
      pw.Spacer(),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _faint)),
    ]);

pw.Widget _stat(String label, String value, {PdfColor color = _ink}) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(right: 8),
        decoration: pw.BoxDecoration(color: _paper, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7.5, color: _faint, letterSpacing: 1)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
        ]),
      ),
    );

String _balanceWord(int b) => b > 0 ? 'owes' : b < 0 ? 'advance' : 'settled';

Future<Uint8List> statementPdf(Map<String, dynamic> st) async {
  final theme = await _theme();
  final serif = await _serif();
  final cur = st['currency'] as String;
  final party = st['party'] as Map<String, dynamic>;
  final shop = (st['shop'] as Map?)?['name'] as String? ?? 'Shop';
  final lines = (st['lines'] as List).cast<Map<String, dynamic>>();
  final opening = st['opening_balance_minor'] as int;
  final closing = st['closing_balance_minor'] as int;
  final period = st['from'] == null && st['to'] == null
      ? 'All entries'
      : '${st['from'] == null ? 'Start' : _d(st['from'] as String)} – ${st['to'] == null ? 'Today' : _d(st['to'] as String)}';

  final doc = pw.Document(title: 'Statement – ${party['name']}', author: shop, creator: 'SayLedger by Cortina', theme: theme);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 30),
    footer: _footer,
    build: (ctx) => [
      _header(serif, shop, 'Account statement', 'Generated ${_d(st['generated_at'] as String?)}'),
      pw.SizedBox(height: 16),
      pw.Text(party['name'] as String, style: pw.TextStyle(font: serif, fontSize: 16)),
      if ((party['phone'] ?? '').toString().isNotEmpty)
        pw.Text(party['phone'] as String, style: const pw.TextStyle(fontSize: 9, color: _faint)),
      pw.Text(period, style: const pw.TextStyle(fontSize: 9, color: _faint)),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        _stat('Opening balance', formatMoney(opening, cur)),
        _stat('Credit given', formatMoney(st['credit_given_minor'] as int, cur)),
        _stat('Payments received', formatMoney(st['payment_received_minor'] as int, cur)),
        _stat('Closing balance', '${formatMoney(closing.abs(), cur)} ${_balanceWord(closing)}', color: _maroon),
      ]),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Details', 'Credit', 'Paid', 'Balance'],
        data: [
          for (final l in lines)
            [
              _d(l['created_at'] as String),
              [kindLabels[l['kind']] ?? l['kind'], if ((l['note'] as String).isNotEmpty) l['note']].join(' · '),
              l['kind'] == 'credit_given' ? formatMoney(l['amount_minor'] as int, cur) : '',
              l['kind'] == 'payment_received' ? formatMoney(l['amount_minor'] as int, cur) : '',
              formatMoney(l['balance_after_minor'] as int, cur),
            ],
        ],
        headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _maroon),
        cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FixedColumnWidth(70), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(72), 3: const pw.FixedColumnWidth(72), 4: const pw.FixedColumnWidth(80)},
      ),
      if (lines.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(16), child: pw.Text('No entries in this period.', style: const pw.TextStyle(color: _faint))),
      pw.SizedBox(height: 18),
      pw.Text(
        'Balance = credit given − payments received. Cancelled entries are not included. '
        'This is an account statement, not a tax invoice.',
        style: const pw.TextStyle(fontSize: 8, color: _faint),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> reportPdf(Map<String, dynamic> r) async {
  final theme = await _theme();
  final serif = await _serif();
  final cur = r['currency'] as String;
  final shop = (r['shop'] as Map?)?['name'] as String? ?? 'Shop';
  final parties = (r['parties'] as List).cast<Map<String, dynamic>>();
  String m(String k) => formatMoney(r[k] as int, cur);

  final doc = pw.Document(title: 'Report ${r['from']} to ${r['to']}', author: shop, creator: 'SayLedger by Cortina', theme: theme);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 30),
    footer: _footer,
    build: (ctx) => [
      _header(serif, shop, 'Book report', '${_d(r['from'] as String)} – ${_d(r['to'] as String)}'),
      pw.SizedBox(height: 16),
      pw.Row(children: [
        _stat('Credit given', m('credit_given_minor')),
        _stat('Payments received', m('payment_received_minor')),
        _stat('Cash sales', m('cash_sale_minor')),
        _stat('Expenses', m('expense_minor')),
      ]),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        _stat('Money in', m('cash_in_minor')),
        _stat('Money out', m('cash_out_minor')),
        _stat('Net cash', m('net_cash_minor'), color: _maroon),
        _stat('Entries', '${r['entries']}'),
      ]),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        _stat('Customers owe you (today)', m('outstanding_total_minor'), color: _maroon),
        _stat('Advances held (today)', m('advance_total_minor')),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('Customers', style: pw.TextStyle(font: serif, fontSize: 13)),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: ['Customer', 'Credit in period', 'Paid in period', 'Balance today'],
        data: [
          for (final p in parties)
            [
              p['name'],
              formatMoney(p['credit_given_minor'] as int, cur),
              formatMoney(p['payment_received_minor'] as int, cur),
              '${formatMoney((p['balance_minor'] as int).abs(), cur)} ${_balanceWord(p['balance_minor'] as int)}',
            ],
        ],
        headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _maroon),
        cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
      ),
      if (parties.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(16), child: pw.Text('No customer activity.', style: const pw.TextStyle(color: _faint))),
      pw.SizedBox(height: 18),
      pw.Text(
        'Money in = cash sales + payments received. Money out = expenses. Cancelled entries are not included. '
        'SayLedger is a credit book, not accounting or tax software.',
        style: const pw.TextStyle(fontSize: 8, color: _faint),
      ),
    ],
  ));
  return doc.save();
}

Future<void> sharePdf(Uint8List bytes, String filename) => Printing.sharePdf(bytes: bytes, filename: filename);
Future<void> printPdf(Uint8List bytes, String name) => Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
