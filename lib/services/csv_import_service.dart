import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../domain/financial_models.dart';

class CsvImportService {
  Future<List<ImportedTransaction>?> pickTransactions() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      throw StateError('Não foi possível ler o arquivo selecionado.');
    }
    return parse(utf8.decode(bytes, allowMalformed: false));
  }

  List<ImportedTransaction> parse(String content) {
    final clean = content.startsWith('\uFEFF') ? content.substring(1) : content;
    final rows = _parseRows(clean);
    if (rows.isEmpty) throw const FormatException('O CSV está vazio.');
    const expected = [
      'Competência',
      'Data',
      'Tipo',
      'Descrição',
      'Categoria',
      'Local',
      'Pagamento',
      'Status',
      'Valor',
    ];
    if (rows.first.length != expected.length ||
        List.generate(
          expected.length,
          (index) => rows.first[index].trim() == expected[index],
        ).contains(false)) {
      throw const FormatException(
        'Formato incompatível. Selecione um CSV exportado pelo aplicativo.',
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy');
    final items = <ImportedTransaction>[];
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      if (row.length != expected.length) {
        throw FormatException('Linha ${index + 1} possui colunas inválidas.');
      }
      try {
        final date = dateFormat.parseStrict(row[1].trim());
        final amount = double.parse(
          row[8].trim().replaceAll('.', '').replaceAll(',', '.'),
        );
        if (amount <= 0 || !RegExp(r'^\d{4}-\d{2}$').hasMatch(row[0].trim())) {
          throw const FormatException();
        }
        items.add(
          ImportedTransaction(
            competence: row[0].trim(),
            dueDate: date,
            type: TransactionType.values.byName(row[2].trim()),
            description: row[3].trim(),
            category: row[4].trim(),
            place: row[5].trim(),
            paymentMethod: PaymentMethod.values.byName(row[6].trim()),
            status: TransactionStatus.values.byName(row[7].trim()),
            amount: amount,
          ),
        );
      } catch (_) {
        throw FormatException('Dados inválidos na linha ${index + 1}.');
      }
    }
    return items;
  }

  List<List<String>> _parseRows(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (char == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ';' && !quoted) {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index++;
        }
        row.add(cell.toString());
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
      } else {
        cell.write(char);
      }
    }
    if (quoted) throw const FormatException('CSV com aspas não finalizadas.');
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }
}
