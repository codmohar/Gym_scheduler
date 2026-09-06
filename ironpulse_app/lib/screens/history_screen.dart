import 'package:flutter/material.dart';
import '../theme.dart';
import '../models.dart';
import '../db_helper.dart';

class HistoryScreen extends StatefulWidget {
  final Function(String message)? onShowToast;

  const HistoryScreen({super.key, this.onShowToast});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutSession> _sessions = [];
  Map<String, dynamic> _telemetry = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await DatabaseHelper.instance.getWorkoutHistory();
    final telemetry = await DatabaseHelper.instance.getTelemetryStats();
    setState(() {
      _sessions = history;
      _telemetry = telemetry;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalVol = (_telemetry['total_volume'] as num?)?.toDouble() ?? 0.0;
    final totalSessions = _telemetry['total_sessions'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History & Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryContainer))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Telemetry Deck
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.surfaceHigh),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.fitness_center, color: AppTheme.primary, size: 14),
                                  SizedBox(width: 4),
                                  Text('TONNAGE', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(totalVol.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text('Total Volume', style: TextStyle(color: AppTheme.secondary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.surfaceHigh),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.bolt, color: AppTheme.tertiary, size: 14),
                                  SizedBox(width: 4),
                                  Text('SESSIONS', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('$totalSessions', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text('Completed', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.surfaceHigh),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.military_tech, color: AppTheme.primaryContainer, size: 14),
                                  SizedBox(width: 4),
                                  Text('PR HITS', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('$totalSessions', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              const Text('Target Load', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Session Feed
                  const Text('LOGGED WORKOUTS ARCHIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                  const SizedBox(height: 10),

                  if (_sessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.calendar_month, color: AppTheme.textMuted, size: 36),
                            SizedBox(height: 8),
                            Text('No Completed Workouts Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            SizedBox(height: 4),
                            Text('Log and finish your first training session to view history.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sessions.length,
                      itemBuilder: (context, idx) {
                        final s = _sessions[idx];
                        final durationMin = s.durationSeconds ~/ 60;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.surfaceHigh),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          s.date.split('T')[0],
                                          style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(width: 8),
                                        Text('• $durationMin min', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        Text(
                                          '• ${s.totalVolume.toStringAsFixed(0)} ${s.unit}',
                                          style: const TextStyle(color: AppTheme.secondary, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 20),
                                onPressed: () async {
                                  if (s.id != null) {
                                    await DatabaseHelper.instance.deleteSession(s.id!);
                                    _loadHistory();
                                    if (widget.onShowToast != null) {
                                      widget.onShowToast!('Workout log deleted');
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
