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
}
