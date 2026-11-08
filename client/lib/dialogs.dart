import 'package:flutter/material.dart';

/// DialogRoute completes its Future before its closing animation unmounts.
/// Controllers must therefore belong to the mounted dialog, not its caller.
class ManagedDialogBuilder extends StatefulWidget {
  const ManagedDialogBuilder({
    super.key,
    required this.controllers,
    required this.builder,
  });
  final List<TextEditingController> controllers;
  final StatefulWidgetBuilder builder;
  @override
  State<ManagedDialogBuilder> createState() => _ManagedDialogBuilderState();
}

class _ManagedDialogBuilderState extends State<ManagedDialogBuilder> {
  void update(VoidCallback change) {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) setState(change);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, update);
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
