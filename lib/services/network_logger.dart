import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/network_log.dart';

class NetworkLogger {
  NetworkLogger._();

  static final NetworkLogger instance = NetworkLogger._();

  Future<void> log({
    required String eventType,
    required String deviceId,
    String? messageId,
    String? peerId,
    int? hopCount,
    String? details,
  }) async {
    try {
      final entry = NetworkLog(
        timestamp: DateTime.now(),
        eventType: eventType,
        deviceId: deviceId,
        messageId: messageId,
        peerId: peerId,
        hopCount: hopCount,
        details: details,
      );

      await DatabaseHelper.instance.insertNetworkLog(entry);

      debugPrint(
        '[NETWORK] $eventType | '
        'device=$deviceId | '
        'message=$messageId | '
        'peer=$peerId | '
        'hop=$hopCount',
      );
    } catch (error, stackTrace) {
      debugPrint('[NETWORK] Failed to save log: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
