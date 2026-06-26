import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class RequestScreen extends StatelessWidget {
  const RequestScreen({
    super.key,
    required this.isConfigured,
    this.onSidebarActivate,
  });

  final bool isConfigured;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    if (!isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request Content')),
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      body: DpadRegion(
        memoryKey: 'requests/placeholder',
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) onSidebarActivate?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Content',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your server admin to add movies, shows, or channels.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: MediaBrowsingMetrics.contentPadding),
              Expanded(
                child: Center(
                  child: Text(
                    'Full request workflow coming soon.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
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
