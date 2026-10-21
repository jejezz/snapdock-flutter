import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../capture/capture_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'capture_thumb.dart';
import 'dock_window.dart';

/// 항상 위에 떠 있는 작은 독. 손잡이를 잡고 끌면 창이 움직인다.
class DockView extends StatefulWidget {
  const DockView({
    super.key,
    required this.controller,
    required this.size,
    required this.onSizeChanged,
    required this.onExpand,
  });

  final CaptureController controller;
  final DockSize size;
  final VoidCallback onSizeChanged;
  final VoidCallback onExpand;

  @override
  State<DockView> createState() => _DockViewState();
}

class _DockViewState extends State<DockView> {
  /// 창 밖으로 나가지 못하는 툴팁 대신, 독 아래 한 줄에 올려 둔 것의 설명을 보여 준다.
  final _hint = ValueNotifier<String?>(null);

  CaptureController get controller => widget.controller;
  DockSize get size => widget.size;

  void _setHint(String? value) => _hint.value = value;

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    DragToMoveArea(
                      child: SizedBox(
                        width: 20,
                        height: double.infinity,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: controller.items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, i) => Align(
                          alignment: Alignment.center,
                          child: CaptureThumb(
                            controller: controller,
                            item: controller.items[i],
                            width: size.width,
                            onHint: _setHint,
                          ),
                        ),
                      ),
                    ),
                    _DockButton(
                      icon: Icons.photo_size_select_large_rounded,
                      label: l10n.dockSizeTooltip,
                      onHint: _setHint,
                      onPressed: widget.onSizeChanged,
                    ),
                    _DockButton(
                      icon: Icons.crop_free_rounded,
                      label: l10n.dockCaptureTooltip,
                      onHint: _setHint,
                      onPressed: controller.busy ? null : controller.capture,
                    ),
                    _DockButton(
                      icon: Icons.open_in_full_rounded,
                      label: l10n.dockExpandTooltip,
                      onHint: _setHint,
                      onPressed: widget.onExpand,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: DockWindow.hintHeight,
                child: ValueListenableBuilder<String?>(
                  valueListenable: _hint,
                  builder: (context, hint, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(
                        hint ?? l10n.captureHotkeyHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
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

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.onHint,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final ValueChanged<String?> onHint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHint(label),
      onExit: (_) => onHint(null),
      child: SizedBox(
        width: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(icon),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: const Size(28, 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button - 2),
            ),
          ),
        ),
      ),
    );
  }
}
