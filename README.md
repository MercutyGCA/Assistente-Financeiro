
## Tecnologias utilizadas

- Flutter e Dart;
- SQLite com `sqflite`;
- `flutter_local_notifications` para alertas locais;
- `timezone` para agendamento no fuso de São Paulo;
- `pdf` para geração de relatórios;
- `share_plus` para compartilhamento de arquivos;
- `file_picker` para selecionar arquivos CSV;
- Material Design 3 com tema Purple Light.

## Estrutura do projeto

```text
lib/
├── application/   # Controladores e estado da aplicação
├── data/          # Banco SQLite e repositórios
├── domain/        # Modelos e regras financeiras
├── presentation/  # Telas e componentes visuais
├── services/      # Notificações, relatórios e importação CSV
└── main.dart       # Inicialização e tema do aplicativo

test/              # Testes automatizados
android/           # Configuração da aplicação Android
assets/            # Ícone e demais recursos visuais
```

## Requisitos

- Flutter instalado e disponível no terminal;
- Dart SDK `>=3.11.4 <4.0.0`;
- Android SDK configurado;
- aparelho Android ou emulador para execução.

Para verificar o ambiente:

```powershell
flutter doctor
```

## Instalação e execução

Clone ou abra o projeto e execute, na pasta raiz:

```powershell
flutter pub get
flutter run
```

## Validação

Execute a análise estática e os testes automatizados:

```powershell
flutter analyze
flutter test
```

## Geração dos APKs

APK de desenvolvimento:

```powershell
flutter build apk --debug
```

APK otimizado:

```powershell
flutter build apk --release
```

Os arquivos são gerados em:

```text
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```

## Armazenamento local

O banco `assistente_financeiro.db` é criado na área privada do aplicativo no Android. Os dados permanecem somente no aparelho e podem ser removidos se o aplicativo for desinstalado ou se os dados do app forem apagados nas configurações do sistema.

## Identificação Android

- nome exibido: **Meu Financeiro**;
- application ID: `br.com.assistentefinanceiro.assistente_financeiro`;
- plataforma atual: Android.

## Histórico de versões

Consulte o arquivo [CHANGELOG.md](CHANGELOG.md) para ver as alterações de cada versão.

## Uso

Projeto destinado inicialmente a uso pessoal. Os dados e relatórios produzidos pelo aplicativo são apenas informativos e não substituem orientação contábil ou financeira profissional.
