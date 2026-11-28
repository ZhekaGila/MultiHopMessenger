part of '../main.dart';

extension _DevicesTabBuilder on _HomeScreenState {
  Widget buildDevicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'My Device ID:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),

        SelectableText(localDeviceId.isEmpty ? 'Loading...' : localDeviceId),
        const SizedBox(height: 8),
        const Text(
          'Connected Peer UUID:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        if (peerIdsByAddress.isEmpty) const Text('No peer UUIDs received yet'),

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

        if (connectedAddresses.isEmpty) const Text('No connected devices'),

        for (final address in connectedAddresses)
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.bluetooth_connected,
                color: Colors.green,
              ),
              title: Text(address, style: const TextStyle(fontSize: 14)),
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

            clearPeerIds();
          },
          child: const Text('Disconnect'),
        ),

      ],
    );
  }
}
