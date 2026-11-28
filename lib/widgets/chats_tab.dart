part of '../main.dart';

extension _ChatsTabBuilder on _HomeScreenState {
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
        final directConnection = findAddressByDeviceId(peerId) != null;
        final routeAvailable = findNextHopAddress(peerId) != null;
        final unreadCount = unreadMessagesByPeer[peerId] ?? 0;
        final reachability = directConnection
            ? 'Connected'
            : routeAvailable
            ? 'Route available'
            : 'Offline';
        final reachabilityColor = directConnection || routeAvailable
            ? Colors.green
            : Colors.grey;

        return FutureBuilder<Message?>(
          future: DatabaseHelper.instance.getLastConversationMessage(
            localDeviceId,
            peerId,
          ),
          builder: (context, snapshot) {
            final lastMessage = snapshot.data;

            String latestMessage = 'No messages yet';
            String time = '';

            if (lastMessage != null) {
              final isMine = lastMessage.senderId == localDeviceId;

              latestMessage = isMine
                  ? 'You: ${lastMessage.text}'
                  : lastMessage.text;

              final localTime = lastMessage.createdAt.toLocal();

              time =
                  '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}';
            }

            return ListTile(
              leading: CircleAvatar(
                child: Icon(
                  Icons.person,
                  color: reachabilityColor,
                ),
              ),
              title: Text('Device ${peerId.substring(0, 8)}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    latestMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    reachability,
                    style: TextStyle(color: reachabilityColor, fontSize: 12),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (unreadCount > 0)
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    )
                  else
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
}
