import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_helper.dart';
import 'models/message.dart';
import 'services/device_identity.dart';

import 'dart:convert';

part 'widgets/devices_tab.dart';

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
  List<BluetoothDeviceInfo> discoveredDevices = [];

  List<String> connectedAddresses = [];

  bool isScanning = false;

  List<ChatMessage> messages = [];

  bool sending = false;

  int selectedTab = 0;

  List<String> conversationPeerIds = [];

  String? selectedPeerId;

  List<Message> conversationMessages = [];

  bool loadingMessages = false;

  bool loadingConversations = false;

  String localDeviceId = '';

  final Map<String, String> peerIdsByAddress = {};

  final Map<String, String> reachablePeers = {};

  static const int maxHopCount = 5;

  bool get isConnected => connectedAddresses.isNotEmpty;

  @override
  void initState() {
    super.initState();

    initializeDeviceIdentity();

    loadConnectedDevices();

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

  Future<bool> sendPacketToDevice(String address, String packet) async {
    if (!connectedAddresses.contains(address)) {
      debugPrint('Device not connected: $address');
      return false;
    }

    try {
      final result = await channel.invokeMethod<String>('sendMessageToDevice', {
        'address': address,
        'message': packet,
      });

      return result == 'Message sent';
    } on PlatformException catch (e) {
      debugPrint('Bluetooth send error: ${e.message}');
      return false;
    }
  }

  Future<void> sendPeers(String address) async {
    if (!connectedAddresses.contains(address) || localDeviceId.isEmpty) {
      return;
    }

    final peers = peerIdsByAddress.entries
        .where(
          (entry) =>
              connectedAddresses.contains(entry.key) &&
              entry.key != address &&
              entry.value.isNotEmpty,
        )
        .map((entry) => entry.value)
        .toList();

    final packet = {'type': 'peers', 'deviceId': localDeviceId, 'peers': peers};

    final success = await sendPacketToDevice(address, jsonEncode(packet));

    if (success) {
      debugPrint('PEERS sent to $address: $peers');
    } else {
      debugPrint('PEERS failed for $address');
    }
  }

  Future<void> sendHello(String address) async {
    if (!connectedAddresses.contains(address) || localDeviceId.isEmpty) {
      return;
    }

    final helloPacket = {'type': 'hello', 'deviceId': localDeviceId};

    final success = await sendPacketToDevice(address, jsonEncode(helloPacket));

    if (!success) {
      debugPrint('HELLO failed for $address');
    }
  }

  Future<void> sendAck(String messageId, String senderAddress) async {
    if (!connectedAddresses.contains(senderAddress) || localDeviceId.isEmpty) {
      return;
    }

    final ackPacket = {
      'type': 'ack',
      'messageId': messageId,
      'deviceId': localDeviceId,
    };

    final success = await sendPacketToDevice(
      senderAddress,
      jsonEncode(ackPacket),
    );

    if (success) {
      debugPrint('ACK sent for message: $messageId to $senderAddress');
    } else {
      debugPrint('ACK send failed for $messageId');
    }
  }

  Future<void> handleAck(
    String messageId,
    String senderDeviceId,
    String senderAddress,
  ) async {
    final expectedDeviceId = peerIdsByAddress[senderAddress];

    if (!connectedAddresses.contains(senderAddress) ||
        expectedDeviceId == null ||
        expectedDeviceId != senderDeviceId) {
      debugPrint('ACK rejected: unexpected sender');
      return;
    }

    final message = await DatabaseHelper.instance.getMessageById(messageId);

    if (message == null) {
      debugPrint('ACK ignored: unknown message $messageId');
      return;
    }

    if (message.status == 'delivered') {
      return;
    }

    if (message.receiverId == senderDeviceId) {
      await DatabaseHelper.instance.updateMessageStatus(messageId, 'delivered');

      debugPrint('Message delivered: $messageId');
    } else {
      await DatabaseHelper.instance.updateMessageStatus(messageId, 'forwarded');

      debugPrint('Message forwarded to relay: $messageId');
    }
  }

  Future<void> saveReceivedJsonMessage(
    Message message,
    String senderAddress,
  ) async {
    try {
      final savedMessage = message.copyWith(status: 'received');

      final inserted = await DatabaseHelper.instance.insertMessage(
        savedMessage,
      );

      await sendAck(message.id, senderAddress);

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

        if (selectedPeerId == savedMessage.senderId) {
          conversationMessages.add(savedMessage);
        }
      });

      scrollToBottom();

      await loadConversations();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Receive error: $e';
      });
    }
  }

  Future<void> forwardMessagesToPeer(String address) async {
    final destinationId = peerIdsByAddress[address];

    if (!connectedAddresses.contains(address) ||
        destinationId == null ||
        destinationId.isEmpty) {
      return;
    }

    final pendingMessages = await DatabaseHelper.instance
        .getMessagesForReceiver(destinationId);

    for (final message in pendingMessages) {
      if (!connectedAddresses.contains(address)) {
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

      final success = await sendPacketToDevice(
        address,
        forwardedMessage.toWireJson(),
      );

      if (success) {
        debugPrint('Forwarded message ${message.id} to $destinationId');
      } else {
        debugPrint('Forwarding failed: ${message.id}');
        break;
      }
    }
  }

  void handleIncomingPacket(String raw, String senderAddress) {
    try {
      final data = jsonDecode(raw);

      if (data is! Map<String, dynamic>) {
        return;
      }

      final packetType = data['type'];

      if (packetType == 'peers') {
        final senderDeviceId = data['deviceId'];
        final receivedPeers = data['peers'];

        if (!connectedAddresses.contains(senderAddress) ||
            senderDeviceId is! String ||
            peerIdsByAddress[senderAddress] != senderDeviceId ||
            receivedPeers is! List) {
          debugPrint('Invalid PEERS packet');
          return;
        }

        final peerIds = receivedPeers
            .whereType<String>()
            .where(
              (id) =>
                  id.isNotEmpty && id != localDeviceId && id != senderDeviceId,
            )
            .toSet();

        setState(() {
          reachablePeers.removeWhere(
            (deviceId, nextHopAddress) => nextHopAddress == senderAddress,
          );

          for (final peerId in peerIds) {
            if (findAddressByDeviceId(peerId) == null) {
              reachablePeers[peerId] = senderAddress;
            }
          }
        });

        debugPrint('Reachable peers via $senderAddress: $peerIds');

        return;
      }

      if (packetType == 'hello') {
        final receivedDeviceId = data['deviceId'];

        if (receivedDeviceId is String &&
            receivedDeviceId.isNotEmpty &&
            receivedDeviceId != localDeviceId) {
          setState(() {
            peerIdsByAddress[senderAddress] = receivedDeviceId;
            status = 'Peer UUID received from $senderAddress';
          });

          forwardMessagesToPeer(senderAddress);

          sendPeers(senderAddress);

          for (final address in connectedAddresses) {
            if (address != senderAddress) {
              sendPeers(address);
            }
          }
        }

        return;
      }

      if (packetType == 'ack') {
        final messageId = data['messageId'];
        final senderDeviceId = data['deviceId'];

        if (messageId is String && senderDeviceId is String) {
          handleAck(messageId, senderDeviceId, senderAddress);
        }

        return;
      }

      if (packetType == 'chat') {
        final message = Message.fromWireJson(raw);

        if (message.receiverId == localDeviceId) {
          saveReceivedJsonMessage(message, senderAddress);
        } else {
          saveRelayMessage(message, senderAddress);
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

    if (type == 'deviceFound') {
      final rawDevice = event['value'];

      if (rawDevice is Map) {
        final device = BluetoothDeviceInfo.fromMap(rawDevice);

        if (device.address.isNotEmpty) {
          setState(() {
            discoveredDevices.removeWhere(
              (existing) => existing.address == device.address,
            );

            discoveredDevices.add(device);
          });
        }
      }

      return;
    }

    if (type == 'discoveryFinished') {
      setState(() {
        isScanning = false;
        status = 'Discovery finished';
      });

      return;
    }

    if (type == 'peerConnected') {
      final address = event['address']?.toString() ?? '';

      if (address.isNotEmpty) {
        loadConnectedDevices().then((_) {
          if (mounted && connectedAddresses.contains(address)) {
            sendHello(address);
          }
        });
      }

      return;
    }

    if (type == 'peerDisconnected') {
      final address = event['address']?.toString() ?? '';

      if (address.isNotEmpty) {
        setState(() {
          peerIdsByAddress.remove(address);

          reachablePeers.removeWhere(
            (deviceId, nextHopAddress) => nextHopAddress == address,
          );
        });
      }

      loadConnectedDevices();
      return;
    }

    if (type == 'peersChanged') {
      loadConnectedDevices();
      return;
    }

    if (type == 'status') {
      setState(() {
        connectionStatus = value;
      });
    } else if (type == 'message') {
      final senderAddress = event['address']?.toString() ?? '';

      if (senderAddress.isNotEmpty) {
        handleIncomingPacket(value, senderAddress);
      }
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

  Future<void> scanNearbyDevices() async {
    if (isScanning) return;

    setState(() {
      discoveredDevices.clear();
      isScanning = true;
      status = 'Scanning nearby devices...';
    });

    try {
      final result = await channel.invokeMethod<String>('startDiscovery');

      if (!mounted) return;

      setState(() {
        status = result ?? 'Unknown discovery status';

        if (result != 'Discovery started') {
          isScanning = false;
        }
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        isScanning = false;
        status = 'Discovery error: ${e.message}';
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

  Future<void> loadConnectedDevices() async {
    try {
      final result = await channel.invokeMethod<List<dynamic>>(
        'getConnectedDevices',
      );

      if (!mounted) return;

      setState(() {
        connectedAddresses = (result ?? [])
            .map((item) => Map<dynamic, dynamic>.from(item as Map))
            .map((item) => item['address']?.toString() ?? '')
            .where((address) => address.isNotEmpty)
            .toList();

        connectionStatus = connectedAddresses.isEmpty
            ? 'Disconnected'
            : 'Connected (${connectedAddresses.length})';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Connection list error: ${e.message}';
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

  Future<void> disconnectFromDevice(String address) async {
    try {
      final result = await channel.invokeMethod<String>('disconnectDevice', {
        'address': address,
      });

      if (!mounted) return;

      setState(() {
        status = result ?? 'Device disconnected';
      });

      await loadConnectedDevices();
    } on PlatformException catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Disconnect error: ${e.message}';
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

  String? findAddressByDeviceId(String deviceId) {
    for (final entry in peerIdsByAddress.entries) {
      if (entry.value == deviceId && connectedAddresses.contains(entry.key)) {
        return entry.key;
      }
    }

    return null;
  }

  String? findNextHopAddress(String destinationId) {
    final directAddress = findAddressByDeviceId(destinationId);

    if (directAddress != null) {
      return directAddress;
    }

    final relayAddress = reachablePeers[destinationId];

    if (relayAddress != null && connectedAddresses.contains(relayAddress)) {
      return relayAddress;
    }

    return null;
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    final enteredReceiverId = receiverController.text.trim();

    final destinationId = enteredReceiverId.isNotEmpty
        ? enteredReceiverId
        : connectedAddresses.length == 1
        ? (peerIdsByAddress[connectedAddresses.first] ?? '')
        : '';

    final destinationAddress = findAddressByDeviceId(destinationId);

    if (text.isEmpty ||
        !isConnected ||
        sending ||
        localDeviceId.isEmpty ||
        destinationId.isEmpty) {
      return;
    }

    if (destinationAddress == null) {
      setState(() {
        status = 'Destination device is not directly connected';
      });
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

      final result = await channel.invokeMethod<String>('sendMessageToDevice', {
        'address': destinationAddress,
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

  Future<void> loadConversations() async {
    if (localDeviceId.isEmpty) return;

    setState(() {
      loadingConversations = true;
    });

    try {
      final peerIds = await DatabaseHelper.instance.getConversationPeerIds(
        localDeviceId,
      );

      if (!mounted) return;

      setState(() {
        conversationPeerIds = peerIds;
        loadingConversations = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingConversations = false;
        status = 'Failed to load conversations: $e';
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

  Future<void> saveRelayMessage(Message message, String senderAddress) async {
    try {
      if (message.hopCount >= maxHopCount) {
        debugPrint('Hop limit reached: ${message.id}');
        return;
      }

      final relayMessage = message.copyWith(status: 'pending');

      final inserted = await DatabaseHelper.instance.insertMessage(
        relayMessage,
      );

      await sendAck(message.id, senderAddress);

      if (!inserted) {
        debugPrint('Duplicate relay message: ${message.id}');
        return;
      }

      debugPrint('Relay message saved: ${message.id}');
      debugPrint('Destination: ${message.receiverId}');

      final destinationAddress = findAddressByDeviceId(message.receiverId);

      if (destinationAddress == null) {
        debugPrint('Destination is not connected. Message stored.');
        return;
      }

      if (destinationAddress == senderAddress) {
        debugPrint('Skipping sender to prevent routing loop');
        return;
      }

      final forwardedMessage = message.copyWith(hopCount: message.hopCount + 1);

      final success = await sendPacketToDevice(
        destinationAddress,
        forwardedMessage.toWireJson(),
      );

      if (success) {
        debugPrint('Message ${message.id} forwarded to ${message.receiverId}');
      } else {
        debugPrint('Forwarding failed: ${message.id}');
      }
    } catch (e) {
      debugPrint('Relay error: $e');
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

      await loadConversations();

      if (isConnected) {
        for (final address in connectedAddresses) {
          await sendHello(address);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = 'Device identity error: $e';
      });
    }
  }

  Future<void> openConversation(String peerId) async {
    messageController.clear();

    setState(() {
      selectedPeerId = peerId;
      conversationMessages = [];
      loadingMessages = true;
    });

    try {
      final savedMessages = await DatabaseHelper.instance.getConversation(
        localDeviceId,
        peerId,
      );

      if (!mounted || selectedPeerId != peerId) return;

      setState(() {
        conversationMessages = savedMessages;
        loadingMessages = false;
      });
    } catch (e) {
      if (!mounted || selectedPeerId != peerId) return;

      setState(() {
        loadingMessages = false;
        status = 'Failed to load conversation: $e';
      });
    }
  }

  Future<void> sendConversationMessage() async {
    final peerId = selectedPeerId;
    final text = messageController.text.trim();

    if (peerId == null || text.isEmpty || sending || localDeviceId.isEmpty) {
      return;
    }

    final nextHopAddress = findNextHopAddress(peerId);

    if (nextHopAddress == null) {
      setState(() {
        status = 'No available route to destination';
      });
      return;
    }

    final isDirectConnection = findAddressByDeviceId(peerId) != null;

    setState(() {
      sending = true;
    });

    try {
      final message = Message.create(
        senderId: localDeviceId,
        receiverId: peerId,
        text: text,
      );

      final success = await sendPacketToDevice(
        nextHopAddress,
        message.toWireJson(),
      );

      if (!mounted) return;

      if (success) {
        final savedMessage = message.copyWith(status: 'sent');

        await DatabaseHelper.instance.insertMessage(savedMessage);

        if (!mounted) return;

        setState(() {
          if (selectedPeerId == peerId) {
            conversationMessages.add(savedMessage);
            messageController.clear();
          }

          status = isDirectConnection
              ? 'Message sent directly'
              : 'Message sent to relay';
        });

        await loadConversations();
      } else {
        setState(() {
          status = 'Failed to send message';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Send error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
        });
      }
    }
  }

  Widget buildConversationTab() {
    final peerId = selectedPeerId;

    if (peerId == null) {
      return buildChatsTab();
    }

    if (loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        ListTile(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              setState(() {
                selectedPeerId = null;
                conversationMessages = [];
              });

              loadConversations();
            },
          ),
          title: Text('Device ${peerId.substring(0, 8)}'),
          subtitle: Text(
            connectedAddresses.any(
                  (address) => peerIdsByAddress[address] == peerId,
                )
                ? 'Connected'
                : 'Offline',
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: conversationMessages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: conversationMessages.length,
                  itemBuilder: (context, index) {
                    final message = conversationMessages[index];

                    final isMine = message.senderId == localDeviceId;

                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.blue.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message.text),

                            const SizedBox(height: 4),

                            Text(
                              '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:'
                              '${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  enabled: !sending && findNextHopAddress(peerId) != null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => sendConversationMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: sending || findNextHopAddress(peerId) == null
                    ? null
                    : sendConversationMessage,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> showNewChatDialog() async {
    final directPeers = peerIdsByAddress.entries
        .where(
          (entry) =>
              connectedAddresses.contains(entry.key) && entry.value.isNotEmpty,
        )
        .toList();

    final indirectPeers = reachablePeers.entries
        .where(
          (entry) =>
              connectedAddresses.contains(entry.value) &&
              findAddressByDeviceId(entry.key) == null,
        )
        .toList();

    final peerId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New Chat'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (directPeers.isNotEmpty) ...[
                  const Text(
                    'Direct connections',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final peer in directPeers)
                    ListTile(
                      leading: const Icon(Icons.bluetooth_connected),
                      title: Text('Device ${peer.value.substring(0, 8)}'),
                      subtitle: const Text('Direct connection'),
                      onTap: () {
                        Navigator.pop(dialogContext, peer.value);
                      },
                    ),
                ],

                if (indirectPeers.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Available through relay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final peer in indirectPeers)
                    ListTile(
                      leading: const Icon(Icons.route),
                      title: Text('Device ${peer.key.substring(0, 8)}'),
                      subtitle: Text(
                        'Via ${peerIdsByAddress[peer.value] ?? peer.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(dialogContext, peer.key);
                      },
                    ),
                ],

                if (directPeers.isEmpty && indirectPeers.isEmpty)
                  const Text(
                    'No devices discovered. '
                    'Connect nearby devices first.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted || peerId == null) return;

    await openConversation(peerId);
  }

  Widget buildChatsTab() {
    if (loadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }

    if (conversationPeerIds.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }

    return ListView.builder(
      itemCount: conversationPeerIds.length,
      itemBuilder: (context, index) {
        final peerId = conversationPeerIds[index];

        return FutureBuilder<Message?>(
          future: DatabaseHelper.instance.getLastConversationMessage(
            localDeviceId,
            peerId,
          ),
          builder: (context, snapshot) {
            final lastMessage = snapshot.data;

            String subtitle = 'No messages yet';
            String time = '';

            if (lastMessage != null) {
              final isMine = lastMessage.senderId == localDeviceId;

              subtitle = isMine ? 'You: ${lastMessage.text}' : lastMessage.text;

              final localTime = lastMessage.createdAt.toLocal();

              time =
                  '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}';
            }

            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('Device ${peerId.substring(0, 8)}'),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                openConversation(peerId);
              },
            );
          },
        );
      },
    );
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
      appBar: AppBar(
        title: const Text('MultiHop Messenger'),
        actions: [
          if (selectedTab == 0 && selectedPeerId == null)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: 'New Chat',
              onPressed: showNewChatDialog,
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            selectedTab = index;
          });

          if (index == 0) {
            loadConversations();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Devices'),
        ],
      ),
      body: selectedTab == 0
          ? (selectedPeerId == null ? buildChatsTab() : buildConversationTab())
          : ListView(
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

                SelectableText(
                  localDeviceId.isEmpty ? 'Loading...' : localDeviceId,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connected Peer UUID:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),

                if (peerIdsByAddress.isEmpty)
                  const Text('No peer UUIDs received yet'),

                for (final entry in peerIdsByAddress.entries)
                  ListTile(
                    dense: true,
                    title: SelectableText(entry.value),
                    subtitle: Text('Bluetooth: ${entry.key}'),
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
                  'Nearby Bluetooth Devices',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: isScanning ? null : scanNearbyDevices,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(isScanning ? 'Scanning...' : 'Scan Nearby'),
                ),

                ElevatedButton.icon(
                  onPressed: () => callKotlin('requestDiscoverable'),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Make My Device Visible'),
                ),

                const SizedBox(height: 12),

                for (final device in discoveredDevices)
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
                  'Connected Devices',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                if (connectedAddresses.isEmpty)
                  const Text('No connected devices'),

                for (final address in connectedAddresses)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.bluetooth_connected,
                        color: Colors.green,
                      ),
                      title: Text(
                        address,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text('Connected'),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off),
                        tooltip: 'Disconnect',
                        onPressed: () => disconnectFromDevice(address),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

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
                    await loadConnectedDevices();

                    if (!mounted) return;

                    setState(() {
                      peerIdsByAddress.clear();
                    });
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
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
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
