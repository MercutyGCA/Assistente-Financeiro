import 'package:assistente_financeiro/domain/financial_models.dart';
import 'package:assistente_financeiro/services/csv_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê o mesmo CSV exportado pelo aplicativo', () {
    const csv =
        '\uFEFF"Competência";"Data";"Tipo";"Descrição";"Categoria";"Local";"Pagamento";"Status";"Valor"\r\n'
        '"2026-07";"18/07/2026";"despesa";"Mercado; semana";"Casa";"Loja ""Centro""";"pix";"pago";"42,50"';

    final items = CsvImportService().parse(csv);

    expect(items, hasLength(1));
    expect(items.single.description, 'Mercado; semana');
    expect(items.single.place, 'Loja "Centro"');
    expect(items.single.amount, 42.5);
    expect(items.single.status, TransactionStatus.pago);
  });

  test('rejeita CSV de formato desconhecido', () {
    expect(
      () => CsvImportService().parse('nome;valor\nTeste;10'),
      throwsFormatException,
    );
  });
}
