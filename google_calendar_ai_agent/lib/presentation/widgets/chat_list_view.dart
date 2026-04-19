import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/chat_message.dart';
import 'chat_bubble.dart';

class ChatListView extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isThinking;
  final ScrollController scrollController;

  const ChatListView({
    super.key,
    required this.messages,
    required this.isThinking,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });

    return ListView.builder(
      controller: scrollController,
      itemCount: isThinking ? messages.length + 1 : messages.length,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemBuilder: (context, index) {
        if (isThinking && index == messages.length) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const ChatBubble(message: 'Thinking...', isUser: false),
              const SizedBox(width: 8),
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ],
          );
        }
        final message = messages[index];
        final isUser = message.role == 'user';
        return ChatBubble(message: message.content, isUser: isUser);
      },
    );
  }
}