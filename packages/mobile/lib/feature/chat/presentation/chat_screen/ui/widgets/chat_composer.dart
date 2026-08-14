import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.sessionId,
    required this.snapshot,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.configOptions,
    required this.onSend,
    required this.onSteer,
    required this.onInterrupt,
    required this.onOpenSettings,
    this.steerUnavailable = false,
    this.pending = false,
    this.error,
    this.picker,
  });

  final String sessionId;
  final ConversationSnapshotModel snapshot;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final List<ChatConfigOptionModel> configOptions;
  final bool steerUnavailable;
  final bool pending;
  final String? error;
  final AttachmentPicker? picker;
  final Future<void> Function(
    String text, {
    List<ChatImageModel>? attachments,
    List<ChatResourceModel>? resources,
  })
  onSend;
  final Future<void> Function(String text) onSteer;
  final VoidCallback onInterrupt;
  final VoidCallback onOpenSettings;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final AttachmentPicker _picker =
      widget.picker ?? PlatformAttachmentPicker();

  Timer? _draftTimer;
  List<PickedAttachment> _attachments = [];
  ComposerSuggestion? _trigger;
  bool _queueDelivery = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    final draft =
        CacheHelper.get(CacheKeys.chatDraft(widget.sessionId)) as String?;
    if (draft != null && draft.isNotEmpty) _controller.text = draft;
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _turnRunning =>
      widget.snapshot.turns.any((turn) => turn.state == 'running');

  bool get _canSteer =>
      widget.snapshot.can('steer') && !widget.steerUnavailable && _turnRunning;

  bool get _steerEligible =>
      _canSteer && !_queueDelivery && _attachments.isEmpty;

  bool get _stopped => widget.snapshot.controllerState == 'stopped';

  Uint8List? _imageBytes(String? encoded) {
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      final text = _controller.text;
      unawaited(
        text.isEmpty
            ? CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId))
            : CacheHelper.save(CacheKeys.chatDraft(widget.sessionId), text),
      );
    });

    final caret = _controller.selection.baseOffset;
    final suggestion = findComposerSuggestion(
      _controller.text,
      caret < 0 ? null : caret,
    );
    final available = suggestion == null
        ? false
        : suggestion.kind == SuggestionKind.skills
        ? widget.skills.isNotEmpty
        : widget.filePaths.isNotEmpty;

    if (available && suggestion != _trigger) {
      _trigger = suggestion;
      unawaited(_openSuggestions(suggestion.kind, suggestion.query));
    } else if (!available) {
      _trigger = null;
    }
    setState(() {});
  }

  Future<void> _openSuggestions(SuggestionKind kind, String query) async {
    final trigger = _trigger;
    final value = await showSuggestionSheet(
      context,
      kind: kind,
      skills: widget.skills,
      filePaths: widget.filePaths,
      filePathsTruncated: widget.filePathsTruncated,
      initialQuery: query,
    );
    if (!mounted) return;

    _trigger = null;
    if (value == null) return;

    final text = _controller.text;
    final next = trigger != null && trigger.kind == kind
        ? replaceComposerSuggestion(text, trigger, value)
        : '$text${text.isEmpty || text.endsWith(' ') ? '' : ' '}'
              '${kind == SuggestionKind.skills ? '/$value' : (value.contains(' ') ? '"$value"' : value)} ';

    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _pick(Future<List<PickedAttachment>> Function() pick) async {
    setState(() => _localError = null);
    try {
      final picked = await pick();
      if (!mounted || picked.isEmpty) return;

      final accepted = [..._attachments];
      var imageBytes = accepted
          .where((attachment) => attachment.isImage)
          .fold<int>(0, (sum, attachment) => sum + attachment.bytes);
      String? problem;

      for (final attachment in picked) {
        if (accepted.length >= kMaxAttachments) {
          problem = 'You can attach up to $kMaxAttachments items.';
          break;
        }
        if (attachment.isImage &&
            imageBytes + attachment.bytes > kMaxImageBytesTotal) {
          problem = 'Images must total under 25 MB.';
          break;
        }
        accepted.add(attachment);
        if (attachment.isImage) imageBytes += attachment.bytes;
      }

      setState(() {
        _attachments = accepted;
        _localError = problem;
        if (accepted.isNotEmpty) _queueDelivery = true;
      });
    } on AttachmentPickerException catch (error) {
      if (mounted) setState(() => _localError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _localError = 'Could not read that attachment.');
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && _attachments.isEmpty) return;

    setState(() {
      _submitting = true;
      _localError = null;
    });

    try {
      final images = _attachments
          .where((attachment) => attachment.isImage)
          .map((attachment) => attachment.image!)
          .toList();
      final resources = _attachments
          .where((attachment) => !attachment.isImage)
          .map((attachment) => attachment.resource!)
          .toList();

      if (_steerEligible) {
        await widget.onSteer(trimmed);
      } else {
        await widget.onSend(
          trimmed,
          attachments: images.isEmpty ? null : images,
          resources: resources.isEmpty ? null : resources,
        );
      }

      if (!mounted) return;
      _controller.clear();
      setState(() => _attachments = []);
      unawaited(CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId)));
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) setState(() => _localError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final hasContent =
        _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;
    final sendDisabled =
        _stopped || widget.pending || _submitting || !hasContent;
    final providerModel = widget.configOptions
        .where(
          (option) =>
              option.category == 'model' ||
              option.id == 'model' ||
              option.id == 'agent',
        )
        .firstOrNull;
    final providerLabel = providerModel?.type == 'select'
        ? providerModel!.choices
                  ?.where(
                    (choice) => choice.value == providerModel.currentValue,
                  )
                  .map((choice) => choice.name)
                  .firstOrNull ??
              providerModel.currentValue
        : null;
    final selectedModel =
        widget.snapshot.modelReroute?.toModel ??
        providerLabel ??
        widget.snapshot.settings.model;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + dockInset(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, _) => const HorizontalSpace(7),
                itemBuilder: (context, index) {
                  final attachment = _attachments[index];
                  final previewBytes = _imageBytes(attachment.image?.data);
                  return Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border.all(color: skin.borderSubtle),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (attachment.isImage && previewBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              previewBytes,
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.image_outlined,
                                size: 14,
                                color: skin.blue,
                              ),
                            ),
                          )
                        else if (attachment.isImage)
                          Icon(Icons.image_outlined, size: 14, color: skin.blue)
                        else
                          Icon(
                            Icons.description_outlined,
                            size: 14,
                            color: skin.blue,
                          ),
                        const HorizontalSpace(6),
                        Flexible(
                          child: AppText(
                            attachment.name,
                            style: AppTextStyle.style11Regular.copyWith(
                              color: skin.textSecondary,
                            ),
                          ),
                        ),
                        const HorizontalSpace(6),
                        InkWell(
                          onTap: () => setState(
                            () => _attachments = _attachments
                                .where((other) => other.id != attachment.id)
                                .toList(),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: skin.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_localError != null || widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 3),
              child: AppText(
                _localError ?? widget.error!,
                style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          Opacity(
            opacity: _stopped ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: skin.bgElevated,
                border: Border.all(color: skin.borderDefault),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !_stopped,
                      maxLines: null,
                      maxLength: 40000,
                      style: AppTextStyle.style15Regular.copyWith(
                        color: skin.textPrimary,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        border: InputBorder.none,
                        hintText: _stopped
                            ? 'Agent is stopped'
                            : _turnRunning
                            ? (_steerEligible
                                  ? 'Agent is working — this goes into its running turn'
                                  : 'Agent is working — this sends when it finishes')
                            : widget.skills.isNotEmpty
                            ? 'Ask the agent…  / for skills, @ for files'
                            : 'Ask the agent…  @ for files',
                        hintStyle: AppTextStyle.style15Regular.copyWith(
                          color: skin.textFaint,
                        ),
                      ),
                    ),
                  ),
                  if (_canSteer) _deliveryChoice(context),
                  Row(
                    children: [
                      _iconButton(
                        context,
                        Icons.attach_file,
                        'Attach image',
                        _stopped ? null : () => _pick(_picker.pickImages),
                      ),
                      if (widget.snapshot.can('embedded_context'))
                        _iconButton(
                          context,
                          Icons.note_add_outlined,
                          'Attach text file',
                          _stopped ? null : () => _pick(_picker.pickTextFiles),
                        ),
                      if (widget.skills.isNotEmpty)
                        _iconButton(
                          context,
                          Icons.terminal,
                          'Skills',
                          _stopped
                              ? null
                              : () =>
                                    _openSuggestions(SuggestionKind.skills, ''),
                        ),
                      if (widget.filePaths.isNotEmpty)
                        _iconButton(
                          context,
                          Icons.alternate_email,
                          'Worktree files',
                          _stopped
                              ? null
                              : () =>
                                    _openSuggestions(SuggestionKind.files, ''),
                        ),
                      Flexible(
                        child: InkWell(
                          onTap: widget.onOpenSettings,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.memory,
                                  size: 13,
                                  color: skin.textTertiary,
                                ),
                                const HorizontalSpace(5),
                                Flexible(
                                  child: AppText(
                                    selectedModel ?? 'Default',
                                    style: AppTextStyle.style10Regular.copyWith(
                                      color: skin.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_turnRunning && _controller.text.trim().isEmpty)
                        _roundButton(
                          context,
                          icon: Icons.stop,
                          background: skin.bgSubtle,
                          foreground: skin.textPrimary,
                          onTap: widget.onInterrupt,
                        )
                      else
                        _roundButton(
                          context,
                          icon: _steerEligible
                              ? Icons.reply
                              : Icons.arrow_upward,
                          background: skin.blue,
                          foreground: skin.onAccent,
                          busy: widget.pending || _submitting,
                          onTap: sendDisabled ? null : _submit,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryChoice(BuildContext context) {
    final skin = context.skin;
    final forced = _attachments.isNotEmpty;

    Widget option(String label, bool queue) {
      final selected = forced ? queue : _queueDelivery == queue;
      final disabled = forced && !queue;
      return Opacity(
        opacity: disabled ? 0.35 : 1,
        child: InkWell(
          onTap: disabled ? null : () => setState(() => _queueDelivery = queue),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? skin.bgSubtle : null,
              borderRadius: BorderRadius.circular(7),
            ),
            child: AppText(
              label,
              style: AppTextStyle.style10SemiBold.copyWith(
                color: selected ? skin.textPrimary : skin.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          option('Steer this turn', false),
          const HorizontalSpace(3),
          option('Queue for next', true),
          if (forced)
            Expanded(
              child: AppText(
                'Attachments start a new turn.',
                style: AppTextStyle.style9Regular.copyWith(
                  color: skin.textFaint,
                ),
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) {
    final skin = context.skin;
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        color: onTap == null ? skin.textFaint : skin.textTertiary,
      ),
    );
  }

  Widget _roundButton(
    BuildContext context, {
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Icon(icon, size: 17, color: foreground),
          ),
        ),
      ),
    );
  }
}
