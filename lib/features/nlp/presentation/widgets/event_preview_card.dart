import 'package:flutter/material.dart';
import '../../domain/entities/ai_scheduling_response.dart';

class EventPreviewCard extends StatelessWidget {
  final AiSchedulingResponse aiResponse;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;

  const EventPreviewCard({
    Key? key,
    required this.aiResponse,
    required this.onConfirm,
    required this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proposed Event',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            if (aiResponse.eventTitleTokenized != null)
              Text('Title: \${aiResponse.eventTitleTokenized}'), // In reality, this should be hydrated
            if (aiResponse.startTime != null)
              Text('Time: \${aiResponse.startTime}'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
                ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text('Confirm'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
