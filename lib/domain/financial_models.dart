enum TransactionType { receita, despesa }

enum PaymentMethod { pix, debito, credito }

enum TransactionStatus { pago, pendente, atrasado }

enum DashboardTransactionFilter { receitas, pagas, pendentes, atrasadas }

extension DashboardTransactionFilterLabel on DashboardTransactionFilter {
  String get title => switch (this) {
    DashboardTransactionFilter.receitas => 'Receitas',
    DashboardTransactionFilter.pagas => 'Despesas pagas',
    DashboardTransactionFilter.pendentes => 'Despesas pendentes',
    DashboardTransactionFilter.atrasadas => 'Despesas em atraso',
  };
}

List<FinancialTransaction> filterDashboardTransactions(
  Iterable<FinancialTransaction> transactions,
  DashboardTransactionFilter filter,
) {
  return transactions.where((item) {
    return switch (filter) {
      DashboardTransactionFilter.receitas =>
        item.type == TransactionType.receita,
      DashboardTransactionFilter.pagas =>
        item.type == TransactionType.despesa &&
            item.status == TransactionStatus.pago,
      DashboardTransactionFilter.pendentes =>
        item.type == TransactionType.despesa &&
            item.status == TransactionStatus.pendente,
      DashboardTransactionFilter.atrasadas =>
        item.type == TransactionType.despesa &&
            item.status == TransactionStatus.atrasado,
    };
  }).toList();
}

class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.type,
    required this.paymentMethod,
    required this.category,
    required this.description,
    required this.place,
    required this.totalAmount,
    required this.installmentAmount,
    required this.installmentNumber,
    required this.installmentCount,
    required this.status,
    required this.purchaseDate,
    required this.dueDate,
    required this.competence,
    required this.createdAt,
    this.installmentGroup,
    this.recurringRuleId,
    this.recurring = false,
    this.sharedPeople = 1,
  });

  final String id;
  final String? installmentGroup;
  final String? recurringRuleId;
  final TransactionType type;
  final PaymentMethod paymentMethod;
  final String category;
  final String description;
  final String place;
  final double totalAmount;
  final double installmentAmount;
  final int installmentNumber;
  final int installmentCount;
  final bool recurring;
  final int sharedPeople;
  final TransactionStatus status;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final String competence;
  final DateTime createdAt;

  double get personalShareTotal =>
      ((totalAmount * 100).round() / sharedPeople).round() / 100;

  factory FinancialTransaction.fromMap(Map<String, Object?> map) {
    return FinancialTransaction(
      id: map['id']! as String,
      installmentGroup: map['installment_group'] as String?,
      recurringRuleId: map['recurring_rule_id'] as String?,
      type: TransactionType.values.byName(map['type']! as String),
      paymentMethod: PaymentMethod.values.byName(
        map['payment_method']! as String,
      ),
      category: map['category']! as String,
      description: map['description']! as String,
      place: map['place']! as String,
      totalAmount: (map['total_amount']! as num).toDouble(),
      installmentAmount: (map['installment_amount']! as num).toDouble(),
      installmentNumber: map['installment_number']! as int,
      installmentCount: map['installment_count']! as int,
      recurring: map['recurring'] == 1,
      sharedPeople: (map['shared_people'] as int?) ?? 1,
      status: TransactionStatus.values.byName(map['status']! as String),
      purchaseDate: DateTime.parse(map['purchase_date']! as String),
      dueDate: DateTime.parse(map['due_date']! as String),
      competence: map['competence']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'installment_group': installmentGroup,
    'recurring_rule_id': recurringRuleId,
    'type': type.name,
    'payment_method': paymentMethod.name,
    'category': category,
    'description': description,
    'place': place,
    'total_amount': totalAmount,
    'installment_amount': installmentAmount,
    'installment_number': installmentNumber,
    'installment_count': installmentCount,
    'recurring': recurring ? 1 : 0,
    'shared_people': sharedPeople,
    'status': status.name,
    'purchase_date': _date(purchaseDate),
    'due_date': _date(dueDate),
    'competence': competence,
    'created_at': createdAt.toIso8601String(),
  };
}

class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.paymentMethod,
    required this.category,
    required this.description,
    required this.place,
    required this.amount,
    required this.purchaseDate,
    required this.dueDate,
    this.installments = 1,
    this.recurring = false,
    this.recurringUntil,
    this.sharedPeople = 1,
    this.remindOnDueDate = false,
  });

  final TransactionType type;
  final PaymentMethod paymentMethod;
  final String category;
  final String description;
  final String place;
  final double amount;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final int installments;
  final bool recurring;
  final DateTime? recurringUntil;
  final int sharedPeople;
  final bool remindOnDueDate;
}

class TransactionUpdate {
  const TransactionUpdate({
    required this.type,
    required this.paymentMethod,
    required this.category,
    required this.description,
    required this.place,
    required this.amount,
    required this.purchaseDate,
    required this.dueDate,
    required this.status,
    required this.sharedPeople,
  });

  final TransactionType type;
  final PaymentMethod paymentMethod;
  final String category;
  final String description;
  final String place;
  final double amount;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final TransactionStatus status;
  final int sharedPeople;
}

class RecurringRuleUpdate {
  const RecurringRuleUpdate({
    required this.type,
    required this.paymentMethod,
    required this.category,
    required this.description,
    required this.place,
    required this.amount,
    required this.sharedPeople,
    required this.dueDay,
    required this.endCompetence,
  });

  final TransactionType type;
  final PaymentMethod paymentMethod;
  final String category;
  final String description;
  final String place;
  final double amount;
  final int sharedPeople;
  final int dueDay;
  final String? endCompetence;
}

class ImportedTransaction {
  const ImportedTransaction({
    required this.competence,
    required this.dueDate,
    required this.type,
    required this.description,
    required this.category,
    required this.place,
    required this.paymentMethod,
    required this.status,
    required this.amount,
  });

  final String competence;
  final DateTime dueDate;
  final TransactionType type;
  final String description;
  final String category;
  final String place;
  final PaymentMethod paymentMethod;
  final TransactionStatus status;
  final double amount;
}

class CsvImportResult {
  const CsvImportResult({required this.imported, required this.skipped});
  final int imported;
  final int skipped;
}

class SpendingGoal {
  const SpendingGoal({
    required this.id,
    required this.category,
    required this.limit,
    required this.alertPercentage,
    this.spent = 0,
  });

  final String id;
  final String category;
  final double limit;
  final int alertPercentage;
  final double spent;

  double get progress => limit <= 0 ? 0 : spent / limit;
}

class FinancialSummary {
  const FinancialSummary({
    this.income = 0,
    this.paid = 0,
    this.pending = 0,
    this.overdue = 0,
  });

  final double income;
  final double paid;
  final double pending;
  final double overdue;

  double get currentBalance => income - paid;
  double get projectedBalance => income - paid - pending - overdue;
  double get commitment =>
      income <= 0 ? 1 : (paid + pending + overdue) / income;

  int get score {
    var value = 100;
    if (overdue > 0) value -= 30;
    if (commitment >= 1) {
      value -= 40;
    } else if (commitment >= .7) {
      value -= 20;
    } else if (commitment >= .5) {
      value -= 10;
    }
    if (projectedBalance > 0) value += 5;
    return value.clamp(0, 100);
  }

  int scoreWithGoals(Iterable<SpendingGoal> goals) {
    var value = score;
    for (final goal in goals) {
      if (goal.progress >= 1) {
        value -= 15;
      } else if (goal.progress >= goal.alertPercentage / 100) {
        value -= 5;
      }
    }
    return value.clamp(0, 100);
  }

  String get classification {
    return scoreClassification(score);
  }
}

String scoreClassification(int score) {
  if (score >= 85) return 'Excelente';
  if (score >= 70) return 'Boa';
  if (score >= 50) return 'Regular';
  return 'Crítica';
}

class MonthlyClosure {
  const MonthlyClosure({
    required this.competence,
    required this.closedAt,
    required this.summary,
  });

  final String competence;
  final DateTime closedAt;
  final FinancialSummary summary;
}

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.type,
    required this.paymentMethod,
    required this.category,
    required this.description,
    required this.place,
    required this.amount,
    required this.dueDay,
    required this.startCompetence,
    required this.endCompetence,
    required this.active,
    required this.sharedPeople,
  });

  final String id;
  final TransactionType type;
  final PaymentMethod paymentMethod;
  final String category;
  final String description;
  final String place;
  final double amount;
  final int dueDay;
  final String startCompetence;
  final String? endCompetence;
  final bool active;
  final int sharedPeople;

  factory RecurringRule.fromMap(Map<String, Object?> map) => RecurringRule(
    id: map['id']! as String,
    type: TransactionType.values.byName(map['type']! as String),
    paymentMethod: PaymentMethod.values.byName(
      map['payment_method']! as String,
    ),
    category: map['category']! as String,
    description: map['description']! as String,
    place: map['place']! as String,
    amount: (map['amount']! as num).toDouble(),
    dueDay: map['due_day']! as int,
    startCompetence: map['start_competence']! as String,
    endCompetence: map['end_competence'] as String?,
    active: map['active'] == 1,
    sharedPeople: (map['shared_people'] as int?) ?? 1,
  );
}

class AppSettings {
  const AppSettings({
    this.creditDueDay = 10,
    this.creditToNextMonth = true,
    this.notificationsEnabled = false,
  });

  final int creditDueDay;
  final bool creditToNextMonth;
  final bool notificationsEnabled;

  AppSettings copyWith({
    int? creditDueDay,
    bool? creditToNextMonth,
    bool? notificationsEnabled,
  }) => AppSettings(
    creditDueDay: creditDueDay ?? this.creditDueDay,
    creditToNextMonth: creditToNextMonth ?? this.creditToNextMonth,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );
}

class GoalAlert {
  const GoalAlert({required this.goal, required this.level});
  final SpendingGoal goal;
  final String level;
}

class ReportCategory {
  const ReportCategory({required this.category, required this.amount});
  final String category;
  final double amount;
}

class ReportMonth {
  const ReportMonth({
    required this.competence,
    required this.income,
    required this.expenses,
  });
  final String competence;
  final double income;
  final double expenses;
  double get balance => income - expenses;
}

class FinancialReport {
  const FinancialReport({
    required this.startCompetence,
    required this.endCompetence,
    required this.transactions,
    required this.income,
    required this.paid,
    required this.pending,
    required this.overdue,
    required this.categories,
    required this.months,
  });

  final String startCompetence;
  final String endCompetence;
  final List<FinancialTransaction> transactions;
  final double income;
  final double paid;
  final double pending;
  final double overdue;
  final List<ReportCategory> categories;
  final List<ReportMonth> months;

  double get expenses => paid + pending + overdue;
  double get balance => income - expenses;
}

String competenceOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String _date(DateTime date) => date.toIso8601String().substring(0, 10);
