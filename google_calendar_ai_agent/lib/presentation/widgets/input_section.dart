import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

class InputSection extends StatefulWidget {
  final TextEditingController controller;
  final bool isListening;
  final VoidCallback onSend;
  final VoidCallback onMic;

  const InputSection({
    super.key,
    required this.controller,
    required this.isListening,
    required this.onSend,
    required this.onMic,
  });

  @override
  State<InputSection> createState() => _InputSectionState();
}

class _InputSectionState extends State<InputSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    maxHeight: 150.0,
                  ),
                  child: Scrollbar(
                    child: TextField(
                      controller: widget.controller,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        hintStyle: GoogleFonts.lato(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isListening)
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.red,
                child: IconButton(
                  icon: const Icon(Icons.mic, color: Colors.white),
                  onPressed: widget.onMic,
                ),
              )
            else
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary,
                child: IconButton(
                  icon: Icon(
                    widget.controller.text.trim().isEmpty ? Icons.mic : Icons.send,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (widget.controller.text.trim().isNotEmpty) {
                      widget.onSend();
                      widget.controller.clear();
                    } else {
                      widget.onMic();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}