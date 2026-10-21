import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_drag_out/flutter_drag_out.dart';

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
    _flashCheck();
  }

  Future<void> _save() async {
    await widget.controller.save(widget.item);
    _flashCheck();
  }

  void _flashCheck() {
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
        PopupMenuItem(value: 'save', child: Text(l10n.thumbSave)),
        PopupMenuItem(value: 'remove', child: Text(l10n.thumbRemove)),
      ],
    );
    switch (choice) {
      case 'copy':
        await _copy();
      case 'save':
        await _save();
      case 'remove':
        widget.controller.remove(widget.item);
    }
  }

  /// 앱 안에서는 일반 [Draggable]이고, 포인터가 창 밖으로 나가는 순간 OS 드래그로 넘어가
  /// 파일(이미지는 PNG, 영상·GIF는 그 파일)이 다른 앱으로 끌려 나간다.
  @override
  Widget build(BuildContext context) {
    final tile = _buildTile(context);
    final viewSize = MediaQuery.sizeOf(context);
    final item = widget.item;
    return Draggable<CaptureItem>(
      data: item,
      onDragUpdate: (details) => FlutterDragOut.maybeStartOnExit(
        details.globalPosition,
        viewSize: viewSize,
        paths: () => File(item.path).existsSync() ? [item.path] : null,
      ),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.85, child: SizedBox(width: widget.width, height: widget.width * 0.75, child: _preview())),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }

  Widget _preview() => Image.file(
        File(widget.item.previewPath),
        fit: BoxFit.contain,
        cacheWidth: (widget.width * 3).round(),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );

  Widget _buildTile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final height = widget.width * 0.75;
    final tint = switch (widget.item.kind) {
      CaptureKind.image => scheme.primary,
      CaptureKind.video => AppColors.accent,
      CaptureKind.gif => AppColors.success,
    };
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
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.button - 2),
                    border: Border.all(
                      color: widget.item.kind == CaptureKind.image
                          ? scheme.outlineVariant
                          : tint.withValues(alpha: 0.6),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _preview(),
                ),
              ),
              if (widget.item.kind != CaptureKind.image)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: _KindBadge(item: widget.item),
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

/// 방금 찍은 캡처가 독에 들어올 때 살짝 커지며 나타나게 한다. 오래된 항목은 그냥 보여 준다.
class CaptureEntrance extends StatelessWidget {
  const CaptureEntrance({super.key, required this.item, required this.child});

  final CaptureItem item;
  final Widget child;

  static const _fresh = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    if (DateTime.now().difference(item.createdAt) > _fresh) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
    );
  }
}

/// 영상은 길이(`0:07`), GIF는 `GIF`를 모서리에 단다.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.item});

  final CaptureItem item;

  @override
  Widget build(BuildContext context) {
    final label = item.kind == CaptureKind.gif ? 'GIF' : _format(item.duration);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          height: 1.1,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  static String _format(Duration? d) {
    final seconds = ((d?.inMilliseconds ?? 0) / 1000).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
