import 'package:flutter/material.dart';

class CounterWidget extends StatelessWidget {
  final int count;
  final VoidCallback onIncrement;
  const CounterWidget({super.key, required this.count, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Counter',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onIncrement,
          child: const Text('Increment'),
        ),
      ],
    );
  }
}
