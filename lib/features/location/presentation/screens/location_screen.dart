import 'package:flutter/material.dart';
import 'package:wakulima/core/theme/app_theme.dart';
import 'package:wakulima/core/widgets/module_scaffold.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Location',
      color: WakulimaColors.location,
      icon: Icons.location_on_outlined,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: WakulimaColors.location,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryBar(color: WakulimaColors.location),
          const SizedBox(height: 16),
          _FilterRow(),
          const SizedBox(height: 12),
          ...List.generate(8, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ListItem(index: i, color: WakulimaColors.location),
          )),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Color color;
  const _SummaryBar({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(child: _Stat(label: 'Today', value: '24')),
        Container(width: 1, height: 40, color: Colors.white24),
        Expanded(child: _Stat(label: 'This week', value: '148')),
        Container(width: 1, height: 40, color: Colors.white24),
        Expanded(child: _Stat(label: 'Pending', value: '3')),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
  ]);
}

class _FilterRow extends StatefulWidget {
  @override
  State<_FilterRow> createState() => _FilterRowState();
}
class _FilterRowState extends State<_FilterRow> {
  int _sel = 0;
  final _filters = const ['All', 'Today', 'This week', 'Pending'];
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: List.generate(_filters.length, (i) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _sel = i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _sel == i ? WakulimaColors.primary700 : WakulimaColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _sel == i ? WakulimaColors.primary700 : WakulimaColors.border),
            ),
            child: Text(_filters[i], style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _sel == i ? Colors.white : WakulimaColors.inkSoft)),
          ),
        ),
      ))),
    );
  }
}

class _ListItem extends StatelessWidget {
  final int index;
  final Color color;
  const _ListItem({required this.index, required this.color});
  @override
  Widget build(BuildContext context) {
    final statuses = ['Pending', 'Completed', 'Active'];
    final statusColors = [
      [const Color(0xFFFEF3CD), const Color(0xFF9A6B00)],
      [const Color(0xFFEAF9EF), const Color(0xFF1A8F33)],
      [const Color(0xFFE8F4FD), const Color(0xFF1565C0)],
    ];
    final si = index % 3;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WakulimaColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WakulimaColors.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text('#${index + 1}', style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: color))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Record ${1000 + index}', style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: WakulimaColors.ink)),
          Text('Mar ${14 - index}, 2026 · Pending review', style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: WakulimaColors.inkMuted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColors[si][0], borderRadius: BorderRadius.circular(20)),
          child: Text(statuses[si], style: TextStyle(
            fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
            color: statusColors[si][1])),
        ),
      ]),
    );
  }
}
