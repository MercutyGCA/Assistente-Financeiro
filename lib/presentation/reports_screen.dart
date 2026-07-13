import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/finance_controller.dart';
import '../domain/financial_models.dart';

final _reportCurrency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _reportMonth = DateFormat('MMM/yyyy', 'pt_BR');

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.controller});

  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final report = controller.report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        _PeriodCard(controller: controller),
        const SizedBox(height: 16),
        if (controller.reportLoading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (report == null)
          const _ReportEmpty()
        else ...[
          _ReportSummary(report: report),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Evolução mensal', icon: Icons.show_chart),
          const SizedBox(height: 10),
          _MonthlyEvolution(report: report),
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Despesas por categoria',
            icon: Icons.donut_large,
          ),
          const SizedBox(height: 10),
          _CategoryBreakdown(report: report),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Exportar relatório', icon: Icons.ios_share),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _export(context, controller.exportReportPdf),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Compartilhar PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _export(context, controller.exportReportCsv),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Compartilhar CSV'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível exportar: $error')),
        );
      }
    }
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.controller});
  final FinanceController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Período do relatório',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MonthButton(
                  label: 'De',
                  date: controller.reportStart,
                  onTap: () => _pick(context, true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 18),
              ),
              Expanded(
                child: _MonthButton(
                  label: 'Até',
                  date: controller.reportEnd,
                  onTap: () => _pick(context, false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.reportLoading
                  ? null
                  : () => controller.loadReport(),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Gerar relatório'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _pick(BuildContext context, bool start) async {
    final current = start ? controller.reportStart : controller.reportEnd;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Mês inicial' : 'Mês final',
    );
    if (selected == null) return;
    if (start) {
      await controller.loadReport(start: selected);
    } else {
      await controller.loadReport(end: selected);
    }
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.date,
    required this.onTap,
  });
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          _capitalize(_reportMonth.format(date)),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report});
  final FinancialReport report;

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    childAspectRatio: 1.55,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: [
      _ReportMetric(
        'Receitas',
        report.income,
        Icons.south_west,
        const Color(0xFF0F9D72),
      ),
      _ReportMetric(
        'Despesas',
        report.expenses,
        Icons.north_east,
        const Color(0xFFE05252),
      ),
      _ReportMetric(
        'Saldo',
        report.balance,
        Icons.account_balance_wallet,
        const Color(0xFF7C3AED),
      ),
      _ReportMetric(
        'Em atraso',
        report.overdue,
        Icons.warning_amber,
        const Color(0xFFF59E0B),
      ),
    ],
  );
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric(this.label, this.value, this.icon, this.color);
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 18, color: color),
          ),
          Text(label),
          Text(
            _reportCurrency.format(value),
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    ),
  );
}

class _MonthlyEvolution extends StatelessWidget {
  const _MonthlyEvolution({required this.report});
  final FinancialReport report;

  @override
  Widget build(BuildContext context) {
    if (report.months.isEmpty) return const _ReportEmpty();
    final maxValue = report.months.fold<double>(
      1,
      (max, month) =>
          [max, month.income, month.expenses].reduce((a, b) => a > b ? a : b),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: report.months.map((month) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(width: 58, child: Text(_period(month.competence))),
                  Expanded(
                    child: Column(
                      children: [
                        _Bar(
                          value: month.income / maxValue,
                          color: const Color(0xFF0F9D72),
                        ),
                        const SizedBox(height: 5),
                        _Bar(
                          value: month.expenses / maxValue,
                          color: const Color(0xFFE05252),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 78,
                    child: Text(
                      _reportCurrency.format(month.balance),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1),
      minHeight: 8,
      color: color,
      backgroundColor: color.withValues(alpha: .1),
    ),
  );
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.report});
  final FinancialReport report;

  @override
  Widget build(BuildContext context) {
    if (report.categories.isEmpty) return const _ReportEmpty();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: report.categories.take(8).map((category) {
            final progress = report.expenses <= 0
                ? 0.0
                : category.amount / report.expenses;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(category.category)),
                      Text(
                        _reportCurrency.format(category.amount),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Bar(
                    value: progress,
                    color: Theme.of(context).colorScheme.primary,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          const Text('Nenhum lançamento encontrado neste período.'),
        ],
      ),
    ),
  );
}

String _period(String competence) {
  final parts = competence.split('-');
  return '${parts[1]}/${parts[0]}';
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
