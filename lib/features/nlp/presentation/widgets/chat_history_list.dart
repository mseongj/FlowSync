import 'package:flutter/material.dart';
import '../../domain/entities/chat_message.dart';

class ChatHistoryList extends StatelessWidget {
  final List<ChatMessage> messages;

  const ChatHistoryList({Key? key, required this.messages}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true, // Show latest at bottom
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // Reverse index because of reverse: true
        final message = messages[messages.length - 1 - index];
        
        return Align(
          alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser ? Colors.blue[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: message.isPending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    message.text,
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        );
      },
    );
  }
}
