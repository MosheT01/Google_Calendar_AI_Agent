import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../core/constants/app_colors.dart';

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isUser;
  final String? debugPrompt;
  final String? debugTrace;
  final String? debugFunctionCalls;
  final String? debugResponse;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    this.debugPrompt,
    this.debugTrace,
    this.debugFunctionCalls,
    this.debugResponse,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasDebug = kDebugMode &&
        (widget.debugPrompt != null ||
            widget.debugTrace != null ||
            widget.debugFunctionCalls != null ||
            widget.debugResponse != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment:
              widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              gradient: widget.isUser
                  ? const LinearGradient(
                      colors: [Color(0xFFFFEEF2), Color(0xFFFFDFE7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFF6F6F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              border: Border.all(
                color: widget.isUser
                    ? const Color(0xFFFFC9D7)
                    : const Color(0xFFE4E4E4),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft:
                    widget.isUser ? const Radius.circular(16) : Radius.zero,
                bottomRight:
                    widget.isUser ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.isUser
                    ? SelectableText(
                        widget.message,
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.left,
                      )
                    : MarkdownBody(
                        data: widget.message,
                        selectable: true,
                        styleSheet: _markdownStyleSheet(),
                        softLineBreak: true,
                      ),
                if (hasDebug && !widget.isUser) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: const Color(0xFF555555),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded ? 'Hide debug' : 'Show debug',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: const Color(0xFF555555),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0x33000000)),
                    const SizedBox(height: 8),
                    _buildDebugSection(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.debugPrompt != null) ...[
          _buildSection('Prompt', widget.debugPrompt!),
          const SizedBox(height: 8),
        ],
        if (widget.debugTrace != null) ...[
          _buildSection('Execution Trace', widget.debugTrace!),
          const SizedBox(height: 8),
        ],
        if (widget.debugFunctionCalls != null) ...[
          _buildSection('Function Calls', widget.debugFunctionCalls!),
          const SizedBox(height: 8),
        ],
        if (widget.debugResponse != null)
          _buildSection('Model Response', widget.debugResponse!),
      ],
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.lato(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          width: double.infinity,
          child: SelectableText(
            content,
            style: GoogleFonts.firaCode(
              fontSize: 11,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  MarkdownStyleSheet _markdownStyleSheet() {
    final bodyStyle = GoogleFonts.lato(
      fontSize: 16,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

    return MarkdownStyleSheet(
      p: bodyStyle,
      h1: GoogleFonts.lato(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      h2: GoogleFonts.lato(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      h3: GoogleFonts.lato(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      listBullet: bodyStyle,
      blockquote: bodyStyle.copyWith(color: Colors.black54),
      blockquoteDecoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: const Color(0xFF2F4E6F),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFECF2F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E5F1)),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: bodyStyle.copyWith(
        color: const Color(0xFF1565C0),
        decoration: TextDecoration.underline,
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x1F000000), width: 1),
        ),
      ),
      tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w700),
      tableBody: bodyStyle,
      tableBorder: TableBorder.all(color: const Color(0x1A000000), width: 1),
      tableCellsPadding: const EdgeInsets.all(8),
      em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
      strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
