import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/message.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'multihop_messenger.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL,
            hop_count INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_created_at
          ON messages(created_at)
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_status
          ON messages(status)
        ''');
      },
    );

    return _database!;
  }

  Future<void> insertMessage(Message message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Message>> getAllMessages() async {
    final db = await database;
    final rows = await db.query('messages', orderBy: 'created_at ASC');
    return rows.map(Message.fromMap).toList();
  }

  Future<void> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Message>> getPendingMessages() async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    return rows.map(Message.fromMap).toList();
  }

  Future<void> migrateLegacySenderId(String deviceId) async {
    final db = await database;
    await db.update(
      'messages',
      {'sender_id': deviceId},
      where: 'sender_id = ?',
      whereArgs: ['phone_a'],
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
