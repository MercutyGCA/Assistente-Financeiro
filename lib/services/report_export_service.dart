import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/financial_models.dart';

class ReportExportService {
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM/yyyy');

  Future<void> sharePdf(FinancialReport report) async {
    final document = pw.Document(
      title:
          'Relatório financeiro ${report.startCompetence} a ${report.endCompetence}',
      author: 'Meu Financeiro',
    );
    const purple = PdfColor.fromInt(0xFF7C3AED);
    const lightPurple = PdfColor.fromInt(0xFFF3E8FF);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: purple, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'MEU FINANCEIRO',
                style: pw.TextStyle(
                  color: purple,
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Página ${context.pageNumber}'),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gerado em ${_date.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 18),
          pw.Text(
            'Relatório financeiro',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Período: ${_period(report.startCompetence)} a ${_period(report.endCompetence)}',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: lightPurple,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _summary('Receitas', report.income),
                _summary('Despesas', report.expenses),
                _summary('Saldo', report.balance),
                _summary('Em atraso', report.overdue),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _title('Evolução mensal', purple),
          _table(
            const ['Mês', 'Receitas', 'Despesas', 'Saldo'],
            report.months
                .map(
                  (month) => [
                    _period(month.competence),
                    _currency.format(month.income),
                    _currency.format(month.expenses),
                    _currency.format(month.balance),
                  ],
                )
                .toList(),
            purple,
          ),
          pw.SizedBox(height: 20),
          _title('Despesas por categoria', purple),
          _table(
            const ['Categoria', 'Total', '% das despesas'],
            report.categories
                .map(
                  (category) => [
                    category.category,
                    _currency.format(category.amount),
                    report.expenses == 0
                        ? '0%'
                        : '${(category.amount / report.expenses * 100).toStringAsFixed(1)}%',
                  ],
                )
                .toList(),
            purple,
          ),
          pw.SizedBox(height: 20),
          _title('Lançamentos', purple),
          _table(
            const ['Data', 'Descrição', 'Categoria', 'Status', 'Valor'],
            report.transactions
                .map(
                  (item) => [
                    _date.format(item.dueDate),
                    item.description,
                    item.category,
                    item.status.name,
                    '${item.type == TransactionType.despesa ? '-' : '+'}${_currency.format(item.installmentAmount)}',
                  ],
                )
                .toList(),
            purple,
          ),
        ],
      ),
    );

    final bytes = await document.save();
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Relatório financeiro',
        text:
            'Relatório de ${_period(report.startCompetence)} a ${_period(report.endCompetence)}',
        files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
        fileNameOverrides: [_fileName(report, 'pdf')],
      ),
    );
  }

  Future<void> shareCsv(FinancialReport report) async {
    final rows = <List<String>>[
      [
        'Competência',
        'Data',
        'Tipo',
        'Descrição',
        'Categoria',
        'Local',
        'Pagamento',
        'Status',
        'Valor',
      ],
      ...report.transactions.map(
        (item) => [
          item.competence,
          _date.format(item.dueDate),
          item.type.name,
          item.description,
          item.category,
          item.place,
          item.paymentMethod.name,
          item.status.name,
          item.installmentAmount.toStringAsFixed(2).replaceAll('.', ','),
        ],
      ),
    ];
    final csv = rows.map((row) => row.map(_csvCell).join(';')).join('\r\n');
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Relatório financeiro em CSV',
        files: [XFile.fromData(bytes, mimeType: 'text/csv')],
        fileNameOverrides: [_fileName(report, 'csv')],
      ),
    );
  }

  pw.Widget _summary(String label, double value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      pw.Text(
        _currency.format(value),
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );

  pw.Widget _title(String text, PdfColor color) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: color,
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  pw.Widget _table(
    List<String> headers,
    List<List<String>> rows,
    PdfColor color,
  ) {
    final allRows = [headers, ...rows];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
      children: List.generate(
        allRows.length,
        (index) => pw.TableRow(
          decoration: index == 0 ? pw.BoxDecoration(color: color) : null,
          children: allRows[index]
              .map(
                (cell) => pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    cell,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: index == 0 ? PdfColors.white : PdfColors.black,
                      fontWeight: index == 0 ? pw.FontWeight.bold : null,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _period(String competence) {
    final parts = competence.split('-');
    return '${parts[1]}/${parts[0]}';
  }

  String _fileName(FinancialReport report, String extension) =>
      'relatorio_${report.startCompetence}_${report.endCompetence}.$extension';

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';
}
