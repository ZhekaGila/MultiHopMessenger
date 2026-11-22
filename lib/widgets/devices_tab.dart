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
    );
  }
}
