import 'dart:async';

import 'package:flutter/material.dart';

import '../capture/capture_controller.dart';
import '../capture/capture_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 캡처 한 건의 썸네일. 누르면 클립보드에 복사하고, 올리면 ✕가 나타난다.
/// 비율은 4:3 고정이고 이미지는 안에 맞춰 넣는다 (원형 PNG의 투명한 모서리가 그대로 보인다).
class CaptureThumb extends StatefulWidget {
  const CaptureThumb({
    super.key,
    required this.controller,
    required this.item,
    required this.width,
    this.onHint,
  });

  final CaptureController controller;
  final CaptureItem item;
  final double width;

  /// 주면 올려 둔 것의 설명을 툴팁 대신 이쪽으로 보낸다 (독처럼 툴팁이 창 밖으로 못 나가는 곳).
  final ValueChanged<String?>? onHint;

  @override
  State<CaptureThumb> createState() => _CaptureThumbState();
}

class _CaptureThumbState extends State<CaptureThumb> {
  bool _hover = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await widget.controller.copy(widget.item);
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _showMenu(Offset position) async {
    final l10n = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'copy', child: Text(l10n.thumbCopy)),
        PopupMenuItem(value: 'remove', child: Text(l10n.thumbRemove)),
      ],
    );
    switch (choice) {
      case 'copy':
        await _copy();
      case 'remove':
        widget.controller.remove(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final height = widget.width * 0.75;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHint?.call(l10n.thumbCopy);
      },
      onExit: (_) {
        setState(() => _hover = false);
        widget.onHint?.call(null);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _copy,
        onSecondaryTapDown: (d) => _showMenu(d.globalPosition),
        child: SizedBox(
          width: widget.width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.button - 2),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    widget.item.png,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              if (_copied)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(AppRadius.button - 2),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: scheme.onPrimary,
                      size: (widget.width * 0.45).clamp(14, 28),
                    ),
                  ),
                ),
              if (_hover)
                Positioned(
                  top: -6,
                  right: -6,
                  child: MouseRegion(
                    onEnter: (_) => widget.onHint?.call(l10n.thumbRemove),
                    onExit: (_) => widget.onHint?.call(
                      widget.onHint == null ? null : l10n.thumbCopy,
                    ),
                    child: GestureDetector(
                      onTap: () => widget.controller.remove(widget.item),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outline),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 11,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
