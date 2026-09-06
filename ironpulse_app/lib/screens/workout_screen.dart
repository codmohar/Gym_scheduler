import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models.dart';
import '../db_helper.dart';
import '../dialogs.dart';

class WorkoutScreen extends StatefulWidget {
  final Function(String message)? onShowToast;
  final Function()? onOpenExercises;

  const WorkoutScreen({
    super.key,
    this.onShowToast,
    this.onOpenExercises,
  });

  @override
  State<WorkoutScreen> createState() => WorkoutScreenState();
}

class WorkoutScreenState extends State<WorkoutScreen> {
  List<RoutineSplit> _splits = PresetRoutines.getAllPresets();
  int _selectedSplitIndex = 0;
  int _selectedDayIndex = 0;
  String _unit = 'kg';

  List<ScheduledExercise> _exercises = [];
  bool _isRestMode = false;
  bool _isLoading = true;

  // Elapsed Timer
  Timer? _workoutTimer;
  int _elapsedSeconds = 0;

  // Rest Timer Overlay
  Timer? _restTimer;
  int _restRemainingSeconds = 0;
  bool _isRestTimerActive = false;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }

  /// Synchronize the current UI state of exercises into the active day's configs
  void _syncCurrentDayConfigs() {
    if (_splits.isEmpty || _selectedSplitIndex >= _splits.length) return;
    final split = _splits[_selectedSplitIndex];
    if (_selectedDayIndex >= split.days.length) return;
    final day = split.days[_selectedDayIndex];

    for (final ex in _exercises) {
      day.exerciseConfigs[ex.exerciseId] = ex.toConfigMap();
    }
  }

  /// Save all splits and current configurations to persistent storage
  Future<void> _saveUserSplitsOverride() async {
    _syncCurrentDayConfigs();
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> splitsJson = _splits.map((s) => s.toMap()).toList();
    await prefs.setString('user_splits_override', json.encode(splitsJson));
  }

  /// Load initial state following the user flow:
  /// Check saved data -> If exists, load edited data -> Else use default data
  Future<void> _loadInitialState() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _unit = prefs.getString('unit') ?? 'kg';
    _selectedSplitIndex = prefs.getInt('selected_split') ?? 0;
    _selectedDayIndex = prefs.getInt('selected_day') ?? 0;

    final overrideJson = prefs.getString('user_splits_override');
    if (overrideJson != null && overrideJson.isNotEmpty) {
      try {
        final decoded = json.decode(overrideJson);
        if (decoded is List) {
          final List<RoutineSplit> loadedSplits = [];
          for (final item in decoded) {
            if (item is Map) {
              loadedSplits.add(RoutineSplit.fromMap(Map<String, dynamic>.from(item)));
            }
          }
          if (loadedSplits.isNotEmpty) {
            _splits = loadedSplits;
          }
        } else if (decoded is Map) {
          // Compatibility with older map format
          for (final split in _splits) {
            if (decoded.containsKey(split.id)) {
              final List<dynamic> daysList = decoded[split.id];
              for (int i = 0; i < daysList.length && i < split.days.length; i++) {
                final dMap = daysList[i] as Map<String, dynamic>;
                final d = split.days[i];
                d.isRest = dMap['isRest'] as bool? ?? d.isRest;
                d.exerciseIds = List<String>.from(dMap['exerciseIds'] ?? d.exerciseIds);
              }
            }
          }
        }
      } catch (e) {
        // Fallback to default presets
        _splits = PresetRoutines.getAllPresets();
      }
    } else {
      // Default data
      _splits = PresetRoutines.getAllPresets();
    }

    if (_selectedSplitIndex >= _splits.length) _selectedSplitIndex = 0;
    if (_selectedDayIndex >= _splits[_selectedSplitIndex].days.length) _selectedDayIndex = 0;

    await _loadDayWorkout(_selectedDayIndex, saveSelection: false);

    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  Future<void> _loadDayWorkout(int dayIndex, {bool saveSelection = true}) async {
    setState(() => _isLoading = true);
    _syncCurrentDayConfigs();

    _selectedDayIndex = dayIndex;
    final currentSplit = _splits[_selectedSplitIndex];
    if (dayIndex >= currentSplit.days.length) {
      _selectedDayIndex = 0;
    }
    final day = currentSplit.days[_selectedDayIndex];
    _isRestMode = day.isRest;

    final List<ScheduledExercise> loaded = [];
    final allEx = await DatabaseHelper.instance.getAllExercises();
    final exMap = {for (var e in allEx) e.id: e};

    for (final exId in day.exerciseIds) {
      final exObj = exMap[exId];
      if (exObj == null) continue;

      final prevData = await DatabaseHelper.instance.getPreviousPerformance(exId);
      final hasHistory = prevData['hasHistory'] as bool;
      final savedWeight = (prevData['last_weight'] as num).toDouble();
      final savedReps = prevData['last_reps'] as int;

      // Check if user previously saved custom sets/configs for this exercise
      final savedConfig = day.exerciseConfigs[exId];

      List<WorkoutSet> sets = [];
      if (savedConfig != null && savedConfig.containsKey('sets') && savedConfig['sets'] is List && (savedConfig['sets'] as List).isNotEmpty) {
        final List sList = savedConfig['sets'];
        sets = sList.map((s) => WorkoutSet.fromDraftMap(Map<String, dynamic>.from(s as Map))).toList();
      } else {
        // Default 3 sets
        for (int s = 1; s <= 3; s++) {
          sets.add(WorkoutSet(
            setNumber: s,
            weight: hasHistory ? savedWeight : 0.0,
            reps: hasHistory ? savedReps : 0,
            completed: false,
            prevWeight: hasHistory ? savedWeight : null,
            prevReps: hasHistory ? savedReps : null,
          ));
        }
      }

      final scheduled = ScheduledExercise(
        exerciseId: exObj.id,
        name: exObj.name,
        muscleGroup: exObj.muscleGroup,
        modality: exObj.modality,
        hasHistory: hasHistory,
        prevWeight: savedWeight,
        prevReps: savedReps,
        sets: sets,
      );

      if (savedConfig != null) {
        scheduled.applyConfig(savedConfig);
      }

      loaded.add(scheduled);
    }

    setState(() {
      _exercises = loaded;
      _isLoading = false;
    });

    if (saveSelection) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('selected_day', _selectedDayIndex);
      await prefs.setInt('selected_split', _selectedSplitIndex);
    }
  }

  /// Public method to add an exercise to a specific day (defaults to current day)
  Future<void> addExerciseToDay(Exercise ex, [int? dayIndex]) async {
    final targetDayIdx = dayIndex ?? _selectedDayIndex;
    final currentSplit = _splits[_selectedSplitIndex];
    if (targetDayIdx >= currentSplit.days.length) return;
    final day = currentSplit.days[targetDayIdx];

    if (!day.exerciseIds.contains(ex.id)) {
      day.exerciseIds.add(ex.id);
    }

    if (day.isRest) {
      day.isRest = false;
      if (targetDayIdx == _selectedDayIndex) {
        _isRestMode = false;
      }
    }

    await _saveUserSplitsOverride();

    if (targetDayIdx == _selectedDayIndex) {
      await _loadDayWorkout(_selectedDayIndex, saveSelection: false);
    } else {
      setState(() {});
    }

    _showToast('Added "${ex.name}" to ${day.day} (${day.name})');
  }

  /// Open in-app exercise picker modal
  void _openAddExercisePicker() async {
    final allEx = await DatabaseHelper.instance.getAllExercises();
    if (!mounted) return;

    final currentSplit = _splits[_selectedSplitIndex];
    final currentDay = currentSplit.days[_selectedDayIndex];

    String searchQuery = '';
    String selectedMuscle = 'All';
    String? selectedModality;

    final muscleGroups = [
      'All',
      'Chest',
      'Back',
      'Shoulders',
      'Biceps',
      'Triceps',
      'Forearms',
      'Neck',
      'Core',
      'Legs',
      'Calves',
      'Full Body',
    ];

    final modalities = [
      'Free Weights',
      'Calisthenics',
      'Cables & Machines',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = allEx.where((ex) {
              final matchesQ = searchQuery.isEmpty ||
                  ex.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                  ex.secondaryMuscles.any((m) => m.toLowerCase().contains(searchQuery.toLowerCase()));

              final matchesM = selectedMuscle == 'All' ||
                  ex.muscleGroup.toLowerCase().contains(selectedMuscle.toLowerCase());

              final matchesMod = selectedModality == null ||
                  ex.modality.toLowerCase() == selectedModality!.toLowerCase();

              return matchesQ && matchesM && matchesMod;
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHighest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Add Exercise to Workout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                              Text('Target: ${currentDay.day} • ${currentDay.name}', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textMuted),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Search input
                      TextField(
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search 187+ movements...',
                          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                          filled: true,
                          fillColor: AppTheme.surfaceHigh,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) {
                          setModalState(() => searchQuery = v);
                        },
                      ),
                      const SizedBox(height: 8),

                      // Muscle filter chips
                      SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: muscleGroups.length,
                          itemBuilder: (_, idx) {
                            final g = muscleGroups[idx];
                            final isSel = g == selectedMuscle;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(g),
                                selected: isSel,
                                selectedColor: AppTheme.primaryContainer,
                                backgroundColor: AppTheme.surfaceHigh,
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? AppTheme.onPrimary : AppTheme.textMuted,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => selectedMuscle = g);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Modality filter chips
                      SizedBox(
                        height: 32,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: modalities.length,
                          itemBuilder: (_, idx) {
                            final mod = modalities[idx];
                            final isSel = mod == selectedModality;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(mod),
                                selected: isSel,
                                selectedColor: AppTheme.tertiaryContainer,
                                backgroundColor: AppTheme.surfaceLowest,
                                labelStyle: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.black : AppTheme.textMuted,
                                ),
                                onSelected: (sel) {
                                  setModalState(() => selectedModality = sel ? mod : null);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Results count & custom action
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${filtered.length} Exercises Available', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              if (widget.onOpenExercises != null) {
                                widget.onOpenExercises!();
                              }
                            },
                            child: const Text('+ Custom Catalog', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // List
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('No exercises found', style: TextStyle(color: AppTheme.textMuted)))
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (_, idx) {
                                  final ex = filtered[idx];
                                  final alreadyAdded = currentDay.exerciseIds.contains(ex.id);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: alreadyAdded ? AppTheme.surfaceLowest : AppTheme.surfaceHigh,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: alreadyAdded ? AppTheme.primary.withValues(alpha: 0.3) : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: AppTheme.surfaceHighest,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            alreadyAdded ? Icons.check : Icons.fitness_center,
                                            color: alreadyAdded ? AppTheme.secondary : AppTheme.primary,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ex.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${ex.muscleGroup.toUpperCase()} • ${ex.modality.toUpperCase()}',
                                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (alreadyAdded)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.secondaryContainer.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text('ADDED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                                          )
                                        else
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.primaryContainer,
                                              foregroundColor: AppTheme.onPrimary,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            icon: const Icon(Icons.add, size: 14),
                                            label: const Text('ADD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            onPressed: () async {
                                              await addExerciseToDay(ex);
                                              setModalState(() {});
                                            },
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _startRestTimer(int seconds) {
    _restTimer?.cancel();
    setState(() {
      _restRemainingSeconds = seconds;
      _isRestTimerActive = true;
    });

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_restRemainingSeconds > 0) {
        setState(() => _restRemainingSeconds--);
      } else {
        _restTimer?.cancel();
        setState(() => _isRestTimerActive = false);
        _showToast('Rest completed! Time for next set.');
      }
    });
  }

  void _showToast(String msg) {
    if (widget.onShowToast != null) {
      widget.onShowToast!(msg);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.surfaceHighest,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatTimer(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentSplit = _splits[_selectedSplitIndex];
    final currentDay = currentSplit.days[_selectedDayIndex];
    final isLbs = _unit == 'lbs';
    final weightStep = isLbs ? 5.0 : 2.5;

    int totalSets = 0;
    for (var ex in _exercises) {
      totalSets += ex.sets.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.fitness_center, color: AppTheme.primaryContainer, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IronPulse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
                Text('Resistance & Workout', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (_unit == 'kg') return;
                    setState(() => _unit = 'kg');
                    final p = await SharedPreferences.getInstance();
                    await p.setString('unit', 'kg');
                    _showToast('Switched to Metric (KG)');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _unit == 'kg' ? AppTheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'KG',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _unit == 'kg' ? AppTheme.onPrimary : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    if (_unit == 'lbs') return;
                    setState(() => _unit = 'lbs');
                    final p = await SharedPreferences.getInstance();
                    await p.setString('unit', 'lbs');
                    _showToast('Switched to Imperial (LBS)');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _unit == 'lbs' ? AppTheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'LBS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _unit == 'lbs' ? AppTheme.onPrimary : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryContainer))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Workout & Weekly Routine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryContainer.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primaryContainer.withValues(alpha: 0.3)),
                            ),
                            child: const Text('MESOCYCLE WK 3', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text('7-Day athletic progression • Tap to switch days', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      const SizedBox(height: 12),

                      // Split Routine Pills (PPL, Upper/Lower, Full Body, Bro Split)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(_splits.length, (idx) {
                            final split = _splits[idx];
                            final isSelected = idx == _selectedSplitIndex;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(split.name.toUpperCase()),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryContainer,
                                backgroundColor: AppTheme.surfaceHigh,
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppTheme.onPrimary : AppTheme.textMuted,
                                ),
                                onSelected: (sel) async {
                                  if (sel) {
                                    setState(() => _selectedSplitIndex = idx);
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setInt('selected_split', idx);
                                    await _loadDayWorkout(0);
                                  }
                                },
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 7-Day Week Segment Strip (MON - SUN)
                      Row(
                        children: List.generate(currentSplit.days.length, (idx) {
                          final d = currentSplit.days[idx];
                          final isSelected = idx == _selectedDayIndex;
                          final isRest = d.isRest;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _loadDayWorkout(idx),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.surfaceHighest
                                      : (isRest ? AppTheme.surfaceLowest : AppTheme.surface),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? AppTheme.primaryContainer : Colors.transparent,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      d.day,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? AppTheme.primary : AppTheme.textMain,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isRest ? 'REST' : d.name.split(' ')[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                        color: isRest ? AppTheme.tertiary : AppTheme.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.primaryContainer : AppTheme.surfaceHigh,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isRest ? 'Zz' : '${d.exerciseIds.length} EX',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? AppTheme.onPrimary : AppTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),

                      // Target Session Header Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.surfaceHigh),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    CircleAvatar(radius: 4, backgroundColor: AppTheme.primary),
                                    SizedBox(width: 6),
                                    Text('TARGET SESSION', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceHigh,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.timer, size: 14, color: AppTheme.tertiary),
                                      const SizedBox(width: 4),
                                      Text(_formatTimer(_elapsedSeconds), style: const TextStyle(color: AppTheme.tertiary, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left, color: AppTheme.textMain, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    final totalDays = currentSplit.days.length;
                                    final prevIdx = (_selectedDayIndex - 1 + totalDays) % totalDays;
                                    _loadDayWorkout(prevIdx);
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${currentDay.day} • ${currentDay.name}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right, color: AppTheme.textMain, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    final totalDays = currentSplit.days.length;
                                    final nextIdx = (_selectedDayIndex + 1) % totalDays;
                                    _loadDayWorkout(nextIdx);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Telemetry row
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLowest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('MOVEMENTS', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                        Text('${_exercises.length} Items', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('VOLUME LOAD', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                        Text('$totalSets Sets', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('EST. DURATION', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                        Text('~${totalSets * 3} min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Switch(
                                      value: _isRestMode,
                                      activeThumbColor: AppTheme.primaryContainer,
                                      onChanged: (val) async {
                                        setState(() {
                                          _isRestMode = val;
                                          currentDay.isRest = val;
                                        });
                                        await _saveUserSplitsOverride();
                                        _showToast(val ? 'Rest day activated' : 'Active training mode');
                                      },
                                    ),
                                    const Text('REST DAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryContainer,
                                    foregroundColor: AppTheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.add_circle, size: 16),
                                  label: const Text('ADD EXERCISE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  onPressed: _openAddExercisePicker,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Exercises List or Rest View
                      if (_isRestMode)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.hotel, color: AppTheme.tertiary, size: 40),
                              const SizedBox(height: 10),
                              const Text('Scheduled Rest & CNS Recovery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              const Text('Sleep goal: 8.5 hrs • 30 min light mobility walk', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: const BorderSide(color: AppTheme.primary),
                                ),
                                icon: const Icon(Icons.bolt, size: 18),
                                label: const Text('Convert to Active Workout'),
                                onPressed: () async {
                                  setState(() {
                                    _isRestMode = false;
                                    currentDay.isRest = false;
                                  });
                                  await _saveUserSplitsOverride();
                                  _showToast('Converted to active workout session');
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _exercises.length,
                          itemBuilder: (context, exIdx) {
                            final ex = _exercises[exIdx];
                            final hasHist = ex.hasHistory || ex.sets.any((s) => s.completed);
                            final lastW = ex.prevWeight;
                            final lastR = ex.prevReps;
                            final overloadText = (lastW > 0 || lastR > 0)
                                ? 'OVERLOAD: +$weightStep $_unit (PREV: ${lastW.toStringAsFixed(1)} $_unit × $lastR)'
                                : 'TARGET: PROGRESSIVE OVERLOAD (PREV: --)';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.surfaceHigh),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Exercise Card Header
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    ex.name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.surfaceHighest,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '${ex.muscleGroup.toUpperCase()} • ${ex.modality.toUpperCase()}',
                                                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                GestureDetector(
                                                  onTap: () {
                                                    showDialog(
                                                      context: context,
                                                      builder: (_) => ExerciseCustomizerDialog(
                                                        exercise: ex,
                                                        onSave: (reps, rpe, rest, notes) async {
                                                          setState(() {
                                                            ex.targetReps = reps;
                                                            ex.targetRpe = rpe;
                                                            ex.restSeconds = rest;
                                                            ex.notes = notes;
                                                          });
                                                          await _saveUserSplitsOverride();
                                                        },
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.surfaceLowest,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(ex.targetReps, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.surfaceLowest,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text('RPE ${ex.targetRpe}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.surfaceLowest,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text('${ex.restSeconds}s Rest', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.tertiary)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(Icons.trending_up, color: AppTheme.secondary, size: 14),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    overloadText,
                                                    style: const TextStyle(fontSize: 10, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.tune, color: AppTheme.textMuted, size: 18),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => ExerciseCustomizerDialog(
                                                  exercise: ex,
                                                  onSave: (reps, rpe, rest, notes) async {
                                                    setState(() {
                                                      ex.targetReps = reps;
                                                      ex.targetRpe = rpe;
                                                      ex.restSeconds = rest;
                                                      ex.notes = notes;
                                                    });
                                                    await _saveUserSplitsOverride();
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () async {
                                              // Save current performance before removal
                                              final validSet = ex.sets.firstWhere((s) => s.weight > 0 || s.reps > 0, orElse: () => ex.sets[0]);
                                              if (validSet.weight > 0 || validSet.reps > 0) {
                                                await DatabaseHelper.instance.updateExercisePerformance(ex.exerciseId, validSet.weight, validSet.reps);
                                              }
                                              setState(() {
                                                _exercises.removeAt(exIdx);
                                                currentSplit.days[_selectedDayIndex].exerciseIds = _exercises.map((e) => e.exerciseId).toList();
                                                currentSplit.days[_selectedDayIndex].exerciseConfigs.remove(ex.exerciseId);
                                              });
                                              await _saveUserSplitsOverride();
                                              _showToast('Removed "${ex.name}"');
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Sets Table Header
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 24, child: Text('SET', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                        const SizedBox(width: 70, child: Text('PREV', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold))),
                                        Expanded(child: Center(child: Text('WEIGHT ($_unit)', style: const TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)))),
                                        const SizedBox(width: 80, child: Center(child: Text('REPS', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)))),
                                        const SizedBox(width: 36, child: Center(child: Text('DONE', style: TextStyle(fontSize: 9, color: AppTheme.textMuted, fontWeight: FontWeight.bold)))),
                                      ],
                                    ),
                                  ),

                                  // Set Rows
                                  Column(
                                    children: List.generate(ex.sets.length, (setIdx) {
                                      final set = ex.sets[setIdx];
                                      final isDone = set.completed;
                                      final prevHint = (set.prevWeight != null && set.prevReps != null && (set.prevWeight! > 0 || set.prevReps! > 0))
                                          ? '${set.prevWeight!.toStringAsFixed(0)} × ${set.prevReps}'
                                          : (hasHist && (lastW > 0 || lastR > 0) ? '${lastW.toStringAsFixed(0)} × $lastR' : '--');

                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 3),
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                        decoration: BoxDecoration(
                                          color: isDone ? AppTheme.surfaceLowest : AppTheme.surfaceHigh,
                                          borderRadius: BorderRadius.circular(6),
                                          border: isDone ? Border.all(color: AppTheme.secondaryContainer) : null,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              child: Text(
                                                '${set.setNumber}',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDone ? AppTheme.secondary : AppTheme.textMain),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 70,
                                              child: Text(prevHint, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                            ),
                                            // Weight steppers
                                            Expanded(
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: Text('-$weightStep', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    onPressed: () async {
                                                      setState(() {
                                                        set.weight = (set.weight - weightStep).clamp(0.0, 999.0);
                                                      });
                                                      await _saveUserSplitsOverride();
                                                    },
                                                  ),
                                                  Text(
                                                    set.weight.toStringAsFixed(1),
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDone ? AppTheme.secondary : AppTheme.primary),
                                                  ),
                                                  IconButton(
                                                    icon: Text('+$weightStep', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                    onPressed: () async {
                                                      setState(() {
                                                        set.weight += weightStep;
                                                      });
                                                      await _saveUserSplitsOverride();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Reps steppers
                                            SizedBox(
                                              width: 80,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Text('-1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
                                                    onPressed: () async {
                                                      setState(() {
                                                        set.reps = (set.reps - 1).clamp(0, 999);
                                                      });
                                                      await _saveUserSplitsOverride();
                                                    },
                                                  ),
                                                  Text(
                                                    '${set.reps}',
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDone ? AppTheme.secondary : AppTheme.primary),
                                                  ),
                                                  IconButton(
                                                    icon: const Text('+1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
                                                    onPressed: () async {
                                                      setState(() {
                                                        set.reps++;
                                                      });
                                                      await _saveUserSplitsOverride();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Done Checkmark
                                            SizedBox(
                                              width: 36,
                                              child: IconButton(
                                                icon: Icon(
                                                  isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                                                  color: isDone ? AppTheme.secondary : AppTheme.textMuted,
                                                  size: 22,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () async {
                                                  final willBeDone = !set.completed;
                                                  setState(() {
                                                    set.completed = willBeDone;
                                                  });

                                                  if (willBeDone && (set.weight > 0 || set.reps > 0)) {
                                                    await DatabaseHelper.instance.updateExercisePerformance(ex.exerciseId, set.weight, set.reps);
                                                    ex.hasHistory = true;
                                                    ex.prevWeight = set.weight;
                                                    ex.prevReps = set.reps;

                                                    // Propagate to next sets if empty
                                                    for (int i = setIdx + 1; i < ex.sets.length; i++) {
                                                      final next = ex.sets[i];
                                                      if (!next.completed) {
                                                        next.prevWeight = set.weight;
                                                        next.prevReps = set.reps;
                                                        if (next.weight == 0 && next.reps == 0) {
                                                          next.weight = set.weight;
                                                          next.reps = set.reps;
                                                        }
                                                      }
                                                    }
                                                    _showToast('Set ${set.setNumber} Logged (${set.weight} $_unit × ${set.reps})');
                                                    _startRestTimer(ex.restSeconds);
                                                  }

                                                  await _saveUserSplitsOverride();
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),

                                  // Exercise bottom controls
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.add, size: 14, color: AppTheme.textMain),
                                        label: const Text('Add Set', style: TextStyle(fontSize: 11, color: AppTheme.textMain)),
                                        onPressed: () async {
                                          final last = ex.sets.isNotEmpty ? ex.sets.last : null;
                                          setState(() {
                                            ex.sets.add(WorkoutSet(
                                              setNumber: ex.sets.length + 1,
                                              weight: last?.weight ?? ex.prevWeight,
                                              reps: last?.reps ?? ex.prevReps,
                                              prevWeight: last?.weight,
                                              prevReps: last?.reps,
                                            ));
                                          });
                                          await _saveUserSplitsOverride();
                                        },
                                      ),
                                      Row(
                                        children: [
                                          TextButton.icon(
                                            icon: const Icon(Icons.calculate, size: 14, color: AppTheme.tertiary),
                                            label: const Text('Plate Calc', style: TextStyle(fontSize: 11, color: AppTheme.tertiary)),
                                            onPressed: () {
                                              final w = ex.sets.isNotEmpty ? ex.sets[0].weight : 0.0;
                                              showDialog(
                                                context: context,
                                                builder: (_) => PlateCalculatorDialog(
                                                  initialWeight: w,
                                                  exerciseName: ex.name,
                                                  unit: _unit,
                                                ),
                                              );
                                            },
                                          ),
                                          if (ex.sets.length > 1)
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 16, color: AppTheme.textMuted),
                                              onPressed: () async {
                                                setState(() => ex.sets.removeLast());
                                                await _saveUserSplitsOverride();
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // Browse Catalog / Add More Exercises Card
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _openAddExercisePicker,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.library_add, color: AppTheme.primary, size: 18),
                              SizedBox(width: 8),
                              Text(
                                '+ ADD EXERCISES FROM 187+ MOVEMENTS CATALOG',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Cycle Schedule Accordion
                      const Text('CYCLE SCHEDULE ACCORDION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                      const SizedBox(height: 8),
                      Column(
                        children: List.generate(currentSplit.days.length, (idx) {
                          if (idx == _selectedDayIndex) return const SizedBox();
                          final d = currentSplit.days[idx];
                          final isRest = d.isRest;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.surfaceHigh),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isRest ? AppTheme.tertiaryContainer.withValues(alpha: 0.2) : AppTheme.secondaryContainer.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(d.day, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isRest ? AppTheme.tertiary : AppTheme.secondary)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(
                                        isRest ? 'Scheduled Rest & Recovery' : '${d.exerciseIds.length} Exercises • ${d.focus}',
                                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isRest)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.surfaceHigh,
                                      foregroundColor: AppTheme.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    ),
                                    onPressed: () async {
                                      d.isRest = false;
                                      await _saveUserSplitsOverride();
                                      _loadDayWorkout(idx);
                                    },
                                    child: const Text('CONVERT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                                    onPressed: () => _loadDayWorkout(idx),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Finish Workout / Save Session Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondary,
                            foregroundColor: AppTheme.onSecondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.bolt),
                          label: Text(
                            'FINISH TODAY\'S ${currentDay.day} SESSION',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          onPressed: () async {
                            final completedSets = <Map<String, dynamic>>[];
                            double totalVolume = 0;

                            for (var ex in _exercises) {
                              for (var s in ex.sets) {
                                if (s.completed) {
                                  totalVolume += s.weight * s.reps;
                                  completedSets.add(s.toMap(null, ex.exerciseId, _unit));
                                }
                              }
                            }

                            if (completedSets.isEmpty) {
                              _showToast('Tap the checkmarks on sets as you complete them!');
                              return;
                            }

                            final session = WorkoutSession(
                              title: '${currentDay.day} • ${currentDay.name}',
                              date: DateTime.now().toIso8601String(),
                              durationSeconds: _elapsedSeconds,
                              totalVolume: totalVolume,
                              unit: _unit,
                            );

                            await DatabaseHelper.instance.finishWorkout(session, completedSets);
                            await _saveUserSplitsOverride();
                            _showToast('Logged Workout! Total Tonnage: ${totalVolume.toStringAsFixed(0)} $_unit');
                          },
                        ),
                      ),
                    ],
                  ),
                ),

          // Rest Timer Floating Overlay Widget
          if (_isRestTimerActive)
            Positioned(
              left: 14,
              right: 14,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.tertiary.withValues(alpha: 0.5)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, color: AppTheme.tertiary, size: 24),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('REST INTERVAL', style: TextStyle(fontSize: 10, color: AppTheme.tertiary, fontWeight: FontWeight.bold)),
                            Text(_formatTimer(_restRemainingSeconds), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.surfaceLowest,
                            foregroundColor: AppTheme.tertiary,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () {
                            setState(() => _restRemainingSeconds += 30);
                            _showToast('+30s Added');
                          },
                          child: const Text('+30s', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.skip_next, color: AppTheme.textMuted),
                          onPressed: () {
                            _restTimer?.cancel();
                            setState(() => _isRestTimerActive = false);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
