import 'package:flutter/material.dart';

abstract final class MesaPalette {
  static const green = Color(0xFF25634B);
  static const cream = Color(0xFFF6F7F2);
  static const clay = Color(0xFFA54F32);

  static ColorScheme scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(
      seedColor: green,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF9ED8B8) : green,
      onPrimary: dark ? const Color(0xFF083821) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF254F3B)
          : const Color(0xFFE1EFE6),
      onPrimaryContainer: dark
          ? const Color(0xFFCAEDD7)
          : const Color(0xFF123B2B),
      secondary: dark ? const Color(0xFFFFB68F) : clay,
      onSecondary: dark ? const Color(0xFF4A2411) : Colors.white,
      secondaryContainer: dark
          ? const Color(0xFF663820)
          : const Color(0xFFFFE3D3),
      onSecondaryContainer: dark
          ? const Color(0xFFFFDBC8)
          : const Color(0xFF4A2411),
      surface: dark ? const Color(0xFF1D2923) : const Color(0xFFFFFEFB),
      onSurface: dark ? const Color(0xFFEDF3ED) : const Color(0xFF242B26),
      onSurfaceVariant: dark
          ? const Color(0xFFBBC8BD)
          : const Color(0xFF515C53),
      outline: dark ? const Color(0xFF87968B) : const Color(0xFF757E77),
    );
  }
}

abstract final class MesaShape {
  static const button = 26.0;
  static const field = 24.0;
  static const card = 28.0;
  static const dialog = 32.0;
}

abstract final class MesaMotion {
  static const quick = Duration(milliseconds: 180);
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : quick;
}

/// Consistent hierarchy without giving every screen another toolbar.
class MesaPageHeader extends StatelessWidget {
  const MesaPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    ),
  );
}

/// Mouse/focus feedback and touch ink use the same rounded surface.
class MesaInteractiveCard extends StatefulWidget {
  const MesaInteractiveCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<MesaInteractiveCard> createState() => _MesaInteractiveCardState();
}

class MesaNavigationItem extends StatelessWidget {
  const MesaNavigationItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: MesaMotion.duration(context),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  IconTheme(
                    data: IconThemeData(
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? colors.primary : colors.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MesaInteractiveCardState extends State<MesaInteractiveCard> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highlighted = widget.onTap != null && (hovered || focused);
    return AnimatedContainer(
      duration: MesaMotion.duration(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MesaShape.card),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ]
            : [],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MesaShape.card),
          side: BorderSide(
            color: highlighted
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: .35),
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => hovered = value),
          onFocusChange: (value) => setState(() => focused = value),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shared spacing in logical pixels for touch, mouse and enlarged text.
abstract final class MesaSpace {
  static const small = 8.0;
  static const control = 12.0;
  static const card = 16.0;
  static const section = 24.0;
  static const page = 32.0;
  static const target = 48.0;
  static const readingWidth = 1200.0;
  static double inset(double width) => width < 600 ? card : page;
}

class ReadingWidth extends StatelessWidget {
  const ReadingWidth({
    super.key,
    required this.child,
    this.maxWidth = MesaSpace.readingWidth,
  });
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

class RecipeSection extends StatelessWidget {
  const RecipeSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: MesaSpace.small),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: MesaSpace.control,
          runSpacing: MesaSpace.small,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: MesaSpace.card),
        ...children,
      ],
    ),
  );
}
