import 'package:flutter/material.dart';
import 'theme.dart';
import 'models.dart';

class PlateCalculatorDialog extends StatefulWidget {
  final double initialWeight;
  final String exerciseName;
  final String unit;

  const PlateCalculatorDialog({
    super.key,
    required this.initialWeight,
    required this.exerciseName,
    required this.unit,
  });

  @override
  State<PlateCalculatorDialog> createState() => _PlateCalculatorDialogState();
}

class _PlateCalculatorDialogState extends State<PlateCalculatorDialog> {
  late TextEditingController _weightController;
  late double _barWeight;

  @override
  void initState() {
    super.initState();
    final isLbs = widget.unit == 'lbs';
    _weightController = TextEditingController(
      text: widget.initialWeight > 0 ? widget.initialWeight.toStringAsFixed(1) : (isLbs ? '135' : '60'),
    );
    _barWeight = isLbs ? 45.0 : 20.0;
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _calculatePlates(double target, bool isLbs, double bar) {
    final availablePlates = isLbs ? [45.0, 35.0, 25.0, 10.0, 5.0, 2.5] : [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
    double remaining = (target - bar) / 2.0;
    if (remaining <= 0) {
      return {'bar': bar, 'plates': <double>[], 'total': bar, 'rem': 0.0};
    }

    final List<double> plates = [];
    for (final p in availablePlates) {
      while (remaining >= p) {
        plates.add(p);
        remaining = double.parse((remaining - p).toStringAsFixed(2));
      }
    }

    final total = bar + (plates.fold(0.0, (a, b) => a + b) * 2);
    return {'bar': bar, 'plates': plates, 'total': total, 'rem': remaining * 2};
  }

  @override
  Widget build(BuildContext context) {
    final isLbs = widget.unit == 'lbs';
    final target = double.tryParse(_weightController.text) ?? 0.0;
    final calc = _calculatePlates(target, isLbs, _barWeight);
    final List<double> plates = calc['plates'];

    return Dialog(
      backgroundColor: AppTheme.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calculate, color: AppTheme.tertiary),
                    const SizedBox(width: 8),
                    Text(
                      'Plate Calculator',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              widget.exerciseName,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL (${widget.unit.toUpperCase()})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.surfaceLowest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BAR (${widget.unit.toUpperCase()})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLowest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<double>(
                          value: _barWeight,
                          isExpanded: true,
                          underline: const SizedBox(),
                          dropdownColor: AppTheme.surfaceHigh,
                          items: isLbs
                              ? [
                                  const DropdownMenuItem(value: 45.0, child: Text('45 lb Bar', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 35.0, child: Text('35 lb Bar', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 25.0, child: Text('25 lb EZ', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 0.0, child: Text('0 lb Zero', style: TextStyle(fontSize: 13))),
                                ]
                              : [
                                  const DropdownMenuItem(value: 20.0, child: Text('20 kg Bar', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 15.0, child: Text('15 kg Bar', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 10.0, child: Text('10 kg EZ', style: TextStyle(fontSize: 13))),
                                  const DropdownMenuItem(value: 0.0, child: Text('0 kg Zero', style: TextStyle(fontSize: 13))),
                                ],
                          onChanged: (v) {
                            if (v != null) setState(() => _barWeight = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Plates Per Side:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      Text(
                        '${calc['total']} ${widget.unit}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (plates.isEmpty)
                    const Text('Bar only - No extra plates needed.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: plates.map((p) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: p >= 20 ? AppTheme.tertiaryContainer : AppTheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$p ${widget.unit}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseCustomizerDialog extends StatefulWidget {
  final ScheduledExercise exercise;
  final Function(String targetReps, String targetRpe, int restSeconds, String notes) onSave;

  const ExerciseCustomizerDialog({
    super.key,
    required this.exercise,
    required this.onSave,
  });

  @override
  State<ExerciseCustomizerDialog> createState() => _ExerciseCustomizerDialogState();
}

class _ExerciseCustomizerDialogState extends State<ExerciseCustomizerDialog> {
  late TextEditingController _repsController;
  late TextEditingController _rpeController;
  late TextEditingController _restController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _repsController = TextEditingController(text: widget.exercise.targetReps);
    _rpeController = TextEditingController(text: widget.exercise.targetRpe);
    _restController = TextEditingController(text: widget.exercise.restSeconds.toString());
    _notesController = TextEditingController(text: widget.exercise.notes);
  }

  @override
  void dispose() {
    _repsController.dispose();
    _rpeController.dispose();
    _restController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Customize Movement',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              widget.exercise.name,
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('TARGET REP RANGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
            const SizedBox(height: 4),
            TextField(
              controller: _repsController,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceLowest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TARGET RPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _rpeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.surfaceLowest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('REST (SECONDS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _restController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.surfaceLowest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('TEMPO / FORM NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
            const SizedBox(height: 4),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceLowest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryContainer,
                  foregroundColor: AppTheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  widget.onSave(
                    _repsController.text,
                    _rpeController.text,
                    int.tryParse(_restController.text) ?? 90,
                    _notesController.text,
                  );
                  Navigator.pop(context);
                },
                child: const Text('Apply Parameters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
