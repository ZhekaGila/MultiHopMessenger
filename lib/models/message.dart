import 'package:uuid/uuid.dart';

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime createdAt;
  final String status;
  final int hopCount;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    required this.status,
    required this.hopCount,
  });

  factory Message.create({
    required String senderId,
    required String receiverId,
    required String text,
  }) {
    return Message(
      id: Uuid().v4(),
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      createdAt: DateTime.now().toUtc(),
      status: 'pending',
      hopCount: 0,
    );
  }

  Map<String,Object?> toMap(){
    return{
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'text': text,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'hop_count': hopCount,
    };
  }

  factory Message.fromMap(Map<String, Object?> map){
    return Message(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      text: map['text'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String,
      hopCount: map['hop_count'] as int,
    );
  }

  Message copyWith({
    String? status,
    int? hopCount,
  }){
    return Message(
      id:id,
      senderId: senderId,
      receiverId: receiverId,
      text:text,
      createdAt: createdAt,
      status: status ?? this.status,
      hopCount: hopCount ?? this.hopCount,
    );
  }
}