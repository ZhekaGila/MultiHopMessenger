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

  Future<bool> insertMessage(Message message) async {
    final db = await database;
    final rowId = await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return rowId != 0;
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

  Future<List<Message>> getMessagesForReceiver(String receiverId) async {
    final db = await database;

    final maps = await db.query(
      'messages',
      where: 'receiver_id = ? AND status = ?',
      whereArgs: [receiverId, 'pending'],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => Message.fromMap(map)).toList();
  }

  Future<List<Message>> getConversation(
    String localDeviceId,
    String peerDeviceId,
  ) async {
    final db = await database;

    final rows = await db.query(
      'messages',
      where: '''
        (sender_id = ? AND receiver_id = ?)
        OR
        (sender_id = ? AND receiver_id = ?)
      ''',
      whereArgs: [localDeviceId, peerDeviceId, peerDeviceId, localDeviceId],
      orderBy: 'created_at ASC',
    );

    return rows.map(Message.fromMap).toList();
  }

  Future<List<String>> getConversationPeerIds(String localDeviceId) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT
        CASE
          WHEN sender_id = ? THEN receiver_id
          ELSE sender_id
        END AS peer_id
      FROM messages
      WHERE sender_id = ? OR receiver_id = ?
      ''',
      [localDeviceId, localDeviceId, localDeviceId],
    );

    return rows
        .map((row) => row['peer_id'] as String)
        .where((id) => id.isNotEmpty && id != localDeviceId)
        .toList();
  }

  Future<Message?> getLastConversationMessage(
    String localDeviceId,
    String peerDeviceId,
  ) async {
    final db = await database;

    final rows = await db.query(
      'messages',
      where: '''
        (sender_id = ? AND receiver_id = ?)
        OR
        (sender_id = ? AND receiver_id = ?)
      ''',
      whereArgs: [localDeviceId, peerDeviceId, peerDeviceId, localDeviceId],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Message.fromMap(rows.first);
  }

  Future<Message?> getMessageById(String messageId) async {
    final db = await database;

    final maps = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (maps.isEmpty) {
      return null;
    }

    return Message.fromMap(maps.first);
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
