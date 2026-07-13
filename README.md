# Meu Financeiro

Aplicativo Flutter offline para controle financeiro pessoal. Os dados são
armazenados localmente em SQLite e não dependem de conexão com a internet.

## Funcionalidades

- receitas e despesas por competência;
- compras parceladas com distribuição exata dos centavos;
- pagamentos pagos, pendentes e atrasados;
- atualização automática de vencimentos em atraso;
- metas mensais por categoria e alertas de limite;
- saldo atual, saldo projetado e score financeiro;
- navegação mensal entre lançamentos e indicadores.
- edição de lançamentos e exclusão individual ou de todo o parcelamento;
- fechamento mensal com proteção contra alterações e opção de reabertura.
- contas fixas recorrentes, com data final opcional e recuperação automática de
  meses não gerados;
- compras no cartão lançadas no mês seguinte, com vencimento configurável;
- limites mensais com alertas locais no celular;
- configurações para cartão, notificações e ativação de recorrências.
- relatórios consolidados por período com exportação em PDF e CSV;
- dashboard Purple Light com evolução, score e distribuição de despesas;
- ícone Android personalizado em formatos tradicional e adaptativo.
- atalhos do dashboard para listas filtradas e detalhes dos lançamentos;
- divisão de despesas entre pessoas, contabilizando somente a parte pessoal.
- lembretes locais às 9h no dia do vencimento de contas pendentes;
- preparação dos próximos 12 meses de contas fixas para manter os avisos ativos.
- edição completa de despesas e gerenciamento das regras recorrentes;
- importação dos relatórios CSV exportados pelo próprio aplicativo;
- detecção de duplicados durante a restauração por CSV.

## Executar

```sh
flutter pub get
flutter run
```

## Validar

```sh
flutter analyze
flutter test
```

O aplicativo usa o banco `assistente_financeiro.db`, criado na área privada do
Android.

## APKs

- `build/app/outputs/flutter-apk/app-debug.apk`: testes e diagnóstico;
- `build/app/outputs/flutter-apk/app-release.apk`: versão otimizada para
  homologação.

No Android 13 ou superior, o sistema solicita autorização quando as notificações
de limites e vencimentos são ativadas pela primeira vez nas Configurações do aplicativo.
