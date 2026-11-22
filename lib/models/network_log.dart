class NetworkLog {
  final int? id;
  final DateTime timestamp;
  final String eventType;
  final String? messageId;
  final String deviceId;
  final String? peerId;
  final int? hopCount;
  final String? details;

  const NetworkLog({
    this.id,
    required this.timestamp,
    required this.eventType,
    this.messageId,
    required this.deviceId,
    this.peerId,
    this.hopCount,
    this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'event_type': eventType,
      'message_id': messageId,
      'device_id': deviceId,
      'peer_id': peerId,
      'hop_count': hopCount,
      'details': details,
    };
  }

  factory NetworkLog.fromMap(Map<String, dynamic> map) {
    return NetworkLog(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      eventType: map['event_type'] as String,
      messageId: map['message_id'] as String?,
      deviceId: map['device_id'] as String,
      peerId: map['peer_id'] as String?,
      hopCount: map['hop_count'] as int?,
      details: map['details'] as String?,
    );
  }
}
