import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/finance_controller.dart';
import '../domain/financial_models.dart';
import 'filtered_transactions_screen.dart';
import 'recurring_rule_form.dart';
import 'reports_screen.dart';
import 'transaction_form.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _month = DateFormat('MMMM yyyy', 'pt_BR');

String _competenceLabel(String competence) {
  final parts = competence.split('-');
  return '${parts[1]}/${parts[0]}';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final FinanceController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              [
                'Visão geral',
                'Lançamentos',
                'Limites',
                'Configurações',
                'Relatórios',
              ][page],
            ),
            actions: [
              IconButton(
                tooltip: 'Atualizar',
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (page < 3) _MonthSelector(controller: controller),
              Expanded(child: _body(controller)),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: page,
            onDestinationSelected: (value) {
              setState(() => page = value);
              if (value == 4 && controller.report == null) {
                controller.loadReport();
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Resumo',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Lançamentos',
              ),
              NavigationDestination(
                icon: Icon(Icons.flag_outlined),
                selectedIcon: Icon(Icons.flag),
                label: 'Limites',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Ajustes',
              ),
              NavigationDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics),
                label: 'Relatórios',
              ),
            ],
          ),
          floatingActionButton:
              page == 0 ||
                  page >= 3 ||
                  (page == 1 && controller.closure != null)
              ? null
              : FloatingActionButton.extended(
                  onPressed: page == 1 ? _addTransaction : _addGoal,
                  icon: const Icon(Icons.add),
                  label: Text(page == 1 ? 'Lançamento' : 'Meta'),
                ),
        );
      },
    );
  }

  Widget _body(FinanceController controller) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: 'Algo deu errado',
        message: controller.error!,
        action: controller.refresh,
      );
    }
    return switch (page) {
      0 => _Dashboard(controller: controller),
      1 => _Transactions(controller: controller),
      2 => _Goals(controller: controller),
      3 => _Settings(controller: controller),
      _ => ReportsScreen(controller: controller),
    };
  }

  Future<void> _addTransaction() async {
    final draft = await showModalBottomSheet<TransactionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TransactionForm(),
    );
    if (draft == null) return;
    await _run(
      () => widget.controller.addTransaction(draft),
      'Lançamento salvo.',
    );
  }

  Future<void> _addGoal() async {
    final result = await showDialog<_GoalInput>(
      context: context,
      builder: (_) => const _GoalDialog(),
    );
    if (result == null) return;
    await _run(
      () => widget.controller.saveGoal(
        result.category,
        result.limit,
        result.alert,
      ),
      'Meta salva.',
    );
  }

  Future<void> _run(Future<void> Function() operation, String success) async {
    try {
      await operation();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.controller});
  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final label = _month.format(controller.selectedMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => controller.changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            width: 170,
            child: Text(
              '${label[0].toUpperCase()}${label.substring(1)}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => controller.changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.controller});
  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;
    final alerts = controller.goals
        .where((goal) => goal.progress >= goal.alertPercentage / 100)
        .toList();
    final score = summary.scoreWithGoals(controller.goals);
    final categoryTotals = <String, double>{};
    for (final item in controller.transactions) {
      if (item.type != TransactionType.despesa) continue;
      categoryTotals.update(
        item.category,
        (value) => value + item.installmentAmount,
        ifAbsent: () => item.installmentAmount,
      );
    }
    final expenseCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          _DashboardHeader(score: score),
          const SizedBox(height: 14),
          _ClosureCard(controller: controller),
          const SizedBox(height: 12),
          _BalanceCard(summary: summary),
          const SizedBox(height: 12),
          if (controller.creditStatement > 0) ...[
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.credit_card)),
                title: const Text('Fatura prevista do cartão'),
                subtitle: Text(
                  controller.closure == null
                      ? 'Toque para marcar a fatura como paga'
                      : 'Compras no crédito desta competência',
                ),
                trailing: Text(
                  _currency.format(controller.creditStatement),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: controller.closure == null
                    ? () => _payCreditStatement(context)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.65,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                'Receitas',
                summary.income,
                Icons.arrow_downward,
                const Color(0xFF267A56),
                onTap: () =>
                    _openFiltered(context, DashboardTransactionFilter.receitas),
              ),
              _MetricCard(
                'Despesas pagas',
                summary.paid,
                Icons.arrow_upward,
                const Color(0xFFA44A3F),
                onTap: () =>
                    _openFiltered(context, DashboardTransactionFilter.pagas),
              ),
              _MetricCard(
                'Pendentes',
                summary.pending,
                Icons.schedule,
                const Color(0xFFAA7418),
                onTap: () => _openFiltered(
                  context,
                  DashboardTransactionFilter.pendentes,
                ),
              ),
              _MetricCard(
                'Em atraso',
                summary.overdue,
                Icons.error_outline,
                const Color(0xFFB3261E),
                onTap: () => _openFiltered(
                  context,
                  DashboardTransactionFilter.atrasadas,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Saúde financeira',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: score / 100,
                              strokeWidth: 8,
                              strokeCap: StrokeCap.round,
                              backgroundColor: const Color(0xFFEDE5FF),
                            ),
                            Text(
                              '$score',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scoreClassification(score),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Text('Seu índice de organização financeira'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.pie_chart_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: summary.commitment.clamp(0, 1),
                            minHeight: 9,
                            backgroundColor: const Color(0xFFEDE5FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(summary.commitment * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Para onde foi seu dinheiro',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            _SpendingBreakdown(categories: expenseCategories),
          ],
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Alertas de metas',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...alerts.map(
              (goal) => Card(
                child: ListTile(
                  leading: Icon(
                    goal.progress >= 1
                        ? Icons.warning_amber
                        : Icons.notifications_active_outlined,
                  ),
                  title: Text(goal.category),
                  subtitle: Text(
                    '${_currency.format(goal.spent)} de ${_currency.format(goal.limit)}',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _payCreditStatement(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Marcar fatura como paga?'),
        content: Text(
          'Todos os lançamentos no crédito desta competência serão marcados como pagos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Marcar como paga'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.payCreditStatement();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _openFiltered(
    BuildContext context,
    DashboardTransactionFilter filter,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FilteredTransactionsScreen(
          filter: filter,
          transactions: controller.transactions,
          competence: controller.competence,
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF1EAFE),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE2D4FF)),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.asset('assets/icon/icon_app.png'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seu panorama financeiro',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                score >= 85
                    ? 'Tudo sob controle. Continue assim!'
                    : score >= 70
                    ? 'Você está no caminho certo.'
                    : 'Há oportunidades para reorganizar o mês.',
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SpendingBreakdown extends StatelessWidget {
  const _SpendingBreakdown({required this.categories});
  final List<MapEntry<String, double>> categories;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<double>(0, (sum, item) => sum + item.value);
    const colors = [
      Color(0xFF7C3AED),
      Color(0xFFA855F7),
      Color(0xFFEC4899),
      Color(0xFF6366F1),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: categories.take(4).toList().asMap().entries.map((entry) {
            final item = entry.value;
            final color = colors[entry.key % colors.length];
            final progress = total <= 0 ? 0.0 : item.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.key,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        _currency.format(item.value),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      color: color,
                      backgroundColor: color.withValues(alpha: .1),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ClosureCard extends StatelessWidget {
  const _ClosureCard({required this.controller});

  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final closure = controller.closure;
    return Card(
      color: closure == null
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(closure == null ? Icons.lock_open : Icons.lock),
        title: Text(closure == null ? 'Mês em aberto' : 'Mês fechado'),
        subtitle: Text(
          closure == null
              ? 'Lançamentos ainda podem ser alterados.'
              : 'Fechado em ${DateFormat('dd/MM/yyyy HH:mm').format(closure.closedAt)}',
        ),
        trailing: TextButton(
          onPressed: () => _toggle(context),
          child: Text(closure == null ? 'Fechar' : 'Reabrir'),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final closing = controller.closure == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(closing ? 'Fechar este mês?' : 'Reabrir este mês?'),
        content: Text(
          closing
              ? 'O resumo será registrado e os lançamentos desta competência ficarão protegidos contra alterações.'
              : 'Os lançamentos poderão ser editados e excluídos novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(closing ? 'Fechar mês' : 'Reabrir mês'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      if (closing) {
        await controller.closeMonth();
      } else {
        await controller.reopenMonth();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFFA855F7)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -25,
              top: -40,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_graph, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'SALDO PROJETADO',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currency.format(summary.projectedBalance),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Disponível agora  ${_currency.format(summary.currentBalance)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
    this.label,
    this.value,
    this.icon,
    this.color, {
    required this.onTap,
  });
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: color.withValues(alpha: .055),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              _currency.format(value),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Transactions extends StatelessWidget {
  const _Transactions({required this.controller});
  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.transactions.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nenhum lançamento',
        message: 'Adicione sua primeira receita ou despesa deste mês.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: controller.transactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = controller.transactions[index];
        final expense = item.type == TransactionType.despesa;
        final paidExpense = expense && item.status == TransactionStatus.pago;
        return Card(
          color: paidExpense ? const Color(0xFFE8F7EF) : null,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: CircleAvatar(
              backgroundColor: paidExpense
                  ? const Color(0xFFCDEEDC)
                  : expense
                  ? const Color(0xFFFFEDEA)
                  : const Color(0xFFE4F5EA),
              child: Icon(
                expense ? Icons.arrow_upward : Icons.arrow_downward,
                color: paidExpense
                    ? const Color(0xFF137A4B)
                    : expense
                    ? const Color(0xFFA44A3F)
                    : const Color(0xFF267A56),
              ),
            ),
            title: Text(
              item.description,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${item.category}${item.installmentCount > 1 ? ' • ${item.installmentNumber}/${item.installmentCount}' : ''}\n${item.status.name} • ${DateFormat('dd/MM').format(item.dueDate)}',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${expense ? '-' : '+'}${_currency.format(item.installmentAmount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: paidExpense
                        ? const Color(0xFF137A4B)
                        : expense
                        ? const Color(0xFFA44A3F)
                        : const Color(0xFF267A56),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await _edit(context, item);
                      return;
                    }
                    if (value == 'delete') {
                      await _delete(context, item);
                    } else {
                      await _execute(
                        context,
                        () => controller.updateStatus(
                          item.id,
                          TransactionStatus.values.byName(value),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    if (expense)
                      ...TransactionStatus.values.map(
                        (status) => PopupMenuItem(
                          value: status.name,
                          child: Text('Marcar como ${status.name}'),
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Excluir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, FinancialTransaction item) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionForm(transaction: item),
    );
    if (result is! TransactionUpdate || !context.mounted) return;
    await _execute(
      context,
      () => controller.updateTransaction(item.id, result),
    );
  }

  Future<void> _delete(BuildContext context, FinancialTransaction item) async {
    final entireGroup = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          item.installmentCount > 1
              ? 'Você pode excluir somente esta parcela ou todas as parcelas da compra.'
              : 'Esta ação não poderá ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          if (item.installmentCount > 1)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Só esta parcela'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, item.installmentCount > 1),
            child: Text(
              item.installmentCount > 1 ? 'Todas as parcelas' : 'Excluir',
            ),
          ),
        ],
      ),
    );
    if (entireGroup == null || !context.mounted) return;
    await _execute(
      context,
      () => controller.deleteTransaction(item.id, entireGroup: entireGroup),
    );
  }

  Future<void> _execute(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.controller});
  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.goals.isEmpty) {
      return const _EmptyState(
        icon: Icons.flag_outlined,
        title: 'Nenhuma meta',
        message: 'Crie limites mensais para acompanhar seus gastos.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: controller.goals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final goal = controller.goals[index];
        final exceeded = goal.progress >= 1;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goal.category,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _delete(context, goal),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Excluir meta',
                    ),
                  ],
                ),
                Text(
                  '${_currency.format(goal.spent)} de ${_currency.format(goal.limit)}',
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: goal.progress.clamp(0, 1),
                  color: exceeded ? Theme.of(context).colorScheme.error : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 6),
                Text(
                  exceeded
                      ? 'Limite ultrapassado'
                      : 'Alerta em ${goal.alertPercentage}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, SpendingGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir meta?'),
        content: Text('A meta de ${goal.category} será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteGoal(goal.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.controller});

  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        Text(
          'Cartão de crédito',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Cobrar no mês seguinte'),
                subtitle: const Text(
                  'Compras no crédito entram na próxima competência',
                ),
                value: settings.creditToNextMonth,
                onChanged: (value) =>
                    _save(context, settings.copyWith(creditToNextMonth: value)),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Dia de vencimento'),
                subtitle: Text('Dia ${settings.creditDueDay} de cada mês'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editDueDay(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Alertas no celular',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notificações e lembretes'),
            subtitle: const Text(
              'Avisar sobre limites e contas no vencimento, às 9h',
            ),
            value: settings.notificationsEnabled,
            onChanged: (value) =>
                _save(context, settings.copyWith(notificationsEnabled: value)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Contas fixas',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (controller.recurringRules.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.event_repeat),
              title: Text('Nenhuma conta fixa'),
              subtitle: Text(
                'Ative “Conta fixa recorrente” ao criar um lançamento.',
              ),
            ),
          )
        else
          ...controller.recurringRules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text(rule.description),
                  subtitle: Text(
                    '${rule.category} • ${_currency.format(rule.amount)} • dia ${rule.dueDay}'
                    '${rule.sharedPeople > 1 ? ' • dividido em ${rule.sharedPeople}' : ''}'
                    '${rule.endCompetence == null ? ' • sem data final' : ' • até ${_competenceLabel(rule.endCompetence!)}'}',
                  ),
                  onTap: () => _editRule(context, rule),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit'
                            ? _editRule(context, rule)
                            : _deleteRule(context, rule),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar por completo'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Excluir recorrência'),
                          ),
                        ],
                      ),
                      Switch(
                        value: rule.active,
                        onChanged: (value) =>
                            _toggleRule(context, rule.id, value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Dados e segurança',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Importar relatório CSV'),
            subtitle: const Text(
              'Restaura lançamentos do CSV exportado pelo próprio app e ignora duplicados',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _importCsv(context),
          ),
        ),
      ],
    );
  }

  Future<void> _editDueDay(BuildContext context) async {
    final input = TextEditingController(
      text: '${controller.settings.creditDueDay}',
    );
    final day = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vencimento do cartão'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Dia do mês'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(input.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    input.dispose();
    if (day == null || !context.mounted) return;
    await _save(context, controller.settings.copyWith(creditDueDay: day));
  }

  Future<void> _save(BuildContext context, AppSettings settings) async {
    try {
      await controller.saveSettings(settings);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _toggleRule(BuildContext context, String id, bool active) async {
    try {
      await controller.setRecurringRuleActive(id, active);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _editRule(BuildContext context, RecurringRule rule) async {
    final update = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecurringRuleForm(rule: rule),
    );
    if (update is! RecurringRuleUpdate || !context.mounted) return;
    try {
      await controller.updateRecurringRule(rule.id, update);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _deleteRule(BuildContext context, RecurringRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir conta recorrente?'),
        content: const Text(
          'A regra e todas as cobranças ainda não pagas deste mês em diante serão excluídas. O histórico pago será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteRecurringRule(rule.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    try {
      final result = await controller.importReportCsv();
      if (result == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.imported} lançamento(s) importado(s); ${result.skipped} duplicado(s) ignorado(s).',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível importar: $error')),
        );
      }
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: action,
              child: const Text('Tentar novamente'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _GoalInput {
  const _GoalInput(this.category, this.limit, this.alert);
  final String category;
  final double limit;
  final int alert;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog();
  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final formKey = GlobalKey<FormState>();
  final category = TextEditingController();
  final limit = TextEditingController();
  double alert = 80;

  @override
  void dispose() {
    category.dispose();
    limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nova meta mensal'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: category,
            decoration: const InputDecoration(labelText: 'Categoria'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Informe a categoria' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Limite mensal',
              prefixText: 'R\$ ',
            ),
            validator: (v) => _number(v) == null || _number(v)! <= 0
                ? 'Informe um valor válido'
                : null,
          ),
          const SizedBox(height: 12),
          Text('Alertar em ${alert.round()}%'),
          Slider(
            value: alert,
            min: 50,
            max: 100,
            divisions: 10,
            onChanged: (value) => setState(() => alert = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _GoalInput(
              category.text.trim(),
              _number(limit.text)!,
              alert.round(),
            ),
          );
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

double? _number(String? value) =>
    double.tryParse((value ?? '').replaceAll('.', '').replaceAll(',', '.'));
