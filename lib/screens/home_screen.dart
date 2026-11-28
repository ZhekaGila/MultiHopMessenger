part of '../main.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RoutingService routingService = RoutingService.instance;
  final MessageService messageService = MessageService.instance;
  final NetworkLogger networkLogger = NetworkLogger.instance;
  final EncryptionService encryptionService = EncryptionService.instance;

  final bluetoothService = BluetoothService.instance;

  final messageController = TextEditingController();
  final scrollController = ScrollController();

  StreamSubscription<dynamic>? eventSubscription;

  String status = 'Waiting for action...';
  String connectionStatus = 'Disconnected';

  List<BluetoothDeviceInfo> pairedDevices = [];
  List<BluetoothDeviceInfo> discoveredDevices = [];

  List<String> connectedAddresses = [];

  bool isScanning = false;

  bool sending = false;

  int selectedTab = 0;

  List<String> conversationPeerIds = [];

  String? selectedPeerId;

  List<Message> conversationMessages = [];

  final Map<String, int> unreadMessagesByPeer = {};

  bool loadingMessages = false;

  bool loadingConversations = false;

  String localDeviceId = '';

  final Map<String, String> peerIdsByAddress = {};

  final Map<String, RouteEntry> reachablePeers = {};

  static const int maxHopCount = 5;

  bool get isConnected => connectedAddresses.isNotEmpty;

  @override
  void initState() {
    super.initState();

    initializeDeviceIdentity();

    loadConnectedDevices();

    eventSubscription = bluetoothService.listenToEvents(
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

      networkLogger.log(
        eventType: 'SEND_FAILED',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[address],
        details: 'Device not connected: $address',
      );

      return false;
    }

    try {
      final sent = await bluetoothService.sendPacket(address, packet);

      networkLogger.log(
        eventType: sent ? 'SEND' : 'SEND_FAILED',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[address],
        details: 'Bluetooth packet to $address',
      );

      return sent;
    } on PlatformException catch (e) {
      debugPrint('Bluetooth send error: ${e.message}');

      networkLogger.log(
        eventType: 'SEND_FAILED',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[address],
        details: 'Bluetooth error: ${e.message}',
      );

      return false;
    }
  }

  Future<void> sendPeers(String address) async {
    if (!connectedAddresses.contains(address) || localDeviceId.isEmpty) {
      return;
    }

    final packet = routingService.createPeersPacket(
      localDeviceId: localDeviceId,
      targetAddress: address,
      peerIdsByAddress: peerIdsByAddress,
      connectedAddresses: connectedAddresses,
    );

    final peers = packet['peers'];

    final success = await sendPacketToDevice(address, jsonEncode(packet));

    if (success) {
      debugPrint('PEERS sent to $address: $peers');
    } else {
      debugPrint('PEERS failed for $address');
    }
  }

  Future<void> sendRoutes(String address) async {
    if (!connectedAddresses.contains(address) || localDeviceId.isEmpty) {
      return;
    }

    final packet = routingService.createRoutesPacket(
      localDeviceId: localDeviceId,
      targetAddress: address,
      peerIdsByAddress: peerIdsByAddress,
      knownRoutes: reachablePeers,
      connectedAddresses: connectedAddresses,
      maxHopCount: maxHopCount,
    );

    final success = await sendPacketToDevice(address, jsonEncode(packet));

    if (success) {
      debugPrint('ROUTES sent to $address: ${packet['routes']}');
    } else {
      debugPrint('ROUTES failed for $address');
    }
  }

  Future<void> broadcastRoutes() async {
    for (final address in List<String>.from(connectedAddresses)) {
      if (peerIdsByAddress[address] == null) {
        continue;
      }

      await sendRoutes(address);
    }
  }

  Future<void> sendHello(String address) async {
    if (!connectedAddresses.contains(address) || localDeviceId.isEmpty) {
      return;
    }

    final helloPacket = routingService.createHelloPacket(localDeviceId);

    final success = await sendPacketToDevice(address, jsonEncode(helloPacket));

    if (!success) {
      debugPrint('HELLO failed for $address');
    }
  }

  Future<void> sendAck(String messageId, String senderAddress) async {
    if (!connectedAddresses.contains(senderAddress) || localDeviceId.isEmpty) {
      return;
    }

    final ackPacket = messageService.createAckPacket(
      messageId: messageId,
      deviceId: localDeviceId,
    );

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
      debugPrint('ACK ignored: message already delivered');
      return;
    }

    if (message.receiverId == senderDeviceId) {
      await DatabaseHelper.instance.updateMessageStatus(messageId, 'delivered');

      networkLogger.log(
        eventType: 'ACK',
        deviceId: localDeviceId,
        messageId: messageId,
        peerId: senderDeviceId,
        hopCount: message.hopCount,
        details: 'Final recipient acknowledged message',
      );

      debugPrint('Message delivered: $messageId');
    } else {
      await DatabaseHelper.instance.updateMessageStatus(messageId, 'forwarded');

      networkLogger.log(
        eventType: 'ACK',
        deviceId: localDeviceId,
        messageId: messageId,
        peerId: senderDeviceId,
        hopCount: message.hopCount,
        details: 'Relay acknowledged message',
      );

      debugPrint('Message forwarded to relay: $messageId');
    }
  }

  Future<void> saveReceivedJsonMessage(
    Message message,
    String senderAddress,
  ) async {
    try {
      final encryptedData = jsonDecode(message.text);

      if (encryptedData is! Map<String, dynamic>) {
        throw const FormatException('Invalid encrypted message');
      }

      final decryptedText = await encryptionService.decrypt(
        encryptedData.map((key, value) => MapEntry(key, value.toString())),
        encryptionService.demoKey,
      );

      final savedMessage = Message(
        id: message.id,
        senderId: message.senderId,
        receiverId: message.receiverId,
        text: decryptedText,
        createdAt: message.createdAt,
        status: 'received',
        hopCount: message.hopCount,
      );

      final inserted = await DatabaseHelper.instance.insertMessage(
        savedMessage,
      );

      await sendAck(message.id, senderAddress);

      if (!inserted) {
        debugPrint('Duplicate message ignored: ${message.id}');
        return;
      }

      if (!mounted) return;

      final isOpenConversation =
          selectedTab == 0 && selectedPeerId == savedMessage.senderId;
      setState(() {
        if (isOpenConversation) {
          conversationMessages.add(savedMessage);
        } else {
          unreadMessagesByPeer.update(
            savedMessage.senderId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      });

      if (isOpenConversation) {
        scrollToBottom();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'New message from Device ${savedMessage.senderId.substring(0, 8)}',
              ),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => openConversation(savedMessage.senderId),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
      }

      await loadConversations();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'Receive error: $e';
      });
    }
  }

  Future<void> forwardMessagesToPeer(String address) async {
    if (!connectedAddresses.contains(address)) {
      return;
    }

    final peerId = peerIdsByAddress[address];

    if (peerId == null || peerId.isEmpty) {
      return;
    }

    final pendingMessages = await DatabaseHelper.instance.getPendingMessages();

    for (final message in pendingMessages) {
      if (!connectedAddresses.contains(address)) {
        break;
      }

      if (message.receiverId == localDeviceId) {
        continue;
      }

      if (message.hopCount >= maxHopCount) {
        debugPrint('Hop limit reached: ${message.id}');
        continue;
      }

      final nextHopAddress = findNextHopAddress(message.receiverId);

      if (nextHopAddress != address) {
        continue;
      }

      final forwardedMessage = message.copyWith(hopCount: message.hopCount + 1);

      final success = await sendPacketToDevice(
        address,
        forwardedMessage.toWireJson(),
      );

      if (success) {
        networkLogger.log(
          eventType: 'FORWARD',
          deviceId: localDeviceId,
          messageId: message.id,
          peerId: peerId,
          hopCount: forwardedMessage.hopCount,
          details: 'Stored message forwarded to $address',
        );

        debugPrint('Stored message ${message.id} forwarded to $peerId');
      } else {
        debugPrint('Failed to forward stored message ${message.id}');
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

      networkLogger.log(
        eventType: 'RECEIVE',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[senderAddress],
        messageId: data['messageId']?.toString(),
        hopCount: (data['hopCount'] as num?)?.toInt(),
        details: 'Packet type: $packetType; from: $senderAddress',
      );

      if (packetType == 'routes') {
        final updatedRoutes = routingService.processRoutePacket(
          senderAddress: senderAddress,
          senderDeviceId: data['deviceId'] is String
              ? data['deviceId'] as String
              : null,
          receivedRoutes: data['routes'],
          localDeviceId: localDeviceId,
          peerIdsByAddress: peerIdsByAddress,
          knownRoutes: reachablePeers,
          connectedAddresses: connectedAddresses,
          maxHopCount: maxHopCount,
        );

        if (updatedRoutes == null) {
          debugPrint('Invalid ROUTES packet');
          return;
        }

        bool routesChanged = updatedRoutes.length != reachablePeers.length;

        if (!routesChanged) {
          for (final entry in updatedRoutes.entries) {
            final oldRoute = reachablePeers[entry.key];
            final newRoute = entry.value;

            if (oldRoute == null ||
                oldRoute.nextHopAddress != newRoute.nextHopAddress ||
                oldRoute.hopCount != newRoute.hopCount) {
              routesChanged = true;
              break;
            }
          }
        }

        if (!routesChanged || !mounted) {
          return;
        }

        setState(() {
          reachablePeers
            ..clear()
            ..addAll(updatedRoutes);
        });

        debugPrint('Routing table updated:');

        for (final route in reachablePeers.values) {
          debugPrint(
            '${route.destinationId} -> '
            '${route.nextHopAddress} '
            '(${route.hopCount} hops)',
          );
        }

        broadcastRoutes();

        for (final address in List<String>.from(connectedAddresses)) {
          if (peerIdsByAddress[address] != null) {
            forwardMessagesToPeer(address);
          }
        }

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

          broadcastRoutes();
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

      networkLogger.log(
        eventType: 'CONNECT',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[address],
        details: 'Bluetooth connected: $address',
      );

      return;
    }

    if (type == 'peerDisconnected') {
      final address = event['address']?.toString() ?? '';

      if (address.isNotEmpty) {
        setState(() {
          peerIdsByAddress.remove(address);

          reachablePeers.removeWhere(
            (deviceId, route) => route.nextHopAddress == address,
          );
        });
      }

      networkLogger.log(
        eventType: 'DISCONNECT',
        deviceId: localDeviceId,
        peerId: peerIdsByAddress[address],
        details: 'Bluetooth disconnected: $address',
      );

      loadConnectedDevices().then((_) {
        if (mounted) {
          broadcastRoutes();
        }
      });

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

  void clearPeerIds() {
    if (!mounted) return;

    setState(() {
      peerIdsByAddress.clear();
    });
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
      final result = await bluetoothService.invokeString(method);

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
      final result = await bluetoothService.startDiscovery();

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
      final result = await bluetoothService.getPairedDevices();

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
      final result = await bluetoothService.getConnectedDevices();

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
      final result = await bluetoothService.connectToDevice(address);

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
      final result = await bluetoothService.disconnectDevice(address);

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
      final result = await bluetoothService.getConnectionStatus();

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
    return routingService.findDirectAddress(
      deviceId: deviceId,
      peerIdsByAddress: peerIdsByAddress,
      connectedAddresses: connectedAddresses,
    );
  }

  String? findNextHopAddress(String destinationId) {
    final directAddress = findAddressByDeviceId(destinationId);

    if (directAddress != null) {
      return directAddress;
    }

    final route = reachablePeers[destinationId];

    if (route == null) {
      return null;
    }

    if (!connectedAddresses.contains(route.nextHopAddress)) {
      return null;
    }

    return route.nextHopAddress;
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

      // Find the next hop using the routing table.
      final nextHopAddress = findNextHopAddress(message.receiverId);

      if (nextHopAddress == null) {
        debugPrint('No route available. Message stored.');
        return;
      }

      // Avoid immediately forwarding back to the sender.
      if (nextHopAddress == senderAddress) {
        debugPrint('Skipping sender to prevent routing loop');
        return;
      }

      final forwardedMessage = message.copyWith(hopCount: message.hopCount + 1);

      final success = await sendPacketToDevice(
        nextHopAddress,
        forwardedMessage.toWireJson(),
      );

      if (success) {
        networkLogger.log(
          eventType: 'FORWARD',
          deviceId: localDeviceId,
          messageId: message.id,
          peerId: peerIdsByAddress[nextHopAddress],
          hopCount: forwardedMessage.hopCount,
          details: 'Forwarded to $nextHopAddress',
        );

        debugPrint('Message ${message.id} forwarded to $nextHopAddress');
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
      selectedTab = 0;
      selectedPeerId = peerId;
      conversationMessages = [];
      loadingMessages = true;
      unreadMessagesByPeer.remove(peerId);
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
      scrollToBottom();
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
      final encrypted = await encryptionService.encrypt(
        text,
        encryptionService.demoKey,
      );

      final encryptedPayload = jsonEncode({
        'ciphertext': encrypted['ciphertext'],
        'nonce': encrypted['nonce'],
        'mac': encrypted['mac'],
      });

      final message = Message.create(
        senderId: localDeviceId,
        receiverId: peerId,
        text: encryptedPayload,
      );

      final success = await sendPacketToDevice(
        nextHopAddress,
        message.toWireJson(),
      );

      if (!mounted) return;

      if (success) {
        final savedMessage = Message(
          id: message.id,
          senderId: message.senderId,
          receiverId: message.receiverId,
          text: text,
          createdAt: message.createdAt,
          status: 'sent',
          hopCount: message.hopCount,
        );

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

  void closeConversation() {
    if (!mounted) return;

    setState(() {
      selectedPeerId = null;
      conversationMessages = [];
    });

    loadConversations();
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    messageController.dispose();
    scrollController.dispose();
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
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            selectedIcon: Icon(Icons.list_alt_outlined),
            label: 'Logs',
          ),
        ],
      ),
      body: selectedTab == 0
          ? (selectedPeerId == null ? buildChatsTab() : buildConversationTab())
          : selectedTab == 1
          ? buildDevicesTab()
          : const NetworkLogsScreen(),
    );
  }
}
