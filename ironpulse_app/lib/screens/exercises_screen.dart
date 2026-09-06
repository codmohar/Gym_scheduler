import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models.dart';
import '../db_helper.dart';

class ExercisesScreen extends StatefulWidget {
  final Function(String message)? onShowToast;
  final Function(Exercise exercise, [int? dayIndex])? onAddExerciseToWorkout;
  final Function()? onNavigateToWorkout;

  const ExercisesScreen({
    super.key,
    this.onShowToast,
    this.onAddExerciseToWorkout,
    this.onNavigateToWorkout,
  });

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  List<Exercise> _allExercises = [];
  List<Exercise> _filteredExercises = [];
  String _searchQuery = '';
  String _selectedMuscleGroup = 'All';
  String? _selectedModality;
  bool _isLoading = true;

  final List<String> _muscleGroups = [
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

  final List<String> _modalities = [
    'Free Weights',
    'Calisthenics',
    'Cables & Machines',
  ];

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => _isLoading = true);
    final list = await DatabaseHelper.instance.getAllExercises();
    if (!mounted) return;
    setState(() {
      _allExercises = list;
      _filteredExercises = list;
      _isLoading = false;
    });
  }

  void _filterExercises() {
    setState(() {
      _filteredExercises = _allExercises.where((ex) {
        final matchesQuery = _searchQuery.isEmpty ||
            ex.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            ex.secondaryMuscles.any((m) => m.toLowerCase().contains(_searchQuery.toLowerCase()));

        final matchesGroup = _selectedMuscleGroup == 'All' ||
            ex.muscleGroup.toLowerCase().contains(_selectedMuscleGroup.toLowerCase());

        final matchesModality = _selectedModality == null ||
            ex.modality.toLowerCase() == _selectedModality!.toLowerCase();

        return matchesQuery && matchesGroup && matchesModality;
      }).toList();
    });
  }

  Future<void> _addExerciseToCurrentWorkout(Exercise ex) async {
    if (widget.onAddExerciseToWorkout != null) {
      widget.onAddExerciseToWorkout!(ex);
      return;
    }

    // Fallback direct persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      final splitIdx = prefs.getInt('selected_split') ?? 0;
      final dayIdx = prefs.getInt('selected_day') ?? 0;

      final overrideJson = prefs.getString('user_splits_override');
      List<RoutineSplit> splits = PresetRoutines.getAllPresets();
      if (overrideJson != null && overrideJson.isNotEmpty) {
        final decoded = json.decode(overrideJson);
        if (decoded is List) {
          splits = decoded.map((e) => RoutineSplit.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        }
      }

      if (splitIdx < splits.length && dayIdx < splits[splitIdx].days.length) {
        final day = splits[splitIdx].days[dayIdx];
        if (!day.exerciseIds.contains(ex.id)) {
          day.exerciseIds.add(ex.id);
        }
        day.isRest = false;
        await prefs.setString('user_splits_override', json.encode(splits.map((s) => s.toMap()).toList()));
        if (widget.onShowToast != null) {
          widget.onShowToast!('Added "${ex.name}" to ${day.day} (${day.name})');
        }
      }
    } catch (e) {
      if (widget.onShowToast != null) {
        widget.onShowToast!('Added "${ex.name}" to Workout');
      }
    }
  }

  void _openCustomExerciseDialog() {
    final nameController = TextEditingController();
    String selectedGroup = 'Chest';
    String selectedMod = 'Free Weights';
    bool addToWorkout = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
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
                    const Text('New Custom Movement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('MOVEMENT NAME *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Deficit RDL, Ring Dips...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
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
                          const Text('PRIMARY MUSCLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: AppTheme.surfaceLowest, borderRadius: BorderRadius.circular(8)),
                            child: DropdownButton<String>(
                              value: selectedGroup,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: AppTheme.surfaceHigh,
                              items: ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Core', 'Legs', 'Calves', 'Full Body']
                                  .map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (v) => setDialogState(() => selectedGroup = v!),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MODALITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: AppTheme.surfaceLowest, borderRadius: BorderRadius.circular(8)),
                            child: DropdownButton<String>(
                              value: selectedMod,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: AppTheme.surfaceHigh,
                              items: _modalities
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (v) => setDialogState(() => selectedMod = v!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: addToWorkout,
                      activeColor: AppTheme.primaryContainer,
                      onChanged: (v) => setDialogState(() => addToWorkout = v ?? true),
                    ),
                    const Text('Add to active workout routine immediately', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryContainer,
                      foregroundColor: AppTheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save Custom Movement', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;

                      final newEx = await DatabaseHelper.instance.addCustomExercise(name, selectedGroup, selectedMod);
                      if (!mounted) return;
                      setState(() {
                        _allExercises.insert(0, newEx);
                        _filterExercises();
                      });

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }

                      if (addToWorkout) {
                        await _addExerciseToCurrentWorkout(newEx);
                      } else {
                        if (widget.onShowToast != null) {
                          widget.onShowToast!('Created custom movement: "$name"');
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exercise Catalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('${_allExercises.length} Movements', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryContainer,
                foregroundColor: AppTheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('+ CUSTOM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: _openCustomExerciseDialog,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryContainer))
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: TextField(
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
                    onChanged: (val) {
                      _searchQuery = val;
                      _filterExercises();
                    },
                  ),
                ),

                // Muscle Group Filter Chips
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _muscleGroups.length,
                    itemBuilder: (context, idx) {
                      final group = _muscleGroups[idx];
                      final isSelected = group == _selectedMuscleGroup;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(group),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryContainer,
                          backgroundColor: AppTheme.surface,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppTheme.onPrimary : AppTheme.textMuted,
                          ),
                          onSelected: (sel) {
                            setState(() => _selectedMuscleGroup = group);
                            _filterExercises();
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),

                // Modality Filter Chips
                SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _modalities.length,
                    itemBuilder: (context, idx) {
                      final mod = _modalities[idx];
                      final isSelected = mod == _selectedModality;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(mod),
                          selected: isSelected,
                          selectedColor: AppTheme.tertiaryContainer,
                          backgroundColor: AppTheme.surfaceLowest,
                          labelStyle: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : AppTheme.textMuted,
                          ),
                          onSelected: (sel) {
                            setState(() => _selectedModality = sel ? mod : null);
                            _filterExercises();
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),

                // Exercise List
                Expanded(
                  child: _filteredExercises.isEmpty
                      ? const Center(child: Text('No exercises found', style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                          itemCount: _filteredExercises.length,
                          itemBuilder: (context, idx) {
                            final ex = _filteredExercises[idx];
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
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                ex.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (ex.isCustom) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(color: AppTheme.primaryContainer.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                                child: const Text('CUSTOM', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${ex.muscleGroup.toUpperCase()} • ${ex.modality.toUpperCase()}',
                                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                      await _addExerciseToCurrentWorkout(ex);
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
  }
}
