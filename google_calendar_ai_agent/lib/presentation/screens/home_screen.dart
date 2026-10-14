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

  String _getTtsName(String engine) {
    if (engine == 'cloud') {
      return 'Cloud TTS';
    }
    return 'Device TTS';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (_queryController.text != provider.draftInput) {
          _queryController.value = TextEditingValue(
            text: provider.draftInput,
            selection: TextSelection.collapsed(
              offset: provider.draftInput.length,
            ),
          );
        }

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
                      backgroundColor: Colors.white,
                      radius: 22,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: AssetImage(
                          'assets/branding/bella_logo_1024.png',
                        ),
                      ),
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
                          "Calendar Agent",
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
                    onSelected: (selection) {
                      if (selection.startsWith('model:')) {
                        final model = selection.substring('model:'.length);
                        provider.saveDefaultModel(model);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Model changed to ${_getModelName(model)}'),
                            backgroundColor: AppColors.primary,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        return;
                      }

                      if (selection.startsWith('tts:')) {
                        final engine = selection.substring('tts:'.length);
                        provider.saveTtsEngine(engine);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Speech changed to ${_getTtsName(engine)}'),
                            backgroundColor: AppColors.primary,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        enabled: false,
                        value: '__header_model__',
                        child: Text('Model'),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-2.5-flash',
                        child: Text(
                          '${provider.currentModel == 'gemini-2.5-flash' ? '✓ ' : ''}⚡ Gemini 2.5 Flash',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-2.5-flash-lite',
                        child: Text(
                          '${provider.currentModel == 'gemini-2.5-flash-lite' ? '✓ ' : ''}💨 Gemini 2.5 Flash Lite',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-3.1-pro-preview',
                        child: Text(
                          '${provider.currentModel == 'gemini-3.1-pro-preview' ? '✓ ' : ''}💎 Gemini 3.1 Pro',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-3-flash-preview',
                        child: Text(
                          '${provider.currentModel == 'gemini-3-flash-preview' ? '✓ ' : ''}🚀 Gemini 3 Flash',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-3.1-flash-lite-preview',
                        child: Text(
                          '${provider.currentModel == 'gemini-3.1-flash-lite-preview' ? '✓ ' : ''}📱 Gemini 3.1 Flash Lite',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'model:gemini-2.5-pro',
                        child: Text(
                          '${provider.currentModel == 'gemini-2.5-pro' ? '✓ ' : ''}🧠 Gemini 2.5 Pro',
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        enabled: false,
                        value: '__header_tts__',
                        child: Text('Speech'),
                      ),
                      PopupMenuItem(
                        value: 'tts:device',
                        child: Text(
                          '${provider.currentTtsEngine == 'device' ? '✓ ' : ''}🔊 Device TTS',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'tts:cloud',
                        child: Text(
                          '${provider.currentTtsEngine == 'cloud' ? '✓ ' : ''}☁ Cloud TTS',
                        ),
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
              if (provider.errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    provider.errorMessage!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      color: Colors.brown.shade900,
                      fontSize: 12,
                    ),
                  ),
                ),
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
                isThinking: provider.isThinking,
                onSend: () {
                  if (_queryController.text.trim().isNotEmpty) {
                    provider.handleUserQuery(
                      _queryController.text.trim(),
                    );
                  }
                },
                onMic: provider.toggleListening,
                onInterrupt: provider.interrupt,
                onChanged: provider.setDraftInput,
              ),
            ],
          ),
        );
      },
    );
  }
}
