import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/financial_models.dart';

class RecurringRuleForm extends StatefulWidget {
  const RecurringRuleForm({super.key, required this.rule});
  final RecurringRule rule;

  @override
  State<RecurringRuleForm> createState() => _RecurringRuleFormState();
}

class _RecurringRuleFormState extends State<RecurringRuleForm> {
  final key = GlobalKey<FormState>();
  late final TextEditingController description;
  late final TextEditingController category;
  late final TextEditingController place;
  late final TextEditingController amount;
  late final TextEditingController people;
  late final TextEditingController dueDay;
  late TransactionType type;
  late PaymentMethod method;
  DateTime? end;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    description = TextEditingController(text: rule.description);
    category = TextEditingController(text: rule.category);
    place = TextEditingController(text: rule.place);
    amount = TextEditingController(
      text: rule.amount.toStringAsFixed(2).replaceAll('.', ','),
    );
    people = TextEditingController(text: '${rule.sharedPeople}');
    dueDay = TextEditingController(text: '${rule.dueDay}');
    type = rule.type;
    method = rule.paymentMethod;
    if (rule.endCompetence != null) {
      final parts = rule.endCompetence!.split('-');
      end = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    }
  }

  @override
  void dispose() {
    description.dispose();
    category.dispose();
    place.dispose();
    amount.dispose();
    people.dispose();
    dueDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Editar conta recorrente'),
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      actions: [TextButton(onPressed: _save, child: const Text('Salvar'))],
    ),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(
                value: TransactionType.despesa,
                label: Text('Despesa'),
              ),
              ButtonSegment(
                value: TransactionType.receita,
                label: Text('Receita'),
              ),
            ],
            selected: {type},
            onSelectionChanged: (value) => setState(() {
              type = value.first;
              if (type == TransactionType.receita) people.text = '1';
            }),
          ),
          const SizedBox(height: 14),
          _field(description, 'Descrição'),
          const SizedBox(height: 12),
          _field(category, 'Categoria'),
          const SizedBox(height: 12),
          _field(place, 'Local (opcional)', required: false),
          const SizedBox(height: 12),
          TextFormField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor total',
              prefixText: 'R\$ ',
            ),
            validator: (value) => _number(value) == null || _number(value)! <= 0
                ? 'Informe um valor válido'
                : null,
          ),
          if (type == TransactionType.despesa) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: people,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade de pessoas',
              ),
              validator: (value) {
                final count = int.tryParse(value ?? '');
                return count == null || count < 1 || count > 100
                    ? 'Use um valor entre 1 e 100'
                    : null;
              },
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: PaymentMethod.values
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(_payment(item)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => method = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: dueDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Dia do vencimento'),
            validator: (value) {
              final day = int.tryParse(value ?? '');
              return day == null || day < 1 || day > 31
                  ? 'Use um dia entre 1 e 31'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Repetir até'),
            subtitle: Text(
              end == null
                  ? 'Sem data final'
                  : DateFormat('MM/yyyy').format(end!),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (end != null)
                  IconButton(
                    onPressed: () => setState(() => end = null),
                    icon: const Icon(Icons.clear),
                  ),
                IconButton(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.calendar_month),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.sync),
              title: Text('Alteração em série'),
              subtitle: Text(
                'As cobranças pendentes deste mês em diante serão atualizadas.',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
  }) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(labelText: label),
    validator: required
        ? (value) =>
              value == null || value.trim().isEmpty ? 'Campo obrigatório' : null
        : null,
  );

  Future<void> _pickEnd() async {
    final parts = widget.rule.startCompetence.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final selected = await showDatePicker(
      context: context,
      initialDate: end ?? start,
      firstDate: start,
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Último mês da conta fixa',
    );
    if (selected != null) setState(() => end = selected);
  }

  void _save() {
    if (!key.currentState!.validate()) return;
    Navigator.pop(
      context,
      RecurringRuleUpdate(
        type: type,
        paymentMethod: method,
        category: category.text,
        description: description.text,
        place: place.text,
        amount: _number(amount.text)!,
        sharedPeople: type == TransactionType.receita
            ? 1
            : int.parse(people.text),
        dueDay: int.parse(dueDay.text),
        endCompetence: end == null ? null : competenceOf(end!),
      ),
    );
  }

  double? _number(String? value) =>
      double.tryParse((value ?? '').replaceAll('.', '').replaceAll(',', '.'));
}

String _payment(PaymentMethod method) => switch (method) {
  PaymentMethod.pix => 'PIX',
  PaymentMethod.debito => 'Débito',
  PaymentMethod.credito => 'Crédito',
};
