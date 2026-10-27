/// Shared chrome for the demo pages: a dark scaffold, an info card, and a row
/// of chips pinned to the bottom.
///
/// Kept deliberately plain — the point of the gallery is the map, not the UI.
library;

import 'package:flutter/material.dart';

const Color kDemoBackground = Color(0xFF0E1116);
const Color kDemoPanel = Color(0xCC151A21);

/// A demo screen: the map fills the body, with a title/hint card on top and
/// optional controls at the bottom.
class DemoScaffold extends StatelessWidget {
  const DemoScaffold({
    required this.title,
    required this.hint,
    required this.child,
    this.detail,
    this.controls = const [],
    super.key,
  });

  final String title;

  /// What the demo is meant to prove.
  final String hint;

  /// Live state (diagnostics, camera…), refreshed by the page.
  final String? detail;

  final Widget child;
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDemoBackground,
      appBar: AppBar(
        backgroundColor: kDemoBackground,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kDemoPanel,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hint,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          detail!,
                          style: const TextStyle(
                            color: Color(0xFF7FDCA4),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (controls.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                // Horizontal scroll: four chips plus a phone width is more than
                // fits, and a clipped toggle is worse than a scrollable one.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kDemoPanel,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: controls),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact toggle chip for the bottom bar.
class DemoChip extends StatelessWidget {
  const DemoChip({
    required this.label,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          onSelected: onChanged,
          visualDensity: VisualDensity.compact,
          labelStyle: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
          ),
          selectedColor: const Color(0xFF7FDCA4),
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: Colors.white24),
          checkmarkColor: Colors.black,
        ),
      );
}
