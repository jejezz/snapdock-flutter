import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../capture/capture_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'capture_thumb.dart';
import 'dock_window.dart';

/// 항상 위에 떠 있는 작은 독. 손잡이를 잡고 끌면 창이 움직인다.
class DockView extends StatelessWidget {
  const DockView({super.key, required this.controller, required this.size, required this.onSizeChanged, required this.onExpand});

  final CaptureController controller;
  final DockSize size;
  final VoidCallback onSizeChanged;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(
            children: [
              DragToMoveArea(
                child: SizedBox(
                  width: 20,
                  height: double.infinity,
                  child: Icon(Icons.drag_indicator_rounded, size: 16, color: scheme.onSurfaceVariant),
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
                    child: CaptureThumb(controller: controller, item: controller.items[i], width: size.width),
                  ),
                ),
              ),
              _DockButton(
                icon: Icons.photo_size_select_large_rounded,
                tooltip: l10n.dockSizeTooltip,
                onPressed: onSizeChanged,
              ),
              _DockButton(
                icon: Icons.crop_free_rounded,
                tooltip: '${l10n.dockCaptureTooltip} (${l10n.captureHotkeyHint})',
                onPressed: controller.busy ? null : controller.capture,
              ),
              _DockButton(
                icon: Icons.open_in_full_rounded,
                tooltip: l10n.dockExpandTooltip,
                onPressed: onExpand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(28, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button - 2)),
        ),
      ),
    );
  }
}
