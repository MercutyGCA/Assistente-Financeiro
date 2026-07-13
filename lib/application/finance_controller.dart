import 'package:flutter/foundation.dart';

import '../data/finance_repository.dart';
import '../domain/financial_models.dart';
import '../services/notification_service.dart';
import '../services/report_export_service.dart';
import '../services/csv_import_service.dart';

class FinanceController extends ChangeNotifier {
  FinanceController({
    FinanceRepository? repository,
    NotificationService? notifications,
    ReportExportService? reportExporter,
    CsvImportService? csvImporter,
  }) : _repository = repository ?? FinanceRepository(),
       _notifications = notifications ?? NotificationService(),
       _reportExporter = reportExporter ?? ReportExportService(),
       _csvImporter = csvImporter ?? CsvImportService();

  final FinanceRepository _repository;
  final NotificationService _notifications;
  final ReportExportService _reportExporter;
  final CsvImportService _csvImporter;
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<FinancialTransaction> transactions = const [];
  List<SpendingGoal> goals = const [];
  FinancialSummary summary = const FinancialSummary();
  MonthlyClosure? closure;
  AppSettings settings = const AppSettings();
  List<RecurringRule> recurringRules = const [];
  double creditStatement = 0;
  DateTime reportStart = DateTime(DateTime.now().year, 1);
  DateTime reportEnd = DateTime(DateTime.now().year, DateTime.now().month);
  FinancialReport? report;
  bool reportLoading = false;
  bool loading = true;
  String? error;

  String get competence => competenceOf(selectedMonth);

  Future<void> initialize() async {
    await _notifications.initialize();
    await _repository.generateRecurringThrough(
      DateTime(selectedMonth.year, selectedMonth.month + 12),
    );
    await _repository.markOverdueTransactions();
    await refresh();
    await _syncPaymentReminders();
    await _notifyNewGoalAlerts();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait<Object?>([
        _repository.listTransactions(competence),
        _repository.listGoals(competence),
        _repository.summary(competence),
        _repository.getClosure(competence),
        _repository.getSettings(),
        _repository.listRecurringRules(),
        _repository.creditStatementTotal(competence),
      ]);
      transactions = values[0] as List<FinancialTransaction>;
      goals = values[1] as List<SpendingGoal>;
      summary = values[2] as FinancialSummary;
      closure = values[3] as MonthlyClosure?;
      settings = values[4] as AppSettings;
      recurringRules = values[5] as List<RecurringRule>;
      creditStatement = values[6] as double;
    } catch (exception) {
      error = 'Não foi possível carregar os dados: $exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> changeMonth(int offset) async {
    selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + offset);
    await _repository.generateRecurringForMonth(selectedMonth);
    await refresh();
    await _syncPaymentReminders();
    await _notifyNewGoalAlerts();
  }

  Future<void> addTransaction(TransactionDraft draft) async {
    await _repository.addTransaction(draft);
    if (draft.recurring) {
      final now = DateTime.now();
      await _repository.generateRecurringThrough(
        DateTime(now.year, now.month + 12),
      );
    }
    await refresh();
    await _syncPaymentReminders();
    await _notifyNewGoalAlerts();
  }

  Future<void> updateStatus(String id, TransactionStatus status) async {
    await _repository.updateStatus(id, status);
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> payCreditStatement() async {
    await _repository.payCreditStatement(competence);
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> updateTransaction(String id, TransactionUpdate update) async {
    await _repository.updateTransaction(id, update);
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> deleteTransaction(String id, {bool entireGroup = false}) async {
    await _repository.deleteTransaction(id, entireGroup: entireGroup);
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> saveGoal(String category, double limit, int alert) async {
    await _repository.saveGoal(
      category: category,
      limit: limit,
      alertPercentage: alert,
    );
    await refresh();
    await _notifyNewGoalAlerts();
  }

  Future<void> deleteGoal(String id) async {
    await _repository.deleteGoal(id);
    await refresh();
  }

  Future<void> saveSettings(AppSettings updated) async {
    var effective = updated;
    if (updated.notificationsEnabled && !settings.notificationsEnabled) {
      final allowed = await _notifications.requestPermission();
      if (!allowed) {
        effective = updated.copyWith(notificationsEnabled: false);
        throw StateError('A permissão de notificações não foi concedida.');
      }
    }
    await _repository.saveSettings(effective);
    await refresh();
    await _syncPaymentReminders();
    await _notifyNewGoalAlerts();
  }

  Future<void> setRecurringRuleActive(String id, bool active) async {
    await _repository.setRecurringRuleActive(id, active);
    if (active) {
      final now = DateTime.now();
      await _repository.generateRecurringThrough(
        DateTime(now.year, now.month + 12),
      );
    }
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> updateRecurringRuleEnd(String id, DateTime? until) async {
    await _repository.updateRecurringRuleEnd(id, until);
    final now = DateTime.now();
    await _repository.generateRecurringThrough(
      DateTime(now.year, now.month + 12),
    );
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> updateRecurringRule(
    String id,
    RecurringRuleUpdate update,
  ) async {
    await _repository.updateRecurringRule(id, update);
    final now = DateTime.now();
    await _repository.generateRecurringThrough(
      DateTime(now.year, now.month + 12),
    );
    await refresh();
    await _syncPaymentReminders();
  }

  Future<void> deleteRecurringRule(String id) async {
    await _repository.deleteRecurringRule(id);
    await refresh();
    await _syncPaymentReminders();
  }

  Future<CsvImportResult?> importReportCsv() async {
    final items = await _csvImporter.pickTransactions();
    if (items == null) return null;
    final result = await _repository.importTransactions(items);
    await _repository.markOverdueTransactions();
    await refresh();
    await _syncPaymentReminders();
    await _notifyNewGoalAlerts();
    return result;
  }

  Future<void> loadReport({DateTime? start, DateTime? end}) async {
    reportStart = DateTime(
      (start ?? reportStart).year,
      (start ?? reportStart).month,
    );
    reportEnd = DateTime((end ?? reportEnd).year, (end ?? reportEnd).month);
    if (reportStart.isAfter(reportEnd)) {
      if (start != null) {
        reportEnd = reportStart;
      } else {
        reportStart = reportEnd;
      }
    }
    reportLoading = true;
    notifyListeners();
    try {
      report = await _repository.buildReport(
        competenceOf(reportStart),
        competenceOf(reportEnd),
      );
    } finally {
      reportLoading = false;
      notifyListeners();
    }
  }

  Future<void> exportReportPdf() async {
    final current = report;
    if (current == null) {
      throw StateError('Gere o relatório antes de exportar.');
    }
    await _reportExporter.sharePdf(current);
  }

  Future<void> exportReportCsv() async {
    final current = report;
    if (current == null) {
      throw StateError('Gere o relatório antes de exportar.');
    }
    await _reportExporter.shareCsv(current);
  }

  Future<void> _notifyNewGoalAlerts() async {
    if (!settings.notificationsEnabled) return;
    final nextMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
    for (final target in [competence, competenceOf(nextMonth)]) {
      final alerts = await _repository.claimNewGoalAlerts(target);
      for (final alert in alerts) {
        await _notifications.showGoalAlert(alert);
      }
    }
  }

  Future<void> _syncPaymentReminders() async {
    final reminders = settings.notificationsEnabled
        ? await _repository.listPendingPaymentReminders()
        : const <FinancialTransaction>[];
    await _notifications.syncPaymentReminders(
      reminders,
      enabled: settings.notificationsEnabled,
    );
  }

  Future<void> closeMonth() async {
    await _repository.closeMonth(competence);
    await refresh();
  }

  Future<void> reopenMonth() async {
    await _repository.reopenMonth(competence);
    await refresh();
  }
}
