import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/financial_models.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    const android = AndroidInitializationSettings('ic_notification');
    await _plugin.initialize(const InitializationSettings(android: android));
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> showGoalAlert(GoalAlert alert) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'spending_limits',
        'Limites de gastos',
        channelDescription: 'Alertas quando os limites mensais são atingidos.',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
    );
    final goal = alert.goal;
    final title = alert.level == 'limit'
        ? 'Limite ultrapassado: ${goal.category}'
        : 'Atenção ao limite: ${goal.category}';
    final percentage = (goal.progress * 100).round();
    await _plugin.show(
      Object.hash(goal.id, alert.level, DateTime.now().year),
      title,
      'Você já utilizou $percentage% do limite mensal.',
      details,
    );
  }

  Future<void> syncPaymentReminders(
    List<FinancialTransaction> transactions, {
    required bool enabled,
  }) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('payment:') ?? false) {
        await _plugin.cancel(request.id);
      }
    }
    if (!enabled) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'payment_due_dates',
        'Vencimentos de contas',
        channelDescription: 'Lembretes de despesas no dia do vencimento.',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
    );
    final now = tz.TZDateTime.now(tz.local);
    for (final transaction in transactions) {
      final due = tz.TZDateTime(
        tz.local,
        transaction.dueDate.year,
        transaction.dueDate.month,
        transaction.dueDate.day,
        9,
      );
      if (!due.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        _paymentNotificationId(transaction.id),
        'Conta vence hoje: ${transaction.description}',
        'Valor: R\$ ${transaction.installmentAmount.toStringAsFixed(2).replaceAll('.', ',')}. Toque para abrir o app.',
        due,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'payment:${transaction.id}',
      );
    }
  }

  int _paymentNotificationId(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x3FFFFFFF;
    }
    return hash | 0x40000000;
  }
}
