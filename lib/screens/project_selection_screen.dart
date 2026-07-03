import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../providers/project_provider.dart';
import '../services/permission_service.dart';
import 'recording_screen.dart';

class ProjectSelectionScreen extends StatefulWidget {
  const ProjectSelectionScreen({super.key});

  @override
  State<ProjectSelectionScreen> createState() => _ProjectSelectionScreenState();
}

class _ProjectSelectionScreenState extends State<ProjectSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().loadProjects();
    });
  }

  Future<void> _onProjectTapped(Project project) async {
    // 1. Prominent data-collection disclosure (required by app stores).
    final consented = await _showDisclosure();
    if (!consented || !mounted) return;

    // 2. Request location + background + notification permissions.
    final result = await PermissionService.requestAll();
    if (!result.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }

    // 3. Download project settings + geofence.
    final ok =
        await context.read<ProjectProvider>().selectProject(project);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const RecordingScreen(),
      ));
    } else {
      final err = context.read<ProjectProvider>().error ?? 'Unknown error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<bool> _showDisclosure() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Data collection notice'),
        content: const SingleChildScrollView(
          child: Text(
            'This app collects your location and motion (accelerometer) data '
            'in the foreground and background during the research session, '
            'and uploads it to the BUas Experience Lab server.\n\n'
            'Data collection only runs while a recording is active. You can '
            'stop it at any time. Continue only if you consent to take part.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I consent'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a project'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.state == LoadState.loading
                ? null
                : () => context.read<ProjectProvider>().loadProjects(),
          ),
        ],
      ),
      body: _buildBody(provider),
    );
  }

  Widget _buildBody(ProjectProvider provider) {
    switch (provider.state) {
      case LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case LoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text(provider.error ?? 'Error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      context.read<ProjectProvider>().loadProjects(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case LoadState.idle:
      case LoadState.ready:
        if (provider.projects.isEmpty) {
          return const Center(child: Text('No active projects found.'));
        }
        return ListView.separated(
          itemCount: provider.projects.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = provider.projects[i];
            return ListTile(
              leading: const Icon(Icons.science_outlined),
              title: Text(p.name),
              subtitle: Text('Project #${p.id}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _onProjectTapped(p),
            );
          },
        );
    }
  }
}
