part of '../main.dart';

extension _NewChatDialogBuilder on _HomeScreenState {
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
}
