import 'package:assistente_financeiro/data/app_database.dart';
import 'package:assistente_financeiro/data/finance_repository.dart';
import 'package:assistente_financeiro/domain/financial_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late FinanceRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createSchema(database);
    repository = FinanceRepository(database: AppDatabase.forTesting(database));
    await repository.saveSettings(const AppSettings(creditToNextMonth: false));
  });

  tearDown(() => database.close());

  test('salva parcelamento distribuindo os centavos corretamente', () async {
    await repository.addTransaction(_draft(amount: 100, installments: 3));

    final july = await repository.listTransactions('2026-07');
    final august = await repository.listTransactions('2026-08');
    final september = await repository.listTransactions('2026-09');

    expect(july.single.installmentAmount, 33.34);
    expect(august.single.installmentAmount, 33.33);
    expect(september.single.installmentAmount, 33.33);
    expect(
      july.single.installmentAmount +
          august.single.installmentAmount +
          september.single.installmentAmount,
      100,
    );
  });

  test('fecha, protege e reabre uma competência', () async {
    await repository.addTransaction(_draft());
    await repository.closeMonth('2026-07');

    final closure = await repository.getClosure('2026-07');
    expect(closure, isNotNull);
    expect(closure!.summary.pending, 50);
    await expectLater(
      repository.updateStatus(
        (await repository.listTransactions('2026-07')).single.id,
        TransactionStatus.pago,
      ),
      throwsStateError,
    );

    await repository.reopenMonth('2026-07');
    final item = (await repository.listTransactions('2026-07')).single;
    await repository.updateStatus(item.id, TransactionStatus.pago);
    expect((await repository.summary('2026-07')).paid, 50);
  });

  test('exclui todas as parcelas de um mesmo grupo', () async {
    await repository.addTransaction(_draft(installments: 3));
    final first = (await repository.listTransactions('2026-07')).single;

    await repository.deleteTransaction(first.id, entireGroup: true);

    expect(await repository.listTransactions('2026-07'), isEmpty);
    expect(await repository.listTransactions('2026-08'), isEmpty);
    expect(await repository.listTransactions('2026-09'), isEmpty);
  });

  test(
    'lança compra no crédito no mês seguinte e no vencimento configurado',
    () async {
      await repository.saveSettings(
        const AppSettings(creditDueDay: 12, creditToNextMonth: true),
      );

      await repository.addTransaction(_draft());

      expect(await repository.listTransactions('2026-07'), isEmpty);
      final august = (await repository.listTransactions('2026-08')).single;
      expect(august.dueDate, DateTime(2026, 8, 12));
      expect(august.status, TransactionStatus.pendente);
      expect(await repository.creditStatementTotal('2026-08'), 50);
      await repository.payCreditStatement('2026-08');
      expect((await repository.summary('2026-08')).paid, 50);
    },
  );

  test('gera conta fixa uma única vez por competência', () async {
    await repository.addTransaction(
      _draft(paymentMethod: PaymentMethod.pix, recurring: true),
    );

    await repository.generateRecurringForMonth(DateTime(2026, 8));
    await repository.generateRecurringForMonth(DateTime(2026, 8));

    final august = await repository.listTransactions('2026-08');
    expect(august, hasLength(1));
    expect(august.single.recurring, isTrue);
    expect(august.single.status, TransactionStatus.pendente);
    expect(await repository.listRecurringRules(), hasLength(1));
  });

  test(
    'recupera competências recorrentes não geradas enquanto o app estava fechado',
    () async {
      await repository.addTransaction(
        _draft(paymentMethod: PaymentMethod.pix, recurring: true),
      );

      await repository.generateRecurringThrough(DateTime(2026, 10));

      expect(await repository.listTransactions('2026-08'), hasLength(1));
      expect(await repository.listTransactions('2026-09'), hasLength(1));
      expect(await repository.listTransactions('2026-10'), hasLength(1));
    },
  );

  test('encerra a conta fixa no último mês configurado', () async {
    await repository.addTransaction(
      _draft(
        paymentMethod: PaymentMethod.pix,
        recurring: true,
        recurringUntil: DateTime(2026, 8),
      ),
    );

    await repository.generateRecurringThrough(DateTime(2026, 10));

    expect(await repository.listTransactions('2026-07'), hasLength(1));
    expect(await repository.listTransactions('2026-08'), hasLength(1));
    expect(await repository.listTransactions('2026-09'), isEmpty);
    expect(await repository.listTransactions('2026-10'), isEmpty);
    final rule = (await repository.listRecurringRules()).single;
    expect(rule.endCompetence, '2026-08');

    await repository.updateRecurringRuleEnd(rule.id, null);
    await repository.generateRecurringForMonth(DateTime(2026, 9));
    expect(await repository.listTransactions('2026-09'), hasLength(1));

    await repository.updateRecurringRuleEnd(rule.id, DateTime(2026, 8));
    expect(await repository.listTransactions('2026-09'), isEmpty);
  });

  test('emite cada nível de alerta de limite somente uma vez', () async {
    await repository.saveGoal(
      category: 'Casa',
      limit: 100,
      alertPercentage: 80,
    );
    await repository.addTransaction(
      _draft(amount: 85, paymentMethod: PaymentMethod.pix),
    );

    final warning = await repository.claimNewGoalAlerts('2026-07');
    expect(warning.single.level, 'warning');
    expect(await repository.claimNewGoalAlerts('2026-07'), isEmpty);

    await repository.addTransaction(
      _draft(amount: 20, paymentMethod: PaymentMethod.pix),
    );
    final limit = await repository.claimNewGoalAlerts('2026-07');
    expect(limit.single.level, 'limit');
    expect(await repository.claimNewGoalAlerts('2026-07'), isEmpty);
  });

  test('consolida relatório por período, mês e categoria', () async {
    await repository.addTransaction(
      _draft(
        type: TransactionType.receita,
        paymentMethod: PaymentMethod.pix,
        amount: 1000,
        category: 'Salário',
      ),
    );
    await repository.addTransaction(
      _draft(paymentMethod: PaymentMethod.pix, amount: 200, category: 'Casa'),
    );
    await repository.addTransaction(
      _draft(
        paymentMethod: PaymentMethod.pix,
        amount: 100,
        category: 'Lazer',
        dueDate: DateTime(2026, 8, 20),
      ),
    );

    final report = await repository.buildReport('2026-07', '2026-08');

    expect(report.transactions, hasLength(3));
    expect(report.income, 1000);
    expect(report.expenses, 300);
    expect(report.balance, 700);
    expect(report.months, hasLength(2));
    expect(report.categories.first.category, 'Casa');
    expect(report.categories.first.amount, 200);
  });

  test('usa somente a parte pessoal de uma despesa dividida', () async {
    await repository.addTransaction(
      _draft(amount: 120, paymentMethod: PaymentMethod.pix, sharedPeople: 3),
    );

    final transaction = (await repository.listTransactions('2026-07')).single;
    expect(transaction.totalAmount, 120);
    expect(transaction.sharedPeople, 3);
    expect(transaction.personalShareTotal, 40);
    expect(transaction.installmentAmount, 40);
    expect((await repository.summary('2026-07')).paid, 40);
    expect((await repository.buildReport('2026-07', '2026-07')).expenses, 40);
  });

  test('divide a parte pessoal corretamente entre parcelas', () async {
    await repository.addTransaction(
      _draft(amount: 100, installments: 3, sharedPeople: 3),
    );

    final july = (await repository.listTransactions('2026-07')).single;
    final august = (await repository.listTransactions('2026-08')).single;
    final september = (await repository.listTransactions('2026-09')).single;
    expect(july.installmentAmount, 11.11);
    expect(august.installmentAmount, 11.11);
    expect(september.installmentAmount, 11.11);
  });

  test('mantém conta com lembrete pendente até o vencimento', () async {
    await repository.addTransaction(
      _draft(
        paymentMethod: PaymentMethod.pix,
        remindOnDueDate: true,
        dueDate: DateTime(2026, 7, 20),
      ),
    );

    final reminders = await repository.listPendingPaymentReminders(
      from: DateTime(2026, 7, 13),
      until: DateTime(2026, 7, 31),
    );
    expect(reminders, hasLength(1));
    expect(reminders.single.status, TransactionStatus.pendente);

    await repository.updateStatus(reminders.single.id, TransactionStatus.pago);
    expect(
      await repository.listPendingPaymentReminders(
        from: DateTime(2026, 7, 13),
        until: DateTime(2026, 7, 31),
      ),
      isEmpty,
    );
  });

  test('edita por completo uma despesa dividida', () async {
    await repository.addTransaction(
      _draft(amount: 120, paymentMethod: PaymentMethod.pix, sharedPeople: 3),
    );
    final original = (await repository.listTransactions('2026-07')).single;

    await repository.updateTransaction(
      original.id,
      TransactionUpdate(
        type: TransactionType.despesa,
        paymentMethod: PaymentMethod.debito,
        category: 'Mercado',
        description: 'Compra alterada',
        place: 'Supermercado',
        amount: 150,
        purchaseDate: DateTime(2026, 7, 14),
        dueDate: DateTime(2026, 7, 25),
        status: TransactionStatus.pendente,
        sharedPeople: 5,
      ),
    );

    final updated = (await repository.listTransactions('2026-07')).single;
    expect(updated.totalAmount, 150);
    expect(updated.installmentAmount, 30);
    expect(updated.sharedPeople, 5);
    expect(updated.paymentMethod, PaymentMethod.debito);
    expect(updated.description, 'Compra alterada');
    expect(updated.status, TransactionStatus.pendente);
  });

  test('propaga edição e exclusão de conta recorrente', () async {
    await repository.addTransaction(
      _draft(paymentMethod: PaymentMethod.pix, recurring: true),
    );
    await repository.generateRecurringForMonth(DateTime(2026, 8));
    final rule = (await repository.listRecurringRules()).single;

    await repository.updateRecurringRule(
      rule.id,
      const RecurringRuleUpdate(
        type: TransactionType.despesa,
        paymentMethod: PaymentMethod.debito,
        category: 'Moradia',
        description: 'Aluguel atualizado',
        place: 'Casa',
        amount: 900,
        sharedPeople: 3,
        dueDay: 15,
        endCompetence: null,
      ),
    );

    final july = (await repository.listTransactions('2026-07')).single;
    final august = (await repository.listTransactions('2026-08')).single;
    for (final item in [july, august]) {
      expect(item.totalAmount, 900);
      expect(item.installmentAmount, 300);
      expect(item.description, 'Aluguel atualizado');
      expect(item.dueDate.day, 15);
    }

    await repository.deleteRecurringRule(rule.id);
    expect(await repository.listRecurringRules(), isEmpty);
    expect(await repository.listTransactions('2026-07'), isEmpty);
    expect(await repository.listTransactions('2026-08'), isEmpty);
  });

  test('importa lançamentos e ignora duplicados', () async {
    final item = ImportedTransaction(
      competence: '2026-07',
      dueDate: DateTime(2026, 7, 18),
      type: TransactionType.despesa,
      description: 'Importada',
      category: 'Casa',
      place: 'Loja',
      paymentMethod: PaymentMethod.pix,
      status: TransactionStatus.pago,
      amount: 42.5,
    );
    final first = await repository.importTransactions([item]);
    final second = await repository.importTransactions([item]);

    expect(first.imported, 1);
    expect(second.skipped, 1);
    expect(await repository.listTransactions('2026-07'), hasLength(1));
  });
}

TransactionDraft _draft({
  TransactionType type = TransactionType.despesa,
  double amount = 50,
  int installments = 1,
  PaymentMethod paymentMethod = PaymentMethod.credito,
  bool recurring = false,
  DateTime? recurringUntil,
  DateTime? dueDate,
  String category = 'Casa',
  int sharedPeople = 1,
  bool remindOnDueDate = false,
}) {
  return TransactionDraft(
    type: type,
    paymentMethod: paymentMethod,
    category: category,
    description: 'Compra de teste',
    place: 'Loja',
    amount: amount,
    purchaseDate: DateTime(2026, 7, 13),
    dueDate: dueDate ?? DateTime(2026, 7, 20),
    installments: installments,
    recurring: recurring,
    recurringUntil: recurringUntil,
    sharedPeople: sharedPeople,
    remindOnDueDate: remindOnDueDate,
  );
}
