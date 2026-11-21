import 'dart:async';

import 'package:flutter/services.dart';

class BluetoothService {
  BluetoothService._();

  static final BluetoothService instance = BluetoothService._();

  static const MethodChannel _channel = MethodChannel('multihop/bluetooth');

  static const EventChannel _eventChannel = EventChannel(
    'multihop/bluetooth_events',
  );

  StreamSubscription<dynamic> listenToEvents(
    void Function(dynamic) onEvent, {
    Function? onError,
  }) {
    return _eventChannel.receiveBroadcastStream().listen(
      onEvent,
      onError: onError,
    );
  }

  Future<String?> invokeString(
    String method, [
    Map<String, dynamic>? arguments,
  ]) {
    return _channel.invokeMethod<String>(method, arguments);
  }

  Future<List<dynamic>?> invokeList(String method) {
    return _channel.invokeMethod<List<dynamic>>(method);
  }

  Future<bool> sendPacket(String address, String packet) async {
    try {
      final result = await invokeString('sendMessageToDevice', {
        'address': address,
        'message': packet,
      });

      return result == 'Message sent';
    } on PlatformException {
      return false;
    }
  }

  Future<String?> startDiscovery() {
    return invokeString('startDiscovery');
  }

  Future<String?> connectToDevice(String address) {
    return invokeString('connectToDevice', {'address': address});
  }

  Future<String?> disconnectDevice(String address) {
    return invokeString('disconnectDevice', {'address': address});
  }

  Future<List<dynamic>?> getPairedDevices() {
    return invokeList('getPairedDevices');
  }

  Future<List<dynamic>?> getConnectedDevices() {
    return invokeList('getConnectedDevices');
  }

  Future<String?> getConnectionStatus() {
    return invokeString('getConnectionStatus');
  }
}
