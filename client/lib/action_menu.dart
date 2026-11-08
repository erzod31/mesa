import 'package:flutter/material.dart';

class MesaMenuAction {
  const MesaMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.group = '',
    this.enabled = true,
    this.destructive = false,
    this.shortcut,
  });
  final String id, label, group;
  final IconData icon;
  final bool enabled, destructive;
  final String? shortcut;
}

/// Commands retain the same order and permissions on both surfaces:
/// reachable sheet on narrow windows, anchored keyboard menu on wide ones.
class MesaActionMenuButton extends StatelessWidget {
  const MesaActionMenuButton({
    super.key,
    required this.title,
    required this.actions,
    required this.onSelected,
    this.label,
    this.tooltip = 'Más acciones',
    this.icon = Icons.more_horiz_rounded,
    this.primary = false,
  });
  final String title, tooltip;
  final String? label;
  final IconData icon;
  final bool primary;
  final List<MesaMenuAction> actions;
  final ValueChanged<String> onSelected;

  Widget trigger(VoidCallback open) {
    if (label == null) {
      return IconButton(tooltip: tooltip, onPressed: open, icon: Icon(icon));
    }
    return Tooltip(
      message: tooltip,
      child: primary
          ? FilledButton.icon(
              onPressed: open,
              icon: Icon(icon),
              label: Text(label!),
            )
          : FilledButton.tonalIcon(
              onPressed: open,
              icon: Icon(icon),
              label: Text(label!),
            ),
    );
  }

  Future<void> openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: () => Navigator.pop(sheet),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (actions[i].group.isNotEmpty &&
                        (i == 0 || actions[i].group != actions[i - 1].group))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Semantics(
                          header: true,
                          child: Text(
                            actions[i].group,
                            style: TextStyle(
                              color: Theme.of(sheet)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ListTile(
                      enabled: actions[i].enabled,
                      minTileHeight: 56,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      leading: Icon(actions[i].icon),
                      iconColor: actions[i].destructive
                          ? Theme.of(sheet).colorScheme.error
                          : null,
                      textColor: actions[i].destructive
                          ? Theme.of(sheet).colorScheme.error
                          : null,
                      title: Text(actions[i].label),
                      onTap: actions[i].enabled
                          ? () => Navigator.pop(sheet, actions[i].id)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return trigger(() => openSheet(context));
    }
    return MenuAnchor(
      menuChildren: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0 && actions[i].group != actions[i - 1].group)
            const Divider(height: 12),
          MenuItemButton(
            autofocus: i == actions.indexWhere((action) => action.enabled),
            onPressed: actions[i].enabled
                ? () => onSelected(actions[i].id)
                : null,
            leadingIcon: Icon(actions[i].icon, size: 20),
            trailingIcon: actions[i].shortcut == null
                ? null
                : Text(actions[i].shortcut!),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(200, 48)),
              foregroundColor: actions[i].destructive
                  ? WidgetStatePropertyAll(Theme.of(context).colorScheme.error)
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(actions[i].label),
            ),
          ),
        ],
      ],
      builder: (context, controller, child) => trigger(() {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      }),
    );
  }
}
