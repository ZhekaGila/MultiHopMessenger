import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_helper.dart';
import 'models/message.dart';
import 'services/device_identity.dart';

import 'dart:convert';

void main() {
  runApp(const MultiHopApp());
}

class MultiHopApp extends StatelessWidget {
  const MultiHopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MultiHop Messenger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class BluetoothDeviceInfo {
  final String name;
  final String address;

  BluetoothDeviceInfo({required this.name, required this.address});

  factory BluetoothDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothDeviceInfo(
      name: map['name']?.toString() ?? 'Unknown device',
      address: map['address']?.toString() ?? '',
    );
  }
}

class ChatMessage {
  final String text;
  final bool isMine;
  final DateTime time;

  ChatMessage({required this.text, required this.isMine, required this.time});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const channel = MethodChannel('multihop/bluetooth');

  static const eventChannel = EventChannel('multihop/bluetooth_events');

  final messageController = TextEditingController();
  final receiverController = TextEditingController();
  final scrollController = ScrollController();

  StreamSubscription<dynamic>? eventSubscription;

  String status = 'Waiting for action...';
  String connectionStatus = 'Disconnected';

  List<BluetoothDeviceInfo> pairedDevices = [];
  List<ChatMessage> messages = [];

  bool sending = false;

  String localDeviceId = '';

  String peerDeviceId = '';

  static const int maxHopCount = 5;

  bool get isConnected => connectionStatus.startsWith('Connected:');

  @override
  void initState() {
    super.initState();

    initializeDeviceIdentity();

    eventSubscription = eventChannel.receiveBroadcastStream().listen(
      handleBluetoothEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          status = 'Event error: $error';
        });
      },
    );
  }

  Future<void> sendHello() async {
    if (!isConnected || localDeviceId.isEmpty) {
      return;
    }

    final helloPacket = {'type': 'hello', 'deviceId': localDeviceId};

    final jsonString = jsonEncode(helloPacket);

    try {
      await channel.invokeMethod<String>('sendMessage', {
        'message': jsonString,
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Hello error: $e';
      });
    }
  }

  Future<void> sendAck(String messageId) async {
    if (!isConnected || peerDeviceId.isEmpty) {
      return;
    }

    final ackPacket = {
      'type': 'ack',
      'messageId': messageId,
      'deviceId': localDeviceId,
    };

    try {
      await channel.invokeMethod<String>('sendMessage', {
        'message': jsonEncode(ackPacket),
      });

      debugPrint('ACK sent for message: $messageId');
    } catch (e) {
      debugPrint('ACK send error: $e');
    }
  }

  Future<void> saveReceivedJsonMessage(Message message) async {
    try {
      final savedMessage = message.copyWith(status: 'received');

      final inserted = await DatabaseHelper.instance.insertMessage(
        savedMessage,
      );

      await sendAck(message.id);

      if (!inserted) {
        debugPrint('Duplicate message ignored: ${message.id}');
        return;
      }

      if (!mounted) return;

      setState(() {
        messages.add(
          ChatMessage(
            text: savedMessage.text,
            isMine: false,
            time: savedMessage.createdAt,
          ),
        );
      });

      scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Receive error: $e';
      });
    }
  }

  Future<void> forwardMessagesToPeer() async {
    if (!isConnected || peerDeviceId.isEmpty) {
      return;
    }

    final pendingMessages = await DatabaseHelper.instance
        .getMessagesForReceiver(peerDeviceId);

    for (final message in pendingMessages) {
      if (!isConnected) {
        break;
      }

      if (message.senderId == localDeviceId) {
        continue;
      }

      if (message.hopCount >= maxHopCount) {
        debugPrint('Hop limit reached: ${message.id}');
        continue;
      }

      final forwardedMessage = message.copyWith(hopCount: message.hopCount + 1);

      try {
        await channel.invokeMethod<String>('sendMessage', {
          'message': forwardedMessage.toWireJson(),
        });

        debugPrint('Forwarded message ${message.id} to $peerDeviceId');
      } catch (e) {
        debugPrint('Forwarding error: $e');
        break;
      }
    }
  }

  void handleIncomingPacket(String raw) {
    try {
      final data = jsonDecode(raw);

      if (data is! Map<String, dynamic>) {
        return;
      }

      final packetType = data['type'];

      if (packetType == 'hello') {
        final receivedDeviceId = data['deviceId'];

        if (receivedDeviceId is String &&
            receivedDeviceId.isNotEmpty &&
            receivedDeviceId != localDeviceId) {
          setState(() {
            peerDeviceId = receivedDeviceId;
            status = 'Peer UUID received!';
          });

          forwardMessagesToPeer();
        }

        return;
      }

      if (packetType == 'ack') {
        final messageId = data['messageId'];
        final senderDeviceId = data['deviceId'];

        if (messageId is String && senderDeviceId is String) {
          debugPrint('ACK received for $messageId from $senderDeviceId');
        }

        return;
      }

      if (packetType == 'chat') {
        final message = Message.fromWireJson(raw);

        if (message.receiverId == localDeviceId) {
          saveReceivedJsonMessage(message);
        } else {
          saveRelayMessage(message);
        }

        return;
      }
    } catch (e) {
      setState(() {
        status = 'Invalid packet: $e';
      });
    }
  }

  void handleBluetoothEvent(dynamic event) {
    if (!mounted || event is! Map) return;

    final type = event['type']?.toString();
    final value = event['value']?.toString() ?? '';

    if (type == 'status') {
      final wasConnected = isConnected;

      setState(() {
        connectionStatus = value;

        if (!value.startsWith('Connected:')) {
          peerDeviceId = '';
        }
      });

      if (isConnected && !wasConnected) {
        sendHello();
      }
    } else if (type == 'message') {
      handleIncomingPacket(value);
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> callKotlin(String method) async {
    try {
      final result = await channel.invokeMethod<String>(method);

      if (!mounted) return;

      setState(() {
        status = result ?? 'No response';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Error: ${e.message}';
      });
    }
  }

  Future<void> loadPairedDevices() async {
    try {
      final result = await channel.invokeMethod<List<dynamic>>(
        'getPairedDevices',
      );

      if (!mounted) return;

      setState(() {
        pairedDevices = (result ?? [])
            .map(
              (item) => BluetoothDeviceInfo.fromMap(
                Map<dynamic, dynamic>.from(item as Map),
              ),
            )
            .toList();

        status = 'Found ${pairedDevices.length} paired devices';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Error: ${e.message}';
      });
    }
  }

  Future<void> connectToDevice(String address) async {
    try {
      final result = await channel.invokeMethod<String>('connectToDevice', {
        'address': address,
      });

      if (!mounted) return;

      setState(() {
        status = result ?? 'No response';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Error: ${e.message}';
      });
    }
  }

  Future<void> refreshConnectionStatus() async {
    try {
      final result = await channel.invokeMethod<String>('getConnectionStatus');

      if (!mounted) return;

      setState(() {
        connectionStatus = result ?? 'Unknown';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        connectionStatus = 'Error: ${e.message}';
      });
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    final destinationId = receiverController.text.trim().isEmpty
        ? peerDeviceId
        : receiverController.text.trim();

    if (text.isEmpty ||
        !isConnected ||
        sending ||
        localDeviceId.isEmpty ||
        peerDeviceId.isEmpty) {
      return;
    }
    setState(() {
      sending = true;
    });

    try {
      final message = Message.create(
        senderId: localDeviceId,
        receiverId: destinationId,
        text: text,
      );

      final result = await channel.invokeMethod<String>('sendMessage', {
        'message': message.toWireJson(),
      });

      if (!mounted) return;

      if (result == 'Message sent') {
        final savedMessage = message.copyWith(status: 'sent');

        await DatabaseHelper.instance.insertMessage(savedMessage);

        setState(() {
          messages.add(
            ChatMessage(text: text, isMine: true, time: DateTime.now()),
          );

          messageController.clear();
          status = 'Message sent';
        });

        scrollToBottom();
      } else {
        setState(() {
          status = result ?? 'Send failed';
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Send error: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
        });
      }
    }
  }

  Future<void> testDatabase() async {
    try {
      final message = Message.create(
        senderId: 'test_phone_a',
        receiverId: 'test_phone_b',
        text: 'Hello SQLite!',
      );

      await DatabaseHelper.instance.insertMessage(message);

      final savedMessages = await DatabaseHelper.instance.getAllMessages();

      if (!mounted) return;

      setState(() {
        status =
            'SQLite works! Saved message: '
            '${savedMessages.length}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'SQLite error: $e';
      });
    }
  }

  Future<void> loadMessagesFromDatabase() async {
    try {
      final savedMessages = await DatabaseHelper.instance.getAllMessages();
      final chatMessages = savedMessages
          .where(
            (message) =>
                message.senderId == localDeviceId ||
                message.receiverId == localDeviceId,
          )
          .toList();

      if (!mounted) return;

      setState(() {
        messages = chatMessages.map((message) {
          return ChatMessage(
            text: message.text,
            isMine: message.senderId == localDeviceId,
            time: message.createdAt,
          );
        }).toList();
      });

      scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Database error: $e';
      });
    }
  }

  Future<void> saveIncomingMessage(String text) async {
    try {
      final message = Message.create(
        senderId: 'remote_device',
        receiverId: localDeviceId,
        text: text,
      ).copyWith(status: 'received');

      await DatabaseHelper.instance.insertMessage(message);

      if (!mounted) return;

      setState(() {
        messages.add(
          ChatMessage(text: text, isMine: false, time: message.createdAt),
        );
      });

      scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Failed to save incoming message: $e';
      });
    }
  }

  Future<void> saveRelayMessage(Message message) async {
    try {
      final relayMessage = message.copyWith(status: 'pending');

      final inserted = await DatabaseHelper.instance.insertMessage(
        relayMessage,
      );

      await sendAck(message.id);

      if (inserted) {
        debugPrint('Relay message saved: ${message.id}');

        debugPrint('Destination: ${message.receiverId}');

        debugPrint('Hop count: ${message.hopCount}');
      } else {
        debugPrint('Duplicate relay message ignored: ${message.id}');
      }
    } catch (e) {
      debugPrint('Relay save error: $e');
    }
  }

  Future<void> initializeDeviceIdentity() async {
    try {
      final id = await DeviceIdentity.getOrCreateDeviceId();
      if (!mounted) return;

      setState(() {
        localDeviceId = id;
      });

      await DatabaseHelper.instance.migrateLegacySenderId(id);
      await loadMessagesFromDatabase();

      if (isConnected) {
        await sendHello();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = 'Device identity error: $e';
      });
    }
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    messageController.dispose();
    scrollController.dispose();
    receiverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MultiHop Messenger')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'My Device ID:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: receiverController,
            decoration: const InputDecoration(
              labelText: 'Destination UUID',
              hintText: 'Enter receiver device UUID',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(localDeviceId.isEmpty ? 'Loading...' : localDeviceId),
          const SizedBox(height: 8),
          const Text(
            'Connected Peer UUID:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          SelectableText(
            peerDeviceId.isEmpty ? 'Not received yet' : peerDeviceId,
          ),
          const Divider(height: 30),
          const Icon(Icons.bluetooth, size: 55, color: Colors.blue),

          const SizedBox(height: 8),

          Text(status, textAlign: TextAlign.center),

          const SizedBox(height: 12),

          ElevatedButton(
            onPressed: () => callKotlin('checkBluetooth'),
            child: const Text('Check Bluetooth'),
          ),

          ElevatedButton(
            onPressed: () => callKotlin('requestBluetoothPermission'),
            child: const Text('Request Bluetooth Permission'),
          ),

          const Divider(height: 30),

          const Text(
            'Bluetooth Server',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          ElevatedButton(
            onPressed: () => callKotlin('startServer'),
            child: const Text('Start Server'),
          ),

          ElevatedButton(
            onPressed: () => callKotlin('stopServer'),
            child: const Text('Stop Server'),
          ),

          const Divider(height: 30),

          const Text(
            'Bluetooth Client',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          ElevatedButton(
            onPressed: loadPairedDevices,
            child: const Text('Show Paired Devices'),
          ),

          for (final device in pairedDevices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.smartphone),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: () => connectToDevice(device.address),
                ),
              ),
            ),

          const Divider(height: 30),

          const Text(
            'Connection Status',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(connectionStatus, textAlign: TextAlign.center),

          ElevatedButton(
            onPressed: refreshConnectionStatus,
            child: const Text('Refresh Connection Status'),
          ),

          ElevatedButton(
            onPressed: () async {
              await callKotlin('disconnect');
              await refreshConnectionStatus();
            },
            child: const Text('Disconnect'),
          ),

          const SizedBox(height: 12),

          ElevatedButton(
            onPressed: testDatabase,
            child: const Text('Test SQLite'),
          ),

          const Divider(height: 30),

          const Text(
            'Bluetooth Chat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          Container(
            height: 260,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];

                      return Align(
                        alignment: message.isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.isMine
                                ? Colors.blue.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(message.text),
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  enabled: isConnected,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              IconButton.filled(
                onPressed: isConnected && !sending ? sendMessage : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
