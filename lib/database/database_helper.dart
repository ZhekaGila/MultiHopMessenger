import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/network_log.dart';
import '../models/message.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;

  static Future<void> _createNetworkLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE network_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        event_type TEXT NOT NULL,
        message_id TEXT,
        device_id TEXT NOT NULL,
        peer_id TEXT,
        hop_count INTEGER,
        details TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_network_logs_timestamp
      ON network_logs(timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_network_logs_message_id
      ON network_logs(message_id)
    ''');
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'multihop_messenger.db');

    _database = await openDatabase(
      path,
      version: 2,
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

        await _createNetworkLogsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createNetworkLogsTable(db);
        }
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

  Future<int> insertNetworkLog(NetworkLog log) async {
    final db = await database;

    return db.insert('network_logs', log.toMap());
  }

  Future<List<NetworkLog>> getNetworkLogs({
    String? eventType,
    int limit = 200,
  }) async {
    final db = await database;

    final rows = await db.query(
      'network_logs',
      where: eventType == null ? null : 'event_type = ?',
      whereArgs: eventType == null ? null : [eventType],
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );

    return rows.map(NetworkLog.fromMap).toList();
  }

  Future<int> getNetworkLogCount() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM network_logs',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<NetworkLog>> getAllNetworkLogs() async {
    final db = await database;

    final rows = await db.query(
      'network_logs',
      orderBy: 'timestamp ASC, id ASC',
    );

    return rows.map(NetworkLog.fromMap).toList();
  }

  Future<void> clearNetworkLogs() async {
    final db = await database;
    await db.delete('network_logs');
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
