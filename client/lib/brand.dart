import 'package:flutter/material.dart';

import 'brand_paths.dart';
import 'design.dart';

/// One original vector mark across the app, native icons and launch surfaces.
class MesaBrandMark extends StatelessWidget {
  const MesaBrandMark({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mesa',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _MesaBrandPainter()),
    ),
  );
}

class _MesaBrandPainter extends CustomPainter {
  const _MesaBrandPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 96);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 96, 96),
        const Radius.circular(26),
      ),
      Paint()..color = MesaPalette.green,
    );
    paintMesaSymbol(canvas, const Color(0xFFFFFEFB), const Color(0xFF9ED8B8));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MesaBrandPainter oldDelegate) => false;
}

class MesaWordmark extends StatelessWidget {
  const MesaWordmark({super.key, this.iconSize = 40, this.textSize = 28});
  final double iconSize, textSize;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mesa · recetas para compartir',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MesaBrandMark(size: iconSize),
          const SizedBox(width: 12),
          Text(
            'mesa',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              fontSize: textSize,
              height: 1.1,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A real loading state shown while existing local initialization runs.
/// No timer, advertising or minimum splash delay is introduced.
class MesaLaunchApp extends StatelessWidget {
  const MesaLaunchApp({super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: MesaPalette.scheme(brightness),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? MesaPalette.cream
          : const Color(0xFF171D19),
      fontFamily: 'Segoe UI',
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mesa · Recetario familiar',
      themeMode: ThemeMode.system,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const MesaLaunchPage(),
    );
  }
}

class MesaLaunchPage extends StatelessWidget {
  const MesaLaunchPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MesaBrandMark(size: 88),
              const SizedBox(height: 24),
              Text(
                'mesa',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La cocina que compartes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              if (!MediaQuery.disableAnimationsOf(context))
                const SizedBox(
                  width: 128,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Abriendo tu recetario',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
