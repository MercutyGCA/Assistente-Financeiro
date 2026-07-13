import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/financial_models.dart';

final _detailsCurrency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _detailsDate = DateFormat('dd/MM/yyyy');

class FilteredTransactionsScreen extends StatelessWidget {
  const FilteredTransactionsScreen({
    super.key,
    required this.filter,
    required this.transactions,
    required this.competence,
  });

  final DashboardTransactionFilter filter;
  final List<FinancialTransaction> transactions;
  final String competence;

  @override
  Widget build(BuildContext context) {
    final filtered = filterDashboardTransactions(transactions, filter);
    final total = filtered.fold<double>(
      0,
      (sum, item) => sum + item.installmentAmount,
    );
    return Scaffold(
      appBar: AppBar(title: Text(filter.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6D28D9), Color(0xFFA855F7)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.filter_alt, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _competenceLabel(competence),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '${filtered.length} ${filtered.length == 1 ? 'lançamento' : 'lançamentos'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        _detailsCurrency.format(total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const _FilteredEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _TransactionTile(
                        transaction: item,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TransactionDetailsScreen(transaction: item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction, required this.onTap});
  final FinancialTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == TransactionType.receita;
    final color = income
        ? const Color(0xFF0F9D72)
        : _statusColor(transaction.status);
    return Card(
      color: !income && transaction.status == TransactionStatus.pago
          ? const Color(0xFFE8F7EF)
          : null,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(
            income ? Icons.south_west : Icons.north_east,
            color: color,
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${transaction.category} • ${_detailsDate.format(transaction.dueDate)}\n${_statusLabel(transaction.status)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${income ? '+' : '-'}${_detailsCurrency.format(transaction.installmentAmount)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class TransactionDetailsScreen extends StatelessWidget {
  const TransactionDetailsScreen({super.key, required this.transaction});
  final FinancialTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == TransactionType.receita;
    final color = income
        ? const Color(0xFF0F9D72)
        : _statusColor(transaction.status);
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do lançamento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: income || transaction.status == TransactionStatus.pago
                    ? const [Color(0xFF087F5B), Color(0xFF20B486)]
                    : const [Color(0xFF6D28D9), Color(0xFFA855F7)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    income ? Icons.south_west : Icons.north_east,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  transaction.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${income ? '+' : '-'}${_detailsCurrency.format(transaction.installmentAmount)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.category_outlined,
                  label: 'Categoria',
                  value: transaction.category,
                ),
                _DetailRow(
                  icon: Icons.storefront_outlined,
                  label: 'Local',
                  value: transaction.place.isEmpty
                      ? 'Não informado'
                      : transaction.place,
                ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Pagamento',
                  value: _paymentLabel(transaction.paymentMethod),
                ),
                _DetailRow(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: _statusLabel(transaction.status),
                  valueColor: color,
                ),
                _DetailRow(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Data da compra',
                  value: _detailsDate.format(transaction.purchaseDate),
                ),
                _DetailRow(
                  icon: Icons.event_outlined,
                  label: 'Vencimento',
                  value: _detailsDate.format(transaction.dueDate),
                ),
                _DetailRow(
                  icon: Icons.calendar_view_month,
                  label: 'Competência',
                  value: _competenceLabel(transaction.competence),
                ),
                if (transaction.installmentCount > 1)
                  _DetailRow(
                    icon: Icons.view_carousel_outlined,
                    label: 'Parcela',
                    value:
                        '${transaction.installmentNumber} de ${transaction.installmentCount}',
                  ),
                if (transaction.sharedPeople > 1)
                  _DetailRow(
                    icon: Icons.groups_outlined,
                    label: 'Divisão da conta',
                    value: '${transaction.sharedPeople} pessoas',
                  ),
                _DetailRow(
                  icon: Icons.repeat,
                  label: 'Recorrência',
                  value: transaction.recurring
                      ? 'Conta fixa mensal'
                      : 'Não recorrente',
                  last: true,
                ),
              ],
            ),
          ),
          if (transaction.sharedPeople > 1) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFF1EAFE),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _SplitValue(
                        label: 'CONTA TOTAL',
                        value: transaction.totalAmount,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: const Color(0xFFD8C7FA),
                    ),
                    Expanded(
                      child: _SplitValue(
                        label: 'SUA PARTE',
                        value: transaction.personalShareTotal,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (transaction.installmentCount > 1) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFF1EAFE),
              child: ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Valor total da compra'),
                trailing: Text(
                  _detailsCurrency.format(transaction.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitValue extends StatelessWidget {
  const _SplitValue({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      const SizedBox(height: 4),
      Text(
        _detailsCurrency.format(value),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: highlight ? const Color(0xFF6D28D9) : null,
        ),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        trailing: SizedBox(
          width: 170,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: FontWeight.w800, color: valueColor),
          ),
        ),
      ),
      if (!last) const Divider(height: 1, indent: 56),
    ],
  );
}

class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),
          const Text(
            'Nenhum lançamento neste filtro.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

Color _statusColor(TransactionStatus status) => switch (status) {
  TransactionStatus.pago => const Color(0xFF0F9D72),
  TransactionStatus.pendente => const Color(0xFFF59E0B),
  TransactionStatus.atrasado => const Color(0xFFE05252),
};

String _statusLabel(TransactionStatus status) => switch (status) {
  TransactionStatus.pago => 'Pago',
  TransactionStatus.pendente => 'Pendente',
  TransactionStatus.atrasado => 'Em atraso',
};

String _paymentLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.pix => 'Pix',
  PaymentMethod.debito => 'Débito',
  PaymentMethod.credito => 'Crédito',
};

String _competenceLabel(String competence) {
  final parts = competence.split('-');
  return '${parts[1]}/${parts[0]}';
}
