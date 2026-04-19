import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../providers/app_provider.dart';
import '../widgets/chat_list_view.dart';
import '../widgets/input_section.dart';
import '../widgets/loading_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getModelName(String model) {
    final names = {
      'gemini-2.5-flash': 'Gemini 2.5 Flash',
      'gemini-2.5-flash-lite': 'Gemini 2.5 Flash Lite',
      'gemini-2.5-pro': 'Gemini 2.5 Pro',
      'gemini-3.1-pro-preview': 'Gemini 3.1 Pro',
      'gemini-3-flash-preview': 'Gemini 3 Flash',
      'gemini-3.1-flash-lite-preview': 'Gemini 3.1 Flash Lite',
    };
    return names[model] ?? model;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return LoadingScreen(
            message: provider.loadingMessages[provider.loadingMessageIndex],
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(70.0),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                forceMaterialTransparency: true,
                elevation: 0,
                centerTitle: true,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      backgroundImage: NetworkImage(
                        'https://www.iconarchive.com/download/i26941/noctuline/wall-e/EVE.ico',
                      ),
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Bella",
                          style: GoogleFonts.lato(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          "Online",
                          style: GoogleFonts.lato(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  PopupMenuButton<String>(
                    onSelected: (model) {
                      provider.saveDefaultModel(model);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Model changed to ${_getModelName(model)}'),
                          backgroundColor: AppColors.primary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'gemini-2.5-flash',
                        child: Text('⚡ Gemini 2.5 Flash'),
                      ),
                      const PopupMenuItem(
                        value: 'gemini-2.5-flash-lite',
                        child: Text('💨 Gemini 2.5 Flash Lite'),
                      ),
                      const PopupMenuItem(
                        value: 'gemini-3.1-pro-preview',
                        child: Text('💎 Gemini 3.1 Pro'),
                      ),
                      const PopupMenuItem(
                        value: 'gemini-3-flash-preview',
                        child: Text('🚀 Gemini 3 Flash'),
                      ),
                      const PopupMenuItem(
                        value: 'gemini-3.1-flash-lite-preview',
                        child: Text('📱 Gemini 3.1 Flash Lite'),
                      ),
                      const PopupMenuItem(
                        value: 'gemini-2.5-pro',
                        child: Text('🧠 Gemini 2.5 Pro'),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ChatListView(
                  messages: provider.chatMessages,
                  isThinking: provider.isThinking,
                  scrollController: _scrollController,
                ),
              ),
              InputSection(
                controller: _queryController,
                isListening: provider.isListening,
                onSend: () {
                  if (_queryController.text.trim().isNotEmpty) {
                    provider.handleUserQuery(_queryController.text.trim());
                  }
                },
                onMic: provider.toggleListening,
              ),
            ],
          ),
        );
      },
    );
  }
}