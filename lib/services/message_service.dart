class MessageService {
  MessageService._();

  static final MessageService instance = MessageService._();

  Map<String, dynamic> createAckPacket({
    required String messageId,
    required String deviceId,
  }) {
    return {'type': 'ack', 'messageId': messageId, 'deviceId': deviceId};
  }
}
