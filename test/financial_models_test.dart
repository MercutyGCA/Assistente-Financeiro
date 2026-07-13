import 'package:assistente_financeiro/domain/financial_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinancialSummary', () {
    test('calcula saldos e comprometimento', () {
      const summary = FinancialSummary(income: 5000, paid: 950, pending: 500);

      expect(summary.currentBalance, 4050);
      expect(summary.projectedBalance, 3550);
      expect(summary.commitment, closeTo(.29, .001));
      expect(summary.score, 100);
      expect(summary.classification, 'Excelente');
    });

    test('penaliza atrasos e alto comprometimento', () {
      const summary = FinancialSummary(
        income: 1000,
        paid: 500,
        pending: 300,
        overdue: 200,
      );

      expect(summary.projectedBalance, 0);
      expect(summary.score, 30);
      expect(summary.classification, 'Crítica');
    });

    test('limita o score entre zero e cem', () {
      const healthy = FinancialSummary(income: 1000);
      const critical = FinancialSummary(income: 100, overdue: 1000);

      expect(healthy.score, 100);
      expect(critical.score, 30);
    });

    test('considera alertas e estouros de metas no score', () {
      const summary = FinancialSummary(income: 1000);
      const goals = [
        SpendingGoal(
          id: '1',
          category: 'Casa',
          limit: 100,
          alertPercentage: 80,
          spent: 85,
        ),
        SpendingGoal(
          id: '2',
          category: 'Lazer',
          limit: 100,
          alertPercentage: 80,
          spent: 120,
        ),
      ];

      expect(summary.scoreWithGoals(goals), 80);
      expect(scoreClassification(80), 'Boa');
    });
  });

  test('formata competência com zero à esquerda', () {
    expect(competenceOf(DateTime(2026, 7, 13)), '2026-07');
  });

  test('filtra os atalhos do dashboard por tipo e status', () {
    final transactions = [
      _transaction('receita', TransactionType.receita, TransactionStatus.pago),
      _transaction('paga', TransactionType.despesa, TransactionStatus.pago),
      _transaction(
        'pendente',
        TransactionType.despesa,
        TransactionStatus.pendente,
      ),
      _transaction(
        'atrasada',
        TransactionType.despesa,
        TransactionStatus.atrasado,
      ),
    ];

    for (final filter in DashboardTransactionFilter.values) {
      expect(filterDashboardTransactions(transactions, filter), hasLength(1));
    }
    expect(
      filterDashboardTransactions(
        transactions,
        DashboardTransactionFilter.pendentes,
      ).single.id,
      'pendente',
    );
  });
}

FinancialTransaction _transaction(
  String id,
  TransactionType type,
  TransactionStatus status,
) {
  return FinancialTransaction(
    id: id,
    type: type,
    paymentMethod: PaymentMethod.pix,
    category: 'Teste',
    description: id,
    place: '',
    totalAmount: 10,
    installmentAmount: 10,
    installmentNumber: 1,
    installmentCount: 1,
    status: status,
    purchaseDate: DateTime(2026, 7, 1),
    dueDate: DateTime(2026, 7, 1),
    competence: '2026-07',
    createdAt: DateTime(2026, 7, 1),
  );
}
