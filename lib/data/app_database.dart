import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  AppDatabase.forTesting(Database database) : _database = database;

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'assistente_financeiro.db');
    _database = await openDatabase(
      path,
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createClosuresTable(db);
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN recurring_rule_id TEXT',
          );
          await _createRecurringAndSettings(db);
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN shared_people INTEGER NOT NULL DEFAULT 1',
          );
        } else if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN shared_people INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE recurring_rules ADD COLUMN shared_people INTEGER NOT NULL DEFAULT 1',
          );
        }
      },
    );
    return _database!;
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        installment_group TEXT,
        recurring_rule_id TEXT,
        type TEXT NOT NULL CHECK(type IN ('receita', 'despesa')),
        payment_method TEXT NOT NULL CHECK(payment_method IN ('pix', 'debito', 'credito')),
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        place TEXT NOT NULL DEFAULT '',
        total_amount REAL NOT NULL CHECK(total_amount > 0),
        installment_amount REAL NOT NULL CHECK(installment_amount > 0),
        installment_number INTEGER NOT NULL DEFAULT 1,
        installment_count INTEGER NOT NULL DEFAULT 1,
        shared_people INTEGER NOT NULL DEFAULT 1,
        recurring INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL CHECK(status IN ('pago', 'pendente', 'atrasado')),
        purchase_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        competence TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL COLLATE NOCASE UNIQUE,
        amount_limit REAL NOT NULL CHECK(amount_limit > 0),
        alert_percentage INTEGER NOT NULL DEFAULT 80
          CHECK(alert_percentage BETWEEN 1 AND 100)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_transactions_competence ON transactions(competence)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_status ON transactions(status)',
    );
    await _createClosuresTable(db);
    await _createRecurringAndSettings(db);
  }

  static Future<void> _createClosuresTable(Database db) async {
    await db.execute('''
      CREATE TABLE monthly_closures (
        competence TEXT PRIMARY KEY,
        closed_at TEXT NOT NULL,
        income REAL NOT NULL,
        paid REAL NOT NULL,
        pending REAL NOT NULL,
        overdue REAL NOT NULL
      )
    ''');
  }

  static Future<void> _createRecurringAndSettings(Database db) async {
    await db.execute('''
      CREATE TABLE recurring_rules (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK(type IN ('receita', 'despesa')),
        payment_method TEXT NOT NULL CHECK(payment_method IN ('pix', 'debito', 'credito')),
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        place TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL CHECK(amount > 0),
        shared_people INTEGER NOT NULL DEFAULT 1,
        due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
        start_competence TEXT NOT NULL,
        end_competence TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_recurring_instance
      ON transactions(recurring_rule_id, competence)
      WHERE recurring_rule_id IS NOT NULL
    ''');
    await db.execute('''
      CREATE TABLE settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE goal_alert_events (
        goal_id TEXT NOT NULL,
        competence TEXT NOT NULL,
        alert_level TEXT NOT NULL,
        notified_at TEXT NOT NULL,
        PRIMARY KEY(goal_id, competence, alert_level)
      )
    ''');
    await db.insert('settings', {
      'setting_key': 'credit_due_day',
      'setting_value': '10',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('settings', {
      'setting_key': 'credit_to_next_month',
      'setting_value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('settings', {
      'setting_key': 'notifications_enabled',
      'setting_value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
