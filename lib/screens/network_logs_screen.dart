import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/network_log.dart';

class NetworkLogsScreen extends StatefulWidget {
  const NetworkLogsScreen({super.key});

  @override
  State<NetworkLogsScreen> createState() => _NetworkLogsScreenState();
}

class _NetworkLogsScreenState extends State<NetworkLogsScreen> {
  List<NetworkLog> logs = [];
  String selectedFilter = 'ALL';
  bool isLoading = false;
  int totalCount = 0;

  final filters = [
    'ALL',
    'CONNECT',
    'DISCONNECT',
    'SEND',
    'SEND_FAILED',
    'RECEIVE',
    'FORWARD',
    'ACK',
  ];

  @override
  void initState() {
    super.initState();
    loadLogs();
  }

  Future<void> loadLogs() async {
    setState(() => isLoading = true);

    try {
      final results = await DatabaseHelper.instance.getNetworkLogs(
        eventType: selectedFilter == 'ALL' ? null : selectedFilter,
      );

      final count = await DatabaseHelper.instance.getNetworkLogCount();

      if (!mounted) return;

      setState(() {
        logs = results;
        totalCount = count;
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load logs: $error')));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> exportLogs() async {
    try {
      final allLogs = await DatabaseHelper.instance.getAllNetworkLogs();

      if (allLogs.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No logs to export')));
        return;
      }

      final rows = <List<dynamic>>[
        [
          'id',
          'timestamp',
          'event_type',
          'message_id',
          'device_id',
          'peer_id',
          'hop_count',
          'details',
        ],
        ...allLogs.map(
          (log) => [
            log.id,
            log.timestamp.toUtc().toIso8601String(),
            log.eventType,
            log.messageId,
            log.deviceId,
            log.peerId,
            log.hopCount,
            log.details,
          ],
        ),
      ];

      final csvContent = Csv().encode(rows);

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/network_logs_$timestamp.csv');

      await file.writeAsString(csvContent, flush: true);

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          text: 'MultiHop Messenger Network Logs',
          title: 'Export Network Logs',
        ),
      );
    } on MissingPluginException catch (error) {
      debugPrint('CSV export plugin unavailable: $error');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing unavailable. Restart the application.'),
        ),
      );
    } catch (error) {
      debugPrint('CSV export failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear network logs?'),
        content: const Text(
          'All network logs will be permanently deleted. '
          'Chat messages will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await DatabaseHelper.instance.clearNetworkLogs();
      if (!mounted) return;
      await loadLogs();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to clear logs: $error')));
    }
  }

  IconData eventIcon(String type) {
    switch (type) {
      case 'CONNECT':
        return Icons.bluetooth_connected;
      case 'DISCONNECT':
        return Icons.bluetooth_disabled;
      case 'SEND':
        return Icons.arrow_upward;
      case 'SEND_FAILED':
        return Icons.error_outline;
      case 'RECEIVE':
        return Icons.arrow_downward;
      case 'FORWARD':
        return Icons.alt_route;
      case 'ACK':
        return Icons.check_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  Color eventColor(String type) {
    switch (type) {
      case 'CONNECT':
      case 'ACK':
        return Colors.green;
      case 'SEND':
        return Colors.blue;
      case 'RECEIVE':
        return Colors.teal;
      case 'FORWARD':
        return Colors.orange;
      case 'SEND_FAILED':
      case 'DISCONNECT':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void showLogDetails(NetworkLog log) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(log.eventType),
        content: SingleChildScrollView(
          child: SelectableText(
            'Time: ${log.timestamp.toLocal()}\n'
            'Device: ${log.deviceId}\n'
            'Peer: ${log.peerId ?? "-"}\n'
            'Message: ${log.messageId ?? "-"}\n'
            'Hop count: ${log.hopCount ?? "-"}\n'
            'Details: ${log.details ?? "-"}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Network Logs ($totalCount)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Event filter',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: filters.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        selectedFilter = value;
                        loadLogs();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: isLoading ? null : loadLogs,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Export CSV',
                    onPressed: isLoading ? null : exportLogs,
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Clear logs',
                    onPressed: isLoading ? null : clearLogs,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isLoading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadLogs,
            child: logs.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No network logs yet')),
                    ],
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];

                      return ListTile(
                        leading: Icon(
                          eventIcon(log.eventType),
                          color: eventColor(log.eventType),
                        ),
                        title: Text(log.eventType),
                        subtitle: Text(
                          '${log.timestamp.toLocal()}\n'
                          '${log.details ?? ""}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: log.hopCount == null
                            ? null
                            : Text('Hop ${log.hopCount}'),
                        onTap: () => showLogDetails(log),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
