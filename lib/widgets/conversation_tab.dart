part of '../main.dart';

extension _ConversationTabBuilder on _HomeScreenState {
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
            onPressed: closeConversation,
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
}
