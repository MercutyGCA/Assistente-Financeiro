import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../domain/financial_models.dart';
import 'app_database.dart';

class FinanceRepository {
  FinanceRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> addTransaction(TransactionDraft draft) async {
    if (draft.amount <= 0) {
      throw ArgumentError('O valor deve ser maior que zero.');
    }
    if (draft.category.trim().isEmpty || draft.description.trim().isEmpty) {
      throw ArgumentError('Categoria e descrição são obrigatórias.');
    }
    if (draft.installments < 1 || draft.installments > 120) {
      throw ArgumentError('A quantidade de parcelas deve estar entre 1 e 120.');
    }
    if (draft.recurring && draft.installments > 1) {
      throw ArgumentError('Uma conta fixa não pode ser parcelada.');
    }
    if (draft.sharedPeople < 1 || draft.sharedPeople > 100) {
      throw ArgumentError('A divisão deve ter entre 1 e 100 pessoas.');
    }
    if (draft.type == TransactionType.receita && draft.sharedPeople > 1) {
      throw ArgumentError('Somente despesas podem ser divididas.');
    }

    final db = await _database.database;
    final settings = await getSettings();
    final now = DateTime.now();
    final count = draft.installments;
    final group = count > 1 ? _id() : null;
    final firstDue =
        draft.paymentMethod == PaymentMethod.credito &&
            settings.creditToNextMonth
        ? _dateWithDay(
            DateTime(draft.purchaseDate.year, draft.purchaseDate.month + 1),
            settings.creditDueDay,
          )
        : draft.dueDate;
    final recurringRuleId = draft.recurring ? _id() : null;
    final recurringEnd = draft.recurringUntil == null
        ? null
        : competenceOf(draft.recurringUntil!);
    if (recurringEnd != null &&
        recurringEnd.compareTo(competenceOf(firstDue)) < 0) {
      throw ArgumentError(
        'A conta fixa não pode terminar antes da primeira cobrança.',
      );
    }
    final totalCents = (draft.amount * 100).round();
    final personalCents = (totalCents / draft.sharedPeople).round();
    final baseCents = personalCents ~/ count;
    final remainder = personalCents % count;

    for (var index = 0; index < count; index++) {
      await _ensureCompetenceOpen(
        db,
        competenceOf(_addMonths(firstDue, index)),
      );
    }

    await db.transaction((txn) async {
      if (recurringRuleId != null) {
        await txn.insert('recurring_rules', {
          'id': recurringRuleId,
          'type': draft.type.name,
          'payment_method': draft.paymentMethod.name,
          'category': draft.category.trim(),
          'description': draft.description.trim(),
          'place': draft.place.trim(),
          'amount': draft.amount,
          'shared_people': draft.sharedPeople,
          'due_day': firstDue.day,
          'start_competence': competenceOf(firstDue),
          'end_competence': recurringEnd,
          'active': 1,
          'created_at': now.toIso8601String(),
        });
      }
      for (var index = 0; index < count; index++) {
        final dueDate = _addMonths(firstDue, index);
        final cents = baseCents + (index < remainder ? 1 : 0);
        final awaitsPayment =
            draft.type == TransactionType.despesa &&
            (draft.recurring ||
                draft.paymentMethod == PaymentMethod.credito ||
                draft.remindOnDueDate);
        final today = DateTime(now.year, now.month, now.day);
        final status = draft.type == TransactionType.receita || !awaitsPayment
            ? TransactionStatus.pago
            : dueDate.isBefore(today)
            ? TransactionStatus.atrasado
            : TransactionStatus.pendente;
        final transaction = FinancialTransaction(
          id: _id(),
          installmentGroup: group,
          recurringRuleId: recurringRuleId,
          type: draft.type,
          paymentMethod: draft.paymentMethod,
          category: draft.category.trim(),
          description: draft.description.trim(),
          place: draft.place.trim(),
          totalAmount: draft.amount,
          installmentAmount: cents / 100,
          installmentNumber: index + 1,
          installmentCount: count,
          sharedPeople: draft.sharedPeople,
          recurring: draft.recurring,
          status: status,
          purchaseDate: draft.purchaseDate,
          dueDate: dueDate,
          competence: competenceOf(dueDate),
          createdAt: now,
        );
        await txn.insert('transactions', transaction.toMap());
      }
    });
  }

  Future<List<FinancialTransaction>> listTransactions(String competence) async {
    final db = await _database.database;
    final rows = await db.query(
      'transactions',
      where: 'competence = ?',
      whereArgs: [competence],
      orderBy: 'due_date DESC, created_at DESC',
    );
    return rows.map(FinancialTransaction.fromMap).toList();
  }

  Future<List<FinancialTransaction>> listPendingPaymentReminders({
    DateTime? from,
    DateTime? until,
    int limit = 200,
  }) async {
    final db = await _database.database;
    final start = from ?? DateTime.now();
    final end = until ?? DateTime(start.year, start.month + 13, 0);
    final rows = await db.query(
      'transactions',
      where:
          "type = 'despesa' AND status = 'pendente' "
          'AND due_date >= ? AND due_date <= ?',
      whereArgs: [_date(start), _date(end)],
      orderBy: 'due_date, created_at',
      limit: limit,
    );
    return rows.map(FinancialTransaction.fromMap).toList();
  }

  Future<FinancialReport> buildReport(
    String startCompetence,
    String endCompetence,
  ) async {
    if (startCompetence.compareTo(endCompetence) > 0) {
      throw ArgumentError('O início do relatório deve ser anterior ao fim.');
    }
    final db = await _database.database;
    final rows = await db.query(
      'transactions',
      where: 'competence >= ? AND competence <= ?',
      whereArgs: [startCompetence, endCompetence],
      orderBy: 'competence, due_date, created_at',
    );
    final transactions = rows.map(FinancialTransaction.fromMap).toList();
    var income = 0.0;
    var paid = 0.0;
    var pending = 0.0;
    var overdue = 0.0;
    final categoryTotals = <String, double>{};
    final monthIncome = <String, double>{};
    final monthExpenses = <String, double>{};

    for (final item in transactions) {
      if (item.type == TransactionType.receita) {
        income += item.installmentAmount;
        monthIncome.update(
          item.competence,
          (value) => value + item.installmentAmount,
          ifAbsent: () => item.installmentAmount,
        );
        continue;
      }
      categoryTotals.update(
        item.category,
        (value) => value + item.installmentAmount,
        ifAbsent: () => item.installmentAmount,
      );
      monthExpenses.update(
        item.competence,
        (value) => value + item.installmentAmount,
        ifAbsent: () => item.installmentAmount,
      );
      switch (item.status) {
        case TransactionStatus.pago:
          paid += item.installmentAmount;
        case TransactionStatus.pendente:
          pending += item.installmentAmount;
        case TransactionStatus.atrasado:
          overdue += item.installmentAmount;
      }
    }

    final categories =
        categoryTotals.entries
            .map(
              (entry) =>
                  ReportCategory(category: entry.key, amount: entry.value),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    final competences = {...monthIncome.keys, ...monthExpenses.keys}.toList()
      ..sort();
    final months = competences
        .map(
          (competence) => ReportMonth(
            competence: competence,
            income: monthIncome[competence] ?? 0,
            expenses: monthExpenses[competence] ?? 0,
          ),
        )
        .toList();

    return FinancialReport(
      startCompetence: startCompetence,
      endCompetence: endCompetence,
      transactions: transactions,
      income: income,
      paid: paid,
      pending: pending,
      overdue: overdue,
      categories: categories,
      months: months,
    );
  }

  Future<void> updateStatus(String id, TransactionStatus status) async {
    final db = await _database.database;
    await _ensureTransactionOpen(db, id);
    await db.update(
      'transactions',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTransaction(String id, TransactionUpdate update) async {
    if (update.amount <= 0) {
      throw ArgumentError('O valor deve ser maior que zero.');
    }
    if (update.category.trim().isEmpty || update.description.trim().isEmpty) {
      throw ArgumentError('Categoria e descrição são obrigatórias.');
    }
    if (update.sharedPeople < 1 || update.sharedPeople > 100) {
      throw ArgumentError('A divisão deve ter entre 1 e 100 pessoas.');
    }
    if (update.type == TransactionType.receita && update.sharedPeople > 1) {
      throw ArgumentError('Somente despesas podem ser divididas.');
    }
    final db = await _database.database;
    await _ensureTransactionOpen(db, id);
    final current = await db.query(
      'transactions',
      columns: ['installment_count', 'shared_people'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (current.isEmpty) throw StateError('Lançamento não encontrado.');
    final competence = competenceOf(update.dueDate);
    await _ensureCompetenceOpen(db, competence);
    final single = current.single['installment_count'] == 1;
    final currentSharedPeople = (current.single['shared_people'] as int?) ?? 1;
    final sharedPeople = single ? update.sharedPeople : currentSharedPeople;
    final personalAmount = single
        ? ((update.amount * 100).round() / sharedPeople).round() / 100
        : update.amount;
    await db.update(
      'transactions',
      {
        'type': update.type.name,
        'payment_method': update.paymentMethod.name,
        'category': update.category.trim(),
        'description': update.description.trim(),
        'place': update.place.trim(),
        if (single) 'total_amount': update.amount,
        'installment_amount': personalAmount,
        'shared_people': sharedPeople,
        'status': update.type == TransactionType.receita
            ? TransactionStatus.pago.name
            : update.status.name,
        'purchase_date': _date(update.purchaseDate),
        'due_date': _date(update.dueDate),
        'competence': competence,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTransaction(String id, {bool entireGroup = false}) async {
    final db = await _database.database;
    await _ensureTransactionOpen(db, id);
    if (!entireGroup) {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
      return;
    }
    final rows = await db.query(
      'transactions',
      columns: ['installment_group'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final group = rows.firstOrNull?['installment_group'] as String?;
    if (group == null) {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
      return;
    }
    final groupRows = await db.query(
      'transactions',
      columns: ['competence'],
      where: 'installment_group = ?',
      whereArgs: [group],
    );
    for (final row in groupRows) {
      await _ensureCompetenceOpen(db, row['competence']! as String);
    }
    await db.delete(
      'transactions',
      where: 'installment_group = ?',
      whereArgs: [group],
    );
  }

  Future<void> markOverdueTransactions() async {
    final db = await _database.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.update(
      'transactions',
      {'status': TransactionStatus.atrasado.name},
      where: "status = 'pendente' AND due_date < ?",
      whereArgs: [today],
    );
  }

  Future<FinancialSummary> summary(String competence) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'receita' THEN installment_amount ELSE 0 END), 0) income,
        COALESCE(SUM(CASE WHEN type = 'despesa' AND status = 'pago' THEN installment_amount ELSE 0 END), 0) paid,
        COALESCE(SUM(CASE WHEN type = 'despesa' AND status = 'pendente' THEN installment_amount ELSE 0 END), 0) pending,
        COALESCE(SUM(CASE WHEN type = 'despesa' AND status = 'atrasado' THEN installment_amount ELSE 0 END), 0) overdue
      FROM transactions
      WHERE competence = ?
    ''',
      [competence],
    );
    final row = rows.single;
    return FinancialSummary(
      income: (row['income']! as num).toDouble(),
      paid: (row['paid']! as num).toDouble(),
      pending: (row['pending']! as num).toDouble(),
      overdue: (row['overdue']! as num).toDouble(),
    );
  }

  Future<double> creditStatementTotal(String competence) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(installment_amount), 0) total "
      "FROM transactions WHERE competence = ? "
      "AND type = 'despesa' AND payment_method = 'credito'",
      [competence],
    );
    return (rows.single['total']! as num).toDouble();
  }

  Future<void> payCreditStatement(String competence) async {
    final db = await _database.database;
    await _ensureCompetenceOpen(db, competence);
    await db.update(
      'transactions',
      {'status': TransactionStatus.pago.name},
      where:
          "competence = ? AND type = 'despesa' "
          "AND payment_method = 'credito' AND status != 'pago'",
      whereArgs: [competence],
    );
  }

  Future<void> saveGoal({
    required String category,
    required double limit,
    required int alertPercentage,
  }) async {
    if (category.trim().isEmpty || limit <= 0) {
      throw ArgumentError('Informe uma categoria e um limite válido.');
    }
    final db = await _database.database;
    await db.insert('goals', {
      'id': _id(),
      'category': category.trim(),
      'amount_limit': limit,
      'alert_percentage': alertPercentage,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteGoal(String id) async {
    final db = await _database.database;
    await db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SpendingGoal>> listGoals(String competence) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT g.id, g.category, g.amount_limit, g.alert_percentage,
        COALESCE(SUM(t.installment_amount), 0) spent
      FROM goals g
      LEFT JOIN transactions t
        ON t.category = g.category COLLATE NOCASE
        AND t.type = 'despesa'
        AND t.competence = ?
      GROUP BY g.id, g.category, g.amount_limit, g.alert_percentage
      ORDER BY g.category COLLATE NOCASE
    ''',
      [competence],
    );
    return rows
        .map(
          (row) => SpendingGoal(
            id: row['id']! as String,
            category: row['category']! as String,
            limit: (row['amount_limit']! as num).toDouble(),
            alertPercentage: row['alert_percentage']! as int,
            spent: (row['spent']! as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<AppSettings> getSettings() async {
    final db = await _database.database;
    final rows = await db.query('settings');
    final values = <String, String>{
      for (final row in rows)
        row['setting_key']! as String: row['setting_value']! as String,
    };
    return AppSettings(
      creditDueDay: int.tryParse(values['credit_due_day'] ?? '') ?? 10,
      creditToNextMonth: values['credit_to_next_month'] != '0',
      notificationsEnabled: values['notifications_enabled'] == '1',
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    if (settings.creditDueDay < 1 || settings.creditDueDay > 31) {
      throw ArgumentError('O vencimento do cartão deve estar entre 1 e 31.');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final values = {
        'credit_due_day': '${settings.creditDueDay}',
        'credit_to_next_month': settings.creditToNextMonth ? '1' : '0',
        'notifications_enabled': settings.notificationsEnabled ? '1' : '0',
      };
      for (final entry in values.entries) {
        await txn.insert('settings', {
          'setting_key': entry.key,
          'setting_value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<RecurringRule>> listRecurringRules() async {
    final db = await _database.database;
    final rows = await db.query(
      'recurring_rules',
      orderBy: 'active DESC, description COLLATE NOCASE',
    );
    return rows.map(RecurringRule.fromMap).toList();
  }

  Future<void> setRecurringRuleActive(String id, bool active) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.update(
        'recurring_rules',
        {'active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (!active) {
        await txn.delete(
          'transactions',
          where: 'recurring_rule_id = ? AND competence > ?',
          whereArgs: [id, competenceOf(DateTime.now())],
        );
      }
    });
  }

  Future<void> updateRecurringRuleEnd(String id, DateTime? until) async {
    final db = await _database.database;
    final rules = await db.query(
      'recurring_rules',
      columns: ['start_competence'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rules.isEmpty) throw StateError('Conta fixa não encontrada.');
    final start = rules.single['start_competence']! as String;
    final end = until == null ? null : competenceOf(until);
    if (end != null && end.compareTo(start) < 0) {
      throw ArgumentError('A data final não pode ser anterior ao início.');
    }

    await db.transaction((txn) async {
      if (end != null) {
        final futureRows = await txn.query(
          'transactions',
          columns: ['competence'],
          where: 'recurring_rule_id = ? AND competence > ?',
          whereArgs: [id, end],
        );
        for (final row in futureRows) {
          await _ensureCompetenceOpen(txn, row['competence']! as String);
        }
        await txn.delete(
          'transactions',
          where: 'recurring_rule_id = ? AND competence > ?',
          whereArgs: [id, end],
        );
      }
      await txn.update(
        'recurring_rules',
        {'end_competence': end},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> updateRecurringRule(
    String id,
    RecurringRuleUpdate update,
  ) async {
    if (update.amount <= 0 ||
        update.category.trim().isEmpty ||
        update.description.trim().isEmpty) {
      throw ArgumentError('Informe descrição, categoria e valor válidos.');
    }
    if (update.dueDay < 1 || update.dueDay > 31) {
      throw ArgumentError('O vencimento deve estar entre 1 e 31.');
    }
    if (update.sharedPeople < 1 ||
        update.sharedPeople > 100 ||
        (update.type == TransactionType.receita && update.sharedPeople > 1)) {
      throw ArgumentError('Divisão da conta inválida.');
    }
    final db = await _database.database;
    final rules = await db.query(
      'recurring_rules',
      columns: ['start_competence'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rules.isEmpty) throw StateError('Conta recorrente não encontrada.');
    final start = rules.single['start_competence']! as String;
    if (update.endCompetence != null &&
        update.endCompetence!.compareTo(start) < 0) {
      throw ArgumentError('A data final não pode ser anterior ao início.');
    }
    final currentCompetence = competenceOf(DateTime.now());
    final personalAmount =
        ((update.amount * 100).round() / update.sharedPeople).round() / 100;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: "recurring_rule_id = ? AND competence >= ? AND status != 'pago'",
        whereArgs: [id, currentCompetence],
      );
      for (final row in rows) {
        final competence = row['competence']! as String;
        if (update.endCompetence != null &&
            competence.compareTo(update.endCompetence!) > 0) {
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          continue;
        }
        await _ensureCompetenceOpen(txn, competence);
        final parts = competence.split('-');
        final dueDate = _dateWithDay(
          DateTime(int.parse(parts[0]), int.parse(parts[1])),
          update.dueDay,
        );
        final today = DateTime.now();
        final todayOnly = DateTime(today.year, today.month, today.day);
        await txn.update(
          'transactions',
          {
            'type': update.type.name,
            'payment_method': update.paymentMethod.name,
            'category': update.category.trim(),
            'description': update.description.trim(),
            'place': update.place.trim(),
            'total_amount': update.amount,
            'installment_amount': personalAmount,
            'shared_people': update.sharedPeople,
            'status': update.type == TransactionType.receita
                ? TransactionStatus.pago.name
                : dueDate.isBefore(todayOnly)
                ? TransactionStatus.atrasado.name
                : TransactionStatus.pendente.name,
            'due_date': _date(dueDate),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.update(
        'recurring_rules',
        {
          'type': update.type.name,
          'payment_method': update.paymentMethod.name,
          'category': update.category.trim(),
          'description': update.description.trim(),
          'place': update.place.trim(),
          'amount': update.amount,
          'shared_people': update.sharedPeople,
          'due_day': update.dueDay,
          'end_competence': update.endCompetence,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deleteRecurringRule(String id) async {
    final db = await _database.database;
    final current = competenceOf(DateTime.now());
    await db.transaction((txn) async {
      final future = await txn.query(
        'transactions',
        columns: ['competence'],
        where: "recurring_rule_id = ? AND competence >= ? AND status != 'pago'",
        whereArgs: [id, current],
      );
      for (final row in future) {
        await _ensureCompetenceOpen(txn, row['competence']! as String);
      }
      await txn.delete(
        'transactions',
        where: "recurring_rule_id = ? AND competence >= ? AND status != 'pago'",
        whereArgs: [id, current],
      );
      await txn.update(
        'transactions',
        {'recurring_rule_id': null, 'recurring': 0},
        where: 'recurring_rule_id = ?',
        whereArgs: [id],
      );
      await txn.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<CsvImportResult> importTransactions(
    List<ImportedTransaction> items,
  ) async {
    final db = await _database.database;
    var imported = 0;
    var skipped = 0;
    await db.transaction((txn) async {
      for (final item in items) {
        final duplicate = await txn.query(
          'transactions',
          columns: ['id'],
          where:
              'competence = ? AND due_date = ? AND type = ? '
              'AND description = ? AND category = ? AND place = ? '
              'AND payment_method = ? AND status = ? AND installment_amount = ?',
          whereArgs: [
            item.competence,
            _date(item.dueDate),
            item.type.name,
            item.description,
            item.category,
            item.place,
            item.paymentMethod.name,
            item.status.name,
            item.amount,
          ],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          skipped++;
          continue;
        }
        await _ensureCompetenceOpen(txn, item.competence);
        await txn.insert(
          'transactions',
          FinancialTransaction(
            id: _id(),
            type: item.type,
            paymentMethod: item.paymentMethod,
            category: item.category,
            description: item.description,
            place: item.place,
            totalAmount: item.amount,
            installmentAmount: item.amount,
            installmentNumber: 1,
            installmentCount: 1,
            status: item.type == TransactionType.receita
                ? TransactionStatus.pago
                : item.status,
            purchaseDate: item.dueDate,
            dueDate: item.dueDate,
            competence: item.competence,
            createdAt: DateTime.now(),
          ).toMap(),
        );
        imported++;
      }
    });
    return CsvImportResult(imported: imported, skipped: skipped);
  }

  Future<void> generateRecurringForMonth(DateTime month) async {
    final db = await _database.database;
    final competence = competenceOf(month);
    final closed = await getClosure(competence);
    if (closed != null) return;
    final rows = await db.query(
      'recurring_rules',
      where:
          'active = 1 AND start_competence <= ? '
          'AND (end_competence IS NULL OR end_competence >= ?)',
      whereArgs: [competence, competence],
    );
    for (final row in rows) {
      final rule = RecurringRule.fromMap(row);
      final dueDate = _dateWithDay(month, rule.dueDay);
      final purchaseDate = rule.paymentMethod == PaymentMethod.credito
          ? _addMonths(dueDate, -1)
          : DateTime(month.year, month.month, 1);
      final personalAmount =
          (((rule.amount * 100).round() / rule.sharedPeople).round()) / 100;
      final transaction = FinancialTransaction(
        id: _id(),
        recurringRuleId: rule.id,
        type: rule.type,
        paymentMethod: rule.paymentMethod,
        category: rule.category,
        description: rule.description,
        place: rule.place,
        totalAmount: rule.amount,
        installmentAmount: personalAmount,
        installmentNumber: 1,
        installmentCount: 1,
        sharedPeople: rule.sharedPeople,
        recurring: true,
        status: rule.type == TransactionType.receita
            ? TransactionStatus.pago
            : TransactionStatus.pendente,
        purchaseDate: purchaseDate,
        dueDate: dueDate,
        competence: competence,
        createdAt: DateTime.now(),
      );
      await db.insert(
        'transactions',
        transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> generateRecurringThrough(DateTime targetMonth) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT MIN(start_competence) first_competence '
      'FROM recurring_rules WHERE active = 1',
    );
    final first = rows.single['first_competence'] as String?;
    if (first == null) return;
    final parts = first.split('-');
    var month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final target = DateTime(targetMonth.year, targetMonth.month);
    var generated = 0;
    while (!month.isAfter(target) && generated < 240) {
      await generateRecurringForMonth(month);
      month = DateTime(month.year, month.month + 1);
      generated++;
    }
  }

  Future<List<GoalAlert>> claimNewGoalAlerts(String competence) async {
    final db = await _database.database;
    final goals = await listGoals(competence);
    final alerts = <GoalAlert>[];
    for (final goal in goals) {
      final level = goal.progress >= 1
          ? 'limit'
          : goal.progress >= goal.alertPercentage / 100
          ? 'warning'
          : null;
      if (level == null) continue;
      final inserted = await db.insert('goal_alert_events', {
        'goal_id': goal.id,
        'competence': competence,
        'alert_level': level,
        'notified_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (inserted > 0) alerts.add(GoalAlert(goal: goal, level: level));
    }
    return alerts;
  }

  Future<MonthlyClosure?> getClosure(String competence) async {
    final db = await _database.database;
    final rows = await db.query(
      'monthly_closures',
      where: 'competence = ?',
      whereArgs: [competence],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return MonthlyClosure(
      competence: row['competence']! as String,
      closedAt: DateTime.parse(row['closed_at']! as String),
      summary: FinancialSummary(
        income: (row['income']! as num).toDouble(),
        paid: (row['paid']! as num).toDouble(),
        pending: (row['pending']! as num).toDouble(),
        overdue: (row['overdue']! as num).toDouble(),
      ),
    );
  }

  Future<void> closeMonth(String competence) async {
    final db = await _database.database;
    final currentSummary = await summary(competence);
    await db.insert('monthly_closures', {
      'competence': competence,
      'closed_at': DateTime.now().toIso8601String(),
      'income': currentSummary.income,
      'paid': currentSummary.paid,
      'pending': currentSummary.pending,
      'overdue': currentSummary.overdue,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> reopenMonth(String competence) async {
    final db = await _database.database;
    await db.delete(
      'monthly_closures',
      where: 'competence = ?',
      whereArgs: [competence],
    );
  }

  Future<void> _ensureTransactionOpen(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'transactions',
      columns: ['competence'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Lançamento não encontrado.');
    await _ensureCompetenceOpen(db, rows.single['competence']! as String);
  }

  Future<void> _ensureCompetenceOpen(
    DatabaseExecutor db,
    String competence,
  ) async {
    final rows = await db.query(
      'monthly_closures',
      columns: ['competence'],
      where: 'competence = ?',
      whereArgs: [competence],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError(
        'O mês $competence está fechado. Reabra-o antes de alterar lançamentos.',
      );
    }
  }
}

String _id() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

DateTime _addMonths(DateTime date, int months) {
  final first = DateTime(date.year, date.month + months, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, date.day.clamp(1, lastDay));
}

String _date(DateTime date) => date.toIso8601String().substring(0, 10);

DateTime _dateWithDay(DateTime month, int day) {
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, day.clamp(1, lastDay));
}
