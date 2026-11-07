import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'state.dart';
import 'ui.dart';

const suggestions = ['모란시장 위험해?', '내 주변 위험해?', '방금 감지된 거 위험해?', '진동이 울리면 어떻게 해야 해?']; // 답을 확인한 질문만

/// 라벨링 콘솔에서 학습해 올린 대화 모델(safety-chat)과 대화
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final input = TextEditingController();

  void _send([String? text]) {
    final t = (text ?? input.text).trim();
    if (t.isEmpty || app.chatting) return;
    input.clear();
    app.sendChat(t);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final media = MediaQuery.of(context);
          final above = media.viewInsets.bottom > 0 ? 0.0 : media.padding.bottom; // 탭 막대 높이 (키보드가 올라오면 가려짐)
          final padding = EdgeInsets.only(top: media.padding.top + 56, bottom: above + media.textScaler.scale(68));
          return Stack(children: [
            Positioned.fill(
              child: app.chat.isEmpty
                  ? ListView(padding: padding, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
                      AppCard(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('보행 위험에 대해 물어보세요', style: bold.copyWith(fontSize: 17, letterSpacing: -.2)),
                            const SizedBox(height: 4),
                            Text('사고다발지역과 실시간 감지 기록을 근거로 답합니다.', style: mutedText),
                            const SizedBox(height: 14),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final s in suggestions)
                                Pressable(
                                  onTap: () => _send(s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(99)),
                                    child: Text(s, style: TextStyle(color: brand, fontWeight: FontWeight.w500, fontSize: 14)),
                                  ),
                                ),
                            ]),
                          ]),
                        ),
                      ),
                    ])
                  : ListView(
                      reverse: true, // 새 메시지가 아래에 붙고 자동으로 보이게
                      padding: padding,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (app.chatting)
                          app.streaming.isEmpty
                              ? const _Bubble(role: 'assistant', text: '답변 작성 중', pending: true)
                              : _Bubble(role: 'assistant', text: app.streaming),
                        for (final m in app.chat.reversed) _Bubble(role: m.role, text: m.content),
                      ],
                    ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CupertinoNavigationBar(
                backgroundColor: chrome,
                automaticBackgroundVisibility: false,
                transitionBetweenRoutes: false,
                middle: FittedBox( // 막대 높이가 고정이라 큰 글자에서는 줄여서 맞춤
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Safety AI'),
                    Text('Improved using Qwen · Qwen2.5-3B 튜닝 모델', style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w400, letterSpacing: 0, color: muted)),
                  ]),
                ),
                trailing: app.chat.isEmpty
                    ? null
                    : CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => app.update(app.chat.clear),
                        child: const Icon(CupertinoIcons.trash, size: 22, semanticLabel: '대화 지우기'),
                      ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: above,
              child: Frosted(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: input,
                        placeholder: '예) 모란시장 입구 위험해?',
                        placeholderStyle: TextStyle(color: muted, fontSize: 16),
                        style: TextStyle(color: textColor, fontSize: 16),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
                      ),
                    ),
                    Pressable(
                      onTap: app.chatting ? null : _send,
                      label: '보내기',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: app.chatting ? line : brand),
                          child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.role, required this.text, this.pending = false});
  final String role, text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final user = role == 'user', error = role == 'error';
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (user ? .75 : .88)),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: role == 'assistant' && !pending ? 14 : 10),
      decoration: BoxDecoration(
        color: user ? brand : error ? levelColors['LOW']!.withValues(alpha: .25) : surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(user ? 18 : 6),
          bottomRight: Radius.circular(user ? 6 : 18),
        ),
      ),
      child: pending
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const CupertinoActivityIndicator(radius: 8),
              const SizedBox(width: 8),
              Text(text, style: TextStyle(color: muted, fontSize: 14.5)),
            ])
          : role == 'assistant'
              ? MarkdownBody(data: text, styleSheet: notionStyle, selectable: true)
              : Text(text, style: TextStyle(color: user ? Colors.white : textColor, height: 1.45, fontSize: 14.5)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: bubble),
    );
  }
}

// 노션 느낌: 회색 콜아웃(> 💡), 얇은 표, 이모지 소제목, 구분선
MarkdownStyleSheet get notionStyle => MarkdownStyleSheet(
      p: TextStyle(fontSize: 14.5, height: 1.6, color: textColor),
      h2: TextStyle(fontSize: 19, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -.3, color: textColor),
      h2Padding: const EdgeInsets.only(bottom: 2),
      h3: TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w600, color: textColor),
      h3Padding: const EdgeInsets.only(top: 10),
      strong: const TextStyle(fontWeight: FontWeight.w600),
      em: TextStyle(fontStyle: FontStyle.italic, color: muted, fontSize: 12.5),
      blockSpacing: 10,
      blockquote: TextStyle(fontSize: 14.5, height: 1.55, color: textColor),
      blockquotePadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(10)),
      listBullet: TextStyle(fontSize: 14.5, color: textColor),
      tableHead: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
      tableBody: TextStyle(fontSize: 13, color: textColor),
      tableBorder: TableBorder.all(color: line),
      tableColumnWidth: const IntrinsicColumnWidth(), // 넓은 표는 가로 스크롤 (overflow 방지)
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      tableHeadCellsDecoration: BoxDecoration(color: line),
      code: TextStyle(fontSize: 13, color: levelColors['MEDIUM'], backgroundColor: line),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
    );
