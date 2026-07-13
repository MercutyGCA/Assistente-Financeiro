import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/financial_models.dart';

class TransactionForm extends StatefulWidget {
  const TransactionForm({super.key, this.transaction});

  final FinancialTransaction? transaction;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final formKey = GlobalKey<FormState>();
  final category = TextEditingController();
  final description = TextEditingController();
  final place = TextEditingController();
  final amount = TextEditingController();
  final installments = TextEditingController(text: '1');
  final sharedPeople = TextEditingController(text: '2');
  TransactionType type = TransactionType.despesa;
  PaymentMethod method = PaymentMethod.pix;
  TransactionStatus status = TransactionStatus.pago;
  bool recurring = false;
  bool splitExpense = false;
  bool remindOnDueDate = false;
  DateTime purchaseDate = DateTime.now();
  DateTime dueDate = DateTime.now();
  DateTime? recurringUntil;

  bool get editing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final current = widget.transaction;
    if (current == null) return;
    type = current.type;
    method = current.paymentMethod;
    status = current.status;
    recurring = current.recurring;
    category.text = current.category;
    description.text = current.description;
    place.text = current.place;
    amount.text =
        (current.installmentCount == 1
                ? current.totalAmount
                : current.installmentAmount)
            .toStringAsFixed(2)
            .replaceAll('.', ',');
    installments.text = current.installmentCount.toString();
    sharedPeople.text = current.sharedPeople.toString();
    splitExpense = current.sharedPeople > 1;
    purchaseDate = current.purchaseDate;
    dueDate = current.dueDate;
  }

  @override
  void dispose() {
    category.dispose();
    description.dispose();
    place.dispose();
    amount.dispose();
    installments.dispose();
    sharedPeople.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar lançamento' : 'Novo lançamento'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [TextButton(onPressed: _save, child: const Text('Salvar'))],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.despesa,
                  label: Text('Despesa'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: TransactionType.receita,
                  label: Text('Receita'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {type},
              onSelectionChanged: (value) => setState(() {
                type = value.first;
                if (type == TransactionType.receita) {
                  splitExpense = false;
                  remindOnDueDate = false;
                  sharedPeople.text = '2';
                }
              }),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descrição'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: category,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Categoria'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: place,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Local (opcional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor total',
                prefixText: 'R\$ ',
              ),
              validator: (value) => _parse(value) == null || _parse(value)! <= 0
                  ? 'Informe um valor válido'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            if (type == TransactionType.despesa &&
                (!editing || widget.transaction!.installmentCount == 1)) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dividir conta'),
                subtitle: const Text(
                  'Considerar somente a sua parte nos cálculos',
                ),
                value: splitExpense,
                onChanged: (value) => setState(() {
                  splitExpense = value;
                  if (!value) sharedPeople.text = '2';
                }),
              ),
              if (splitExpense) ...[
                TextFormField(
                  controller: sharedPeople,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade total de pessoas',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (!splitExpense) return null;
                    final people = int.tryParse(value ?? '');
                    return people == null || people < 2 || people > 100
                        ? 'Use um valor entre 2 e 100'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                _PersonalSharePreview(
                  total: _parse(amount.text),
                  people: int.tryParse(sharedPeople.text),
                ),
              ],
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: method,
              decoration: const InputDecoration(
                labelText: 'Forma de pagamento',
              ),
              items: PaymentMethod.values
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_paymentLabel(item)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                method = value!;
                if (method != PaymentMethod.credito) installments.text = '1';
              }),
            ),
            if (editing && type == TransactionType.despesa) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<TransactionStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: TransactionStatus.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(_statusLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => status = value!),
              ),
            ],
            if (method == PaymentMethod.credito && !editing && !recurring) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: installments,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Número de parcelas',
                ),
                validator: (value) {
                  final count = int.tryParse(value ?? '');
                  return count == null || count < 1 || count > 120
                      ? 'Use um valor entre 1 e 120'
                      : null;
                },
              ),
            ],
            const SizedBox(height: 12),
            if (!editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conta fixa recorrente'),
                subtitle: const Text(
                  'Gerar este lançamento automaticamente todos os meses',
                ),
                value: recurring,
                onChanged: (value) => setState(() {
                  recurring = value;
                  if (value) installments.text = '1';
                }),
              ),
            if (method == PaymentMethod.credito && !editing)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'A primeira cobrança será lançada no próximo mês, conforme as configurações do cartão.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (recurring && !editing) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Repetir até (opcional)',
                  prefixIcon: Icon(Icons.event_busy_outlined),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickRecurringUntil,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            recurringUntil == null
                                ? 'Sem data final'
                                : DateFormat('MM/yyyy').format(recurringUntil!),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: recurringUntil == null
                          ? 'Escolher data final'
                          : 'Remover data final',
                      onPressed: recurringUntil == null
                          ? _pickRecurringUntil
                          : () => setState(() => recurringUntil = null),
                      icon: Icon(
                        recurringUntil == null
                            ? Icons.calendar_month
                            : Icons.clear,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (type == TransactionType.despesa &&
                !editing &&
                method != PaymentMethod.credito &&
                !recurring)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notification_add_outlined),
                title: const Text('Lembrar no vencimento'),
                subtitle: const Text(
                  'Manter como pendente e avisar no dia informado',
                ),
                value: remindOnDueDate,
                onChanged: (value) => setState(() => remindOnDueDate = value),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Data da compra',
                    date: purchaseDate,
                    onTap: () => _pickDate(true),
                  ),
                ),
                if (method != PaymentMethod.credito || editing) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Vencimento',
                      date: dueDate,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool purchase) async {
    final current = purchase ? purchaseDate : dueDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (purchase) {
        purchaseDate = selected;
      } else {
        dueDate = selected;
      }
    });
  }

  Future<void> _pickRecurringUntil() async {
    final firstMonth = DateTime(
      purchaseDate.year,
      purchaseDate.month + (method == PaymentMethod.credito ? 1 : 0),
      1,
    );
    final selected = await showDatePicker(
      context: context,
      initialDate: recurringUntil ?? firstMonth,
      firstDate: firstMonth,
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Último mês da conta fixa',
    );
    if (selected == null) return;
    setState(() => recurringUntil = selected);
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    if (editing) {
      Navigator.pop(
        context,
        TransactionUpdate(
          type: type,
          paymentMethod: method,
          category: category.text,
          description: description.text,
          place: place.text,
          amount: _parse(amount.text)!,
          purchaseDate: purchaseDate,
          dueDate: dueDate,
          status: type == TransactionType.receita
              ? TransactionStatus.pago
              : status,
          sharedPeople:
              widget.transaction!.installmentCount == 1 && splitExpense
              ? int.parse(sharedPeople.text)
              : widget.transaction!.sharedPeople,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      TransactionDraft(
        type: type,
        paymentMethod: method,
        category: category.text,
        description: description.text,
        place: place.text,
        amount: _parse(amount.text)!,
        purchaseDate: purchaseDate,
        dueDate: dueDate,
        installments: method == PaymentMethod.credito
            ? int.parse(installments.text)
            : 1,
        recurring: recurring,
        recurringUntil: recurringUntil,
        sharedPeople: splitExpense ? int.parse(sharedPeople.text) : 1,
        remindOnDueDate: remindOnDueDate,
      ),
    );
  }
}

String _statusLabel(TransactionStatus status) => switch (status) {
  TransactionStatus.pago => 'Pago',
  TransactionStatus.pendente => 'Pendente',
  TransactionStatus.atrasado => 'Atrasado',
};

class _PersonalSharePreview extends StatelessWidget {
  const _PersonalSharePreview({required this.total, required this.people});
  final double? total;
  final int? people;

  @override
  Widget build(BuildContext context) {
    final valid = total != null && total! > 0 && people != null && people! > 1;
    final share = valid ? total! / people! : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EAFE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE2D4FF),
            child: Icon(Icons.person_outline, color: Color(0xFF6D28D9)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Sua parte estimada',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(share),
            style: const TextStyle(
              color: Color(0xFF6D28D9),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(DateFormat('dd/MM/yyyy').format(date)),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Campo obrigatório' : null;
double? _parse(String? value) =>
    double.tryParse((value ?? '').replaceAll('.', '').replaceAll(',', '.'));

String _paymentLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.pix => 'Pix',
  PaymentMethod.debito => 'Débito',
  PaymentMethod.credito => 'Crédito',
};
