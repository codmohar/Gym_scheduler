/**
 * IronPulse Web Application Controller
 * Clean, Zero-Latency Resistance & Workout Logger
 */

(function () {
  'use strict';

  // --- State ---
  const state = {
    currentTab: 'workout',
    unit: 'kg', // 'kg' or 'lbs'
    exercises: [],
    catalogFilterGroup: 'all',
    catalogFilterModality: null,
    catalogSearchQuery: '',
    
    // Planner / Schedule State
    currentSplitId: 'ppl',
    selectedDayIndex: 0, // 0 = MON
    routines: [],

    // Active Workout State
    activeWorkout: {
      isActive: false,
      title: 'Monday • Push Power & Chest',
      startTime: null,
      elapsedSeconds: 0,
      timerInterval: null,
      isRestMode: false,
      exercises: [] // Array of { exercise_id, name, muscle_group, modality, target_reps, target_rpe, rest_seconds, notes, sets: [{ set_number, weight, reps, completed, prev_weight, prev_reps }] }
    },

    // Selected Exercise for Parameter Customizer Modal
    selectedExIndexForCustomizer: 0,

    // Rest Timer State
    restTimer: {
      isActive: false,
      remainingSeconds: 0,
      totalSeconds: 90,
      intervalId: null
    },

    // History State
    historySessions: []
  };

  // --- Audio Synthesizer for Rest Timer Chime ---
  function playTimerChime() {
    try {
      const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(587.33, audioCtx.currentTime); // D5
      osc.frequency.setValueAtTime(880, audioCtx.currentTime + 0.15); // A5
      gain.gain.setValueAtTime(0.3, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.6);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start();
      osc.stop(audioCtx.currentTime + 0.6);
    } catch (e) {
      // Audio not supported or blocked
    }

    if (navigator.vibrate) {
      navigator.vibrate([200, 100, 200]);
    }
  }

  // --- Toast Notifications ---
  function showToast(message, icon = 'check_circle', isSuccess = true) {
    const toast = document.getElementById('appToast');
    const toastText = document.getElementById('appToastText');
    const toastIcon = document.getElementById('appToastIcon');
    if (!toast || !toastText) return;

    toastText.textContent = message;
    if (toastIcon) {
      toastIcon.textContent = icon;
      toastIcon.className = `material-symbols-outlined text-[20px] ${isSuccess ? 'text-secondary' : 'text-primary'}`;
    }

    toast.classList.remove('opacity-0', 'translate-y-4', 'pointer-events-none');
    toast.classList.add('opacity-100', 'translate-y-0');

    clearTimeout(toast._timeout);
    toast._timeout = setTimeout(() => {
      toast.classList.remove('opacity-100', 'translate-y-0');
      toast.classList.add('opacity-0', 'translate-y-4', 'pointer-events-none');
    }, 2400);
  }

  // --- Plate Calculator Helper ---
  function calculatePlates(targetWeight, isLbs = false, customBar = null) {
    if (isLbs) {
      const barWeight = customBar !== null ? Number(customBar) : 45;
      const availablePlates = [45, 35, 25, 10, 5, 2.5];
      let remainingPerSide = (targetWeight - barWeight) / 2;
      if (remainingPerSide <= 0) return { barWeight, platesPerSide: [], totalCalculated: Math.min(targetWeight, barWeight), remainder: 0, unit: 'lbs' };

      const platesPerSide = [];
      for (const plate of availablePlates) {
        while (remainingPerSide >= plate) {
          platesPerSide.push(plate);
          remainingPerSide = Math.round((remainingPerSide - plate) * 100) / 100;
        }
      }

      return {
        barWeight,
        platesPerSide,
        totalCalculated: barWeight + platesPerSide.reduce((a, b) => a + b, 0) * 2,
        remainder: remainingPerSide * 2,
        unit: 'lbs'
      };
    } else {
      const barWeight = customBar !== null ? Number(customBar) : 20;
      const availablePlates = [25, 20, 15, 10, 5, 2.5, 1.25];
      let remainingPerSide = (targetWeight - barWeight) / 2;
      if (remainingPerSide <= 0) return { barWeight, platesPerSide: [], totalCalculated: Math.min(targetWeight, barWeight), remainder: 0, unit: 'kg' };

      const platesPerSide = [];
      for (const plate of availablePlates) {
        while (remainingPerSide >= plate) {
          platesPerSide.push(plate);
          remainingPerSide = Math.round((remainingPerSide - plate) * 100) / 100;
        }
      }

      return {
        barWeight,
        platesPerSide,
        totalCalculated: barWeight + platesPerSide.reduce((a, b) => a + b, 0) * 2,
        remainder: remainingPerSide * 2,
        unit: 'kg'
      };
    }
  }

  // --- Initialize Application ---
  async function initApp() {
    // 1. Initialize Dexie IndexedDB
    await window.ironPulseDB.init();
    state.exercises = await window.ironPulseDB.getAllExercises();
    state.routines = await window.ironPulseDB.getRoutines();

    // 2. Load Saved Settings (Unit, Split, Day)
    const savedUnit = await window.ironPulseDB.getSetting('unit', 'kg');
    state.unit = savedUnit || 'kg';
    updateUnitUI();

    const savedSplitId = await window.ironPulseDB.getSetting('selected_split_id', 'ppl');
    const savedDayIndex = await window.ironPulseDB.getSetting('selected_day_index', 0);
    state.currentSplitId = savedSplitId || 'ppl';
    state.selectedDayIndex = typeof savedDayIndex === 'number' ? savedDayIndex : 0;

    // 3. Restore active workout state if present and valid
    const savedActiveWorkout = await window.ironPulseDB.getActiveWorkout();
    if (savedActiveWorkout && savedActiveWorkout.exercises && savedActiveWorkout.exercises.length > 0 &&
        savedActiveWorkout.splitId === state.currentSplitId && savedActiveWorkout.dayIndex === state.selectedDayIndex) {
      state.activeWorkout = savedActiveWorkout;
      startWorkoutTimer();
    } else {
      // Load user's saved day workout from routine
      await loadDayWorkout(state.selectedDayIndex);
    }

    // 4. Setup Navigation & Routing
    setupNavigation();

    // 5. Render Initial Views
    renderUnifiedScheduleView();
    renderCatalogView();
    renderHistoryView();
    renderSyncView();

    // 6. Setup Event Listeners
    setupCatalogListeners();
    setupUnifiedScheduleListeners();
    setupRestTimerListeners();
    setupCustomExerciseModalListeners();
    setupParameterSettingsModalListeners();
    setupSyncListeners();
    setupUnitSwitcherListeners();

    // 7. Handle URL Hash
    handleHashChange();
    window.addEventListener('hashchange', handleHashChange);
  }

  // --- Unit Switcher Logic ---
  function updateUnitUI() {
    const isKg = state.unit === 'kg';
    const kgBtn = document.getElementById('unitKgBtn');
    const lbsBtn = document.getElementById('unitLbsBtn');
    const settingsKgBtn = document.getElementById('settingsUnitKgBtn');
    const settingsLbsBtn = document.getElementById('settingsUnitLbsBtn');
    const historyUnitLabel = document.getElementById('historyUnitLabel');

    if (kgBtn && lbsBtn) {
      if (isKg) {
        kgBtn.className = 'px-2.5 py-1 rounded-md font-label-caps text-xs font-bold transition-all bg-primary-container text-on-primary shadow-sm';
        lbsBtn.className = 'px-2.5 py-1 rounded-md font-label-caps text-xs font-bold transition-all text-on-surface-variant hover:text-on-surface';
      } else {
        lbsBtn.className = 'px-2.5 py-1 rounded-md font-label-caps text-xs font-bold transition-all bg-primary-container text-on-primary shadow-sm';
        kgBtn.className = 'px-2.5 py-1 rounded-md font-label-caps text-xs font-bold transition-all text-on-surface-variant hover:text-on-surface';
      }
    }

    if (settingsKgBtn && settingsLbsBtn) {
      if (isKg) {
        settingsKgBtn.className = 'flex-1 h-12 rounded-xl bg-primary-container text-on-primary font-headline-sm text-sm uppercase flex items-center justify-center gap-2 active:scale-95 shadow-md font-bold';
        settingsLbsBtn.className = 'flex-1 h-12 rounded-xl bg-surface-container-high text-on-surface font-headline-sm text-sm uppercase flex items-center justify-center gap-2 active:scale-95 shadow-md hover:bg-surface-bright';
      } else {
        settingsLbsBtn.className = 'flex-1 h-12 rounded-xl bg-primary-container text-on-primary font-headline-sm text-sm uppercase flex items-center justify-center gap-2 active:scale-95 shadow-md font-bold';
        settingsKgBtn.className = 'flex-1 h-12 rounded-xl bg-surface-container-high text-on-surface font-headline-sm text-sm uppercase flex items-center justify-center gap-2 active:scale-95 shadow-md hover:bg-surface-bright';
      }
    }

    if (historyUnitLabel) historyUnitLabel.textContent = state.unit;
    document.querySelectorAll('.unit-text-span').forEach(el => el.textContent = state.unit);
  }

  function setupUnitSwitcherListeners() {
    const setUnit = async (newUnit) => {
      if (state.unit === newUnit) return;
      const oldUnit = state.unit;
      state.unit = newUnit;

      // Convert active workout exercises weight values dynamically
      if (state.activeWorkout && state.activeWorkout.exercises) {
        state.activeWorkout.exercises.forEach(ex => {
          if (ex.prevWeight > 0) {
            if (oldUnit === 'kg' && newUnit === 'lbs') {
              ex.prevWeight = Math.round(ex.prevWeight * 2.20462262 * 2) / 2;
            } else if (oldUnit === 'lbs' && newUnit === 'kg') {
              ex.prevWeight = Math.round((ex.prevWeight / 2.20462262) * 2) / 2;
            }
          }
          ex.sets.forEach(s => {
            if (s.weight > 0) {
              if (oldUnit === 'kg' && newUnit === 'lbs') {
                s.weight = Math.round(s.weight * 2.20462262 * 2) / 2;
              } else if (oldUnit === 'lbs' && newUnit === 'kg') {
                s.weight = Math.round((s.weight / 2.20462262) * 2) / 2;
              }
            }
            if (s.prev_weight > 0) {
              if (oldUnit === 'kg' && newUnit === 'lbs') {
                s.prev_weight = Math.round(s.prev_weight * 2.20462262 * 2) / 2;
              } else if (oldUnit === 'lbs' && newUnit === 'kg') {
                s.prev_weight = Math.round((s.prev_weight / 2.20462262) * 2) / 2;
              }
            }
          });
        });
      }

      await window.ironPulseDB.setSetting('unit', newUnit);
      await saveActiveWorkoutState();
      updateUnitUI();
      renderUnifiedScheduleView();
      renderHistoryView();
      showToast(`Measurement unit switched to ${newUnit.toUpperCase()}`);
    };

    const kgBtn = document.getElementById('unitKgBtn');
    const lbsBtn = document.getElementById('unitLbsBtn');
    const settingsKgBtn = document.getElementById('settingsUnitKgBtn');
    const settingsLbsBtn = document.getElementById('settingsUnitLbsBtn');

    if (kgBtn) kgBtn.addEventListener('click', () => setUnit('kg'));
    if (lbsBtn) lbsBtn.addEventListener('click', () => setUnit('lbs'));
    if (settingsKgBtn) settingsKgBtn.addEventListener('click', () => setUnit('kg'));
    if (settingsLbsBtn) settingsLbsBtn.addEventListener('click', () => setUnit('lbs'));
  }

  // --- Load Day Workout from Routine ---
  async function loadDayWorkout(dayIndex = 0) {
    state.selectedDayIndex = dayIndex;
    await window.ironPulseDB.setSetting('selected_day_index', dayIndex);
    await window.ironPulseDB.setSetting('selected_split_id', state.currentSplitId);

    const activeRoutine = state.routines.find(r => r.id === state.currentSplitId) || state.routines[0];
    if (!activeRoutine) return;

    const day = activeRoutine.days[dayIndex];
    if (!day) return;

    const dayTitle = `${day.day === 'MON' ? 'Monday' : (day.day === 'TUE' ? 'Tuesday' : (day.day === 'WED' ? 'Wednesday' : (day.day === 'THU' ? 'Thursday' : (day.day === 'FRI' ? 'Friday' : (day.day === 'SAT' ? 'Saturday' : 'Sunday')))))} • ${day.name}`;

    const exList = [];
    for (const exId of day.exercise_ids) {
      const exObj = state.exercises.find(e => e.id === exId);
      if (!exObj) continue;

      // Check if user previously logged weight/reps for this exercise
      const prevData = await window.ironPulseDB.getPreviousPerformance(exId);
      const defaultSetsCount = 3;
      
      const savedWeight = prevData.hasHistory ? prevData.last_weight : 0;
      const savedReps = prevData.hasHistory ? prevData.last_reps : 0;

      const sets = [];
      for (let s = 1; s <= defaultSetsCount; s++) {
        sets.push({
          set_number: s,
          prev_weight: prevData.hasHistory ? prevData.last_weight : null,
          prev_reps: prevData.hasHistory ? prevData.last_reps : null,
          weight: savedWeight,
          reps: savedReps,
          completed: false
        });
      }

      exList.push({
        exercise_id: exObj.id,
        name: exObj.name,
        muscle_group: exObj.muscle_group,
        modality: exObj.modality,
        target_reps: `${defaultSetsCount} Sets × 8-10 Reps`,
        target_rpe: '8.0',
        rest_seconds: 90,
        notes: '',
        hasHistory: prevData.hasHistory,
        prevWeight: prevData.last_weight,
        prevReps: prevData.last_reps,
        sets
      });
    }

    state.activeWorkout = {
      isActive: true,
      splitId: state.currentSplitId,
      dayIndex: state.selectedDayIndex,
      title: dayTitle,
      startTime: Date.now(),
      elapsedSeconds: 0,
      timerInterval: null,
      isRestMode: day.is_rest,
      exercises: exList
    };

    startWorkoutTimer();
    await saveActiveWorkoutState();
  }

  // --- Navigation & Routing ---
  function setupNavigation() {
    const navButtons = document.querySelectorAll('nav [data-path]');
    navButtons.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const targetTab = btn.getAttribute('data-path');
        window.location.hash = targetTab;
      });
    });
  }

  function handleHashChange() {
    const rawHash = (window.location.hash || '#workout').replace('#', '');
    const validTabs = ['workout', 'exercises', 'history', 'sync'];
    const activeTab = (rawHash === 'planner' || rawHash === 'schedule') ? 'workout' : (validTabs.includes(rawHash) ? rawHash : 'workout');

    state.currentTab = activeTab;

    document.querySelectorAll('nav [data-path]').forEach(btn => {
      const path = btn.getAttribute('data-path');
      const isActive = (path === activeTab);
      if (isActive) {
        btn.classList.add('text-primary-container', 'font-headline-sm');
        btn.classList.remove('text-on-surface-variant');
      } else {
        btn.classList.remove('text-primary-container', 'font-headline-sm');
        btn.classList.add('text-on-surface-variant');
      }
    });

    const screens = {
      workout: document.getElementById('workoutScreen'),
      exercises: document.getElementById('exercisesScreen'),
      history: document.getElementById('historyScreen'),
      sync: document.getElementById('syncScreen')
    };

    Object.entries(screens).forEach(([key, screenEl]) => {
      if (!screenEl) return;
      if (key === activeTab) {
        screenEl.classList.remove('hidden');
        window.scrollTo({ top: 0, behavior: 'instant' });
      } else {
        screenEl.classList.add('hidden');
      }
    });

    if (activeTab === 'workout') renderUnifiedScheduleView();
    if (activeTab === 'history') renderHistoryView();
    if (activeTab === 'sync') renderSyncView();
  }

  // --- Timer Engine ---
  function startWorkoutTimer() {
    if (state.activeWorkout.timerInterval) clearInterval(state.activeWorkout.timerInterval);
    state.activeWorkout.timerInterval = setInterval(() => {
      state.activeWorkout.elapsedSeconds++;
      updateElapsedTimerDisplay();
    }, 1000);
    updateElapsedTimerDisplay();
  }

  function updateElapsedTimerDisplay() {
    const timerEl = document.getElementById('elapsed-timer');
    if (!timerEl) return;
    const totalSecs = state.activeWorkout.elapsedSeconds;
    const mins = Math.floor(totalSecs / 60);
    const secs = totalSecs % 60;
    timerEl.textContent = `${mins < 10 ? '0' : ''}${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  async function saveActiveWorkoutState() {
    const toSave = {
      ...state.activeWorkout,
      splitId: state.currentSplitId,
      dayIndex: state.selectedDayIndex,
      timerInterval: null
    };
    await window.ironPulseDB.saveActiveWorkout(toSave);

    // Sync routine day exercise_ids and is_rest so changes persist across day switching and reloads
    const activeRoutine = state.routines.find(r => r.id === state.currentSplitId) || state.routines[0];
    if (activeRoutine && activeRoutine.days && activeRoutine.days[state.selectedDayIndex]) {
      const day = activeRoutine.days[state.selectedDayIndex];
      day.exercise_ids = state.activeWorkout.exercises.map(e => e.exercise_id).filter(Boolean);
      day.is_rest = !!state.activeWorkout.isRestMode;
      await window.ironPulseDB.saveRoutine(activeRoutine);
    }
  }

  // --- Unified Schedule & Workout Render Engine ---

  function renderUnifiedScheduleView() {
    const daysStrip = document.getElementById('unifiedDaysStrip');
    const targetTitle = document.getElementById('targetSessionTitle');
    const movementsCountEl = document.getElementById('targetSessionMovementsCount');
    const volumeSetsEl = document.getElementById('targetSessionVolumeSets');
    const estDurationEl = document.getElementById('targetSessionEstDuration');
    const container = document.getElementById('unifiedExercisesContainer');
    const accordionContainer = document.getElementById('cycleScheduleAccordion');
    const restToggleBtn = document.getElementById('restToggleBtn');
    const restToggleKnob = document.getElementById('restToggleKnob');
    const startTodayBtnText = document.getElementById('startTodayWorkoutBtnText');
    if (!daysStrip || !container) return;

    const activeRoutine = state.routines.find(r => r.id === state.currentSplitId) || state.routines[0];
    if (!activeRoutine) return;

    // 0. Update Split Selector Active Pill Highlight
    document.querySelectorAll('.split-pill').forEach(pill => {
      const splitId = pill.getAttribute('data-split-id');
      const isSelected = splitId === state.currentSplitId;
      if (isSelected) {
        pill.className = 'split-pill flex items-center gap-1.5 px-3.5 py-2 rounded-lg bg-primary-container text-on-primary font-label-caps text-label-caps whitespace-nowrap shadow-sm active:scale-95 transition-transform font-bold';
      } else {
        pill.className = 'split-pill flex items-center gap-1.5 px-3.5 py-2 rounded-lg bg-surface-container-high text-on-surface-variant hover:text-on-surface font-label-caps text-label-caps whitespace-nowrap active:scale-95 transition-all';
      }
    });

    const isLbs = state.unit === 'lbs';
    const weightStep = isLbs ? 5 : 2.5;

    // 1. Render 7-Day Strip
    daysStrip.innerHTML = activeRoutine.days.map((d, idx) => {
      const isSelected = idx === state.selectedDayIndex;
      const isRest = d.is_rest;
      const borderTop = isSelected ? 'bg-primary' : 'bg-transparent';
      const containerClass = isSelected
        ? 'bg-surface-container-highest shadow-[0_0_12px_rgba(245,158,11,0.25)] border-primary'
        : (isRest ? 'bg-surface-container-lowest opacity-75' : 'bg-surface-container-low hover:bg-surface-container');

      return `
        <button class="unified-day-pill relative flex flex-col items-center justify-between p-1.5 rounded-lg ${containerClass} min-h-[70px] text-left transition-all active:scale-95" data-day-index="${idx}">
          <span class="w-full h-0.5 rounded-full ${borderTop} mb-1"></span>
          <span class="font-headline-sm text-[13px] font-bold ${isSelected ? 'text-primary' : 'text-on-surface'} leading-none">${d.day}</span>
          <span class="font-label-caps text-[9px] ${isRest ? 'text-tertiary' : 'text-on-surface-variant'} font-semibold truncate max-w-full uppercase">${isRest ? 'REST' : d.name.split(' ')[0]}</span>
          <span class="font-label-numeric-sm text-[10px] ${isSelected ? 'text-on-primary bg-primary-container font-bold' : (isRest ? 'text-tertiary' : 'text-on-surface-variant bg-surface-container-highest')} px-1 rounded-sm mt-1">
            ${isRest ? '<span class="material-symbols-outlined text-[13px]">hotel</span>' : `${d.exercise_ids.length} EX`}
          </span>
        </button>
      `;
    }).join('');

    // 2. Render Target Session Metadata Box
    if (targetTitle) targetTitle.textContent = state.activeWorkout.title;

    let totalSets = 0;
    state.activeWorkout.exercises.forEach(ex => { totalSets += ex.sets.length; });

    if (movementsCountEl) movementsCountEl.textContent = `${state.activeWorkout.exercises.length} Items`;
    if (volumeSetsEl) volumeSetsEl.textContent = `${totalSets} Sets`;
    if (estDurationEl) estDurationEl.textContent = `~${Math.max(15, totalSets * 3)} min`;

    if (startTodayBtnText) {
      const curDayName = activeRoutine.days[state.selectedDayIndex]?.day || 'TODAY';
      startTodayBtnText.textContent = state.activeWorkout.isRestMode ? `REST DAY` : `START TODAY'S ${curDayName}`;
    }

    if (restToggleKnob && restToggleBtn) {
      if (state.activeWorkout.isRestMode) {
        restToggleBtn.classList.remove('bg-surface-container-lowest');
        restToggleBtn.classList.add('bg-primary-container');
        restToggleKnob.classList.remove('bg-on-surface-variant', 'translate-x-1');
        restToggleKnob.classList.add('bg-on-primary', 'translate-x-4');
      } else {
        restToggleBtn.classList.add('bg-surface-container-lowest');
        restToggleBtn.classList.remove('bg-primary-container');
        restToggleKnob.classList.add('bg-on-surface-variant', 'translate-x-1');
        restToggleKnob.classList.remove('bg-on-primary', 'translate-x-4');
      }
    }

    // 3. Render Exercises List with Integrated Steppers and Set Customizer
    if (state.activeWorkout.isRestMode) {
      container.innerHTML = `
        <div class="p-space-lg bg-surface-container rounded-xl text-center flex flex-col items-center gap-2 text-on-surface-variant shadow-md">
          <span class="material-symbols-outlined text-[36px] text-tertiary">snooze</span>
          <span class="font-headline-md text-on-surface font-bold">Scheduled Rest & CNS Recovery</span>
          <p class="font-body-sm max-w-sm">Sleep goal: 8.5 hrs • Hydration & 30 min light mobility walk.</p>
          <button id="convertRestToWorkoutBtn" class="mt-2 h-11 px-5 rounded-xl bg-surface-container-high hover:bg-surface-bright text-primary font-headline-sm text-sm uppercase flex items-center gap-1.5 shadow-sm active:scale-95">
            <span class="material-symbols-outlined text-[18px]">bolt</span>
            <span>Convert to Active Workout</span>
          </button>
        </div>
      `;
      const convertBtn = document.getElementById('convertRestToWorkoutBtn');
      if (convertBtn) {
        convertBtn.addEventListener('click', () => {
          state.activeWorkout.isRestMode = false;
          renderUnifiedScheduleView();
          showToast('Converted to active workout session');
        });
      }
    } else {
      container.innerHTML = state.activeWorkout.exercises.map((ex, exIdx) => {
        const primaryTag = `${(ex.muscle_group || 'CHEST').toUpperCase()} • ${(ex.modality || 'COMPOUND').toUpperCase()}`;
        
        const hasHistory = ex.hasHistory || ex.sets.some(s => s.completed);
        const lastW = ex.prevWeight || (ex.sets[0]?.weight || 0);
        const lastR = ex.prevReps || (ex.sets[0]?.reps || 0);

        const overloadText = hasHistory && (lastW > 0 || lastR > 0)
          ? `OVERLOAD: +${weightStep} ${state.unit} (PREV: ${lastW} ${state.unit} × ${lastR})`
          : `TARGET: PROGRESSIVE OVERLOAD (PREV: --)`;

        return `
          <div class="exercise-item relative bg-surface-container rounded-xl p-space-sm shadow-md transition-all border border-surface-container-high/30" data-ex-index="${exIdx}">
            <!-- Card Header -->
            <div class="flex items-start justify-between gap-space-xs">
              <button aria-label="Reorder" class="touch-manipulation text-on-surface-variant/40 hover:text-on-surface-variant active:text-primary py-1 pr-1 -ml-1 cursor-grab" type="button">
                <span class="material-symbols-outlined text-[20px]">drag_indicator</span>
              </button>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap mb-1">
                  <span class="font-headline-sm text-[17px] text-on-surface font-bold truncate">${escapeHTML(ex.name)}</span>
                  <span class="px-1.5 py-0.5 rounded bg-surface-container-highest text-on-surface-variant font-label-caps text-[10px] uppercase font-bold">${primaryTag}</span>
                </div>

                <!-- Parameter Configuration Row -->
                <div class="flex items-center gap-2 flex-wrap">
                  <button class="open-customizer-pill flex items-center gap-1 bg-surface-container-lowest hover:bg-surface-container-highest px-2 py-1 rounded transition-colors" data-ex-index="${exIdx}">
                    <span class="material-symbols-outlined text-primary text-[14px]">repeat</span>
                    <span class="font-label-numeric-sm text-label-numeric-sm text-on-surface font-bold">${escapeHTML(ex.target_reps || '3 Sets × 8-10 Reps')}</span>
                  </button>
                  <button class="open-customizer-pill flex items-center gap-1 bg-surface-container-lowest hover:bg-surface-container-highest px-2 py-1 rounded transition-colors" data-ex-index="${exIdx}">
                    <span class="font-label-caps text-label-caps text-on-surface-variant">RPE</span>
                    <span class="font-label-numeric-sm text-label-numeric-sm text-primary font-bold">${escapeHTML(ex.target_rpe || '8.0')}</span>
                  </button>
                  <button class="open-customizer-pill flex items-center gap-1 bg-surface-container-lowest hover:bg-surface-container-highest px-2 py-1 rounded transition-colors" data-ex-index="${exIdx}">
                    <span class="font-label-caps text-label-caps text-on-surface-variant">REST</span>
                    <span class="font-label-numeric-sm text-label-numeric-sm text-tertiary font-medium">${ex.rest_seconds || 90}s</span>
                  </button>
                  ${ex.notes ? `<span class="bg-surface-container-lowest px-2 py-1 rounded text-primary font-label-caps text-[10px] font-bold">${escapeHTML(ex.notes)}</span>` : ''}
                </div>

                <!-- Overload Progress Marker -->
                <div class="mt-1.5 flex items-center gap-1.5 text-secondary font-label-caps text-[10px] font-semibold">
                  <span class="material-symbols-outlined text-[14px]">trending_up</span>
                  <span>${escapeHTML(overloadText)}</span>
                </div>
              </div>

              <!-- Action Buttons -->
              <div class="flex items-center gap-1 shrink-0">
                <button aria-label="Configure Details" class="open-customizer-btn w-9 h-9 rounded-lg bg-surface-container-high flex items-center justify-center text-on-surface-variant hover:text-on-surface active:scale-90 transition-transform" data-ex-index="${exIdx}" title="Configure parameters">
                  <span class="material-symbols-outlined text-[18px]">tune</span>
                </button>
                <button aria-label="Remove Movement" class="remove-movement-btn w-9 h-9 rounded-lg bg-surface-container-high flex items-center justify-center text-on-surface-variant hover:text-error active:scale-90 transition-transform" data-ex-index="${exIdx}" title="Remove exercise">
                  <span class="material-symbols-outlined text-[18px]">close</span>
                </button>
              </div>
            </div>

            <!-- Integrated Live Sets Table with Steppers -->
            <div class="mt-2.5 pt-2 border-t border-surface-container-high/40">
              <div class="grid grid-cols-12 gap-1 px-1 py-1 font-label-caps text-[10px] text-on-surface-variant text-center items-center">
                <span class="col-span-1">Set</span>
                <span class="col-span-3">Prev</span>
                <span class="col-span-4">Weight (${state.unit})</span>
                <span class="col-span-3">Reps</span>
                <span class="col-span-1">Done</span>
              </div>

              <!-- Set Rows -->
              <div class="flex flex-col gap-1.5">
                ${ex.sets.map((set, setIdx) => {
                  const isCompleted = set.completed;
                  const isFirstIncomplete = !isCompleted && ex.sets.findIndex(s => !s.completed) === setIdx;
                  const rowClass = isCompleted 
                    ? 'bg-surface-container-low border-l-2 border-secondary' 
                    : (isFirstIncomplete ? 'bg-surface-container-high border-l-2 border-primary shadow-sm' : 'bg-surface-container-low/60');

                  const prevText = (set.prev_weight != null && set.prev_reps != null && (set.prev_weight > 0 || set.prev_reps > 0))
                    ? `${set.prev_weight} × ${set.prev_reps}`
                    : (hasHistory && (lastW > 0 || lastR > 0) ? `${lastW} × ${lastR}` : '--');

                  return `
                    <div class="grid grid-cols-12 gap-1 items-center p-1.5 rounded-lg transition-all ${rowClass}">
                      <!-- Set # -->
                      <div class="col-span-1 text-center flex flex-col items-center justify-center">
                        <span class="font-label-numeric-md text-label-numeric-md ${isCompleted ? 'text-secondary font-bold' : (isFirstIncomplete ? 'text-primary font-bold' : 'text-on-surface-variant')}">${set.set_number}</span>
                        ${isFirstIncomplete ? '<span class="w-1.5 h-1.5 rounded-full bg-primary animate-ping mt-0.5"></span>' : ''}
                      </div>

                      <!-- Prev Target Hint -->
                      <div class="col-span-3 text-center flex flex-col items-center justify-center min-w-0">
                        <span class="font-label-numeric-sm text-label-numeric-sm text-on-surface-variant/80 truncate">${prevText}</span>
                        ${isFirstIncomplete ? '<span class="font-label-caps text-[9px] text-primary uppercase leading-tight font-bold">Target</span>' : ''}
                      </div>

                      <!-- Weight Steppers & Numeric Box -->
                      <div class="col-span-4 flex items-center justify-center gap-1">
                        <button class="step-btn w-touch-compact h-touch-compact rounded bg-surface-container-highest hover:bg-surface-bright text-on-surface font-label-numeric-sm flex items-center justify-center active:scale-90 transition-transform select-none" data-action="weight-minus" data-ex="${exIdx}" data-set="${setIdx}">-${weightStep}</button>
                        <input class="set-input w-14 h-touch-compact text-center font-label-numeric-md text-label-numeric-md ${isCompleted ? 'text-secondary' : 'text-primary'} bg-surface-container-lowest rounded outline-none border border-transparent focus:border-primary transition-colors" type="number" step="${weightStep}" data-field="weight" data-ex="${exIdx}" data-set="${setIdx}" value="${set.weight}" inputmode="decimal" />
                        <button class="step-btn w-touch-compact h-touch-compact rounded bg-surface-container-highest hover:bg-surface-bright text-on-surface font-label-numeric-sm flex items-center justify-center active:scale-90 transition-transform select-none" data-action="weight-plus" data-ex="${exIdx}" data-set="${setIdx}">+${weightStep}</button>
                      </div>

                      <!-- Reps Steppers & Numeric Box -->
                      <div class="col-span-3 flex items-center justify-center gap-1">
                        <button class="step-btn w-9 h-touch-compact rounded bg-surface-container-highest hover:bg-surface-bright text-on-surface font-label-numeric-sm flex items-center justify-center active:scale-90 transition-transform select-none" data-action="reps-minus" data-ex="${exIdx}" data-set="${setIdx}">-1</button>
                        <input class="set-input w-9 h-touch-compact text-center font-label-numeric-md text-label-numeric-md ${isCompleted ? 'text-secondary' : 'text-primary'} bg-surface-container-lowest rounded outline-none border border-transparent focus:border-primary transition-colors" type="number" step="1" data-field="reps" data-ex="${exIdx}" data-set="${setIdx}" value="${set.reps}" inputmode="numeric" />
                        <button class="step-btn w-9 h-touch-compact rounded bg-surface-container-highest hover:bg-surface-bright text-on-surface font-label-numeric-sm flex items-center justify-center active:scale-90 transition-transform select-none" data-action="reps-plus" data-ex="${exIdx}" data-set="${setIdx}">+1</button>
                      </div>

                      <!-- Complete Button (Checkbox Action) -->
                      <div class="col-span-1 flex items-center justify-center">
                        <button class="complete-set-btn w-10 h-10 rounded-lg flex items-center justify-center active:scale-95 transition-all shadow-sm ${isCompleted ? 'bg-secondary text-on-secondary' : (isFirstIncomplete ? 'bg-primary-container text-on-primary-container' : 'bg-surface-container-highest text-on-surface-variant')}" data-ex="${exIdx}" data-set="${setIdx}">
                          <span class="material-symbols-outlined text-[20px]" style="${isCompleted ? 'font-variation-settings: \'FILL\' 1;' : ''}">
                            ${isCompleted ? 'check' : 'done'}
                          </span>
                        </button>
                      </div>
                    </div>
                  `;
                }).join('')}
              </div>

              <!-- Exercise Bottom Controls -->
              <div class="flex items-center justify-between mt-space-xs pt-1">
                <button class="add-set-btn h-9 px-space-sm rounded bg-surface-container-high hover:bg-surface-bright text-on-surface font-headline-sm text-xs flex items-center gap-1 active:scale-95 transition-transform" data-ex-index="${exIdx}">
                  <span class="material-symbols-outlined text-[16px]">add</span>
                  <span>Add Set</span>
                </button>
                <div class="flex items-center gap-2">
                  <button class="plate-calc-btn text-tertiary font-label-caps text-[11px] uppercase flex items-center gap-0.5 hover:underline" data-ex-index="${exIdx}">
                    <span class="material-symbols-outlined text-[14px]">calculate</span>
                    <span>Plate Calc</span>
                  </button>
                  <button class="delete-last-set-btn text-on-surface-variant/70 hover:text-error font-label-caps text-[11px] uppercase flex items-center gap-0.5" data-ex-index="${exIdx}">
                    <span class="material-symbols-outlined text-[14px]">remove</span>
                    <span>Remove Set</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        `;
      }).join('');
    }

    // 4. Render Cycle Schedule Accordion
    if (accordionContainer) {
      accordionContainer.innerHTML = activeRoutine.days.map((d, idx) => {
        if (idx === state.selectedDayIndex) return '';

        const dayBadgeColor = d.is_rest ? 'bg-tertiary-container/20 text-tertiary' : 'bg-secondary-container/20 text-secondary';

        if (d.is_rest) {
          return `
            <div class="bg-surface-container rounded-xl p-space-sm flex items-center justify-between shadow-sm cursor-pointer hover:bg-surface-container-high transition-colors border border-surface-container-high/30" data-accordion-day="${idx}">
              <div class="flex items-center gap-2.5 min-w-0">
                <span class="px-2 py-1 rounded font-headline-sm text-xs font-bold ${dayBadgeColor}">${d.day}</span>
                <div class="flex flex-col min-w-0">
                  <span class="font-headline-sm text-sm text-on-surface font-bold truncate">Scheduled Rest & CNS Recovery</span>
                  <span class="font-body-sm text-xs text-on-surface-variant truncate">Sleep goal: 8.5 hrs • Hydration & Walk</span>
                </div>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <button class="accordion-convert-btn text-[11px] px-2.5 py-1 rounded-lg bg-surface-container-highest text-primary hover:bg-surface-bright font-label-caps uppercase font-bold transition-all active:scale-95" data-convert-day="${idx}">CONVERT TO WORKOUT</button>
              </div>
            </div>
          `;
        } else {
          const previewNames = d.exercise_ids
            .map(id => state.exercises.find(e => e.id === id)?.name)
            .filter(Boolean)
            .slice(0, 3)
            .map(n => n.split(' ')[0] + ' ' + (n.split(' ')[1] || ''))
            .join(', ');

          return `
            <div class="bg-surface-container rounded-xl p-space-sm flex items-center justify-between shadow-sm cursor-pointer hover:bg-surface-container-high transition-colors border border-surface-container-high/30" data-accordion-day="${idx}">
              <div class="flex items-center gap-2.5 min-w-0">
                <span class="px-2 py-1 rounded font-headline-sm text-xs font-bold ${dayBadgeColor}">${d.day}</span>
                <div class="flex flex-col min-w-0">
                  <span class="font-headline-sm text-sm text-on-surface font-bold truncate">${escapeHTML(d.name)}</span>
                  <span class="font-body-sm text-xs text-on-surface-variant truncate">${d.exercise_ids.length} Exercises • ${previewNames ? escapeHTML(previewNames) + '...' : escapeHTML(d.focus)}</span>
                </div>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <span class="material-symbols-outlined text-on-surface-variant text-[20px]">expand_more</span>
              </div>
            </div>
          `;
        }
      }).join('');
    }

    attachUnifiedScheduleDynamicListeners();
  }

  function attachUnifiedScheduleDynamicListeners() {
    const isLbs = state.unit === 'lbs';
    const weightStep = isLbs ? 5 : 2.5;

    // Steppers (+ / -)
    document.querySelectorAll('.step-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const action = btn.getAttribute('data-action');
        const exIdx = parseInt(btn.getAttribute('data-ex'), 10);
        const setIdx = parseInt(btn.getAttribute('data-set'), 10);
        const targetEx = state.activeWorkout.exercises[exIdx];
        const targetSet = targetEx?.sets[setIdx];
        if (!targetSet) return;

        if (action === 'weight-minus') {
          targetSet.weight = Math.max(0, Math.round((Number(targetSet.weight) - weightStep) * 10) / 10);
        } else if (action === 'weight-plus') {
          targetSet.weight = Math.round((Number(targetSet.weight) + weightStep) * 10) / 10;
        } else if (action === 'reps-minus') {
          targetSet.reps = Math.max(0, parseInt(targetSet.reps, 10) - 1);
        } else if (action === 'reps-plus') {
          targetSet.reps = parseInt(targetSet.reps, 10) + 1;
        }

        // Persist to exercise_history immediately
        if (targetEx.exercise_id && (targetSet.weight > 0 || targetSet.reps > 0)) {
          await window.ironPulseDB.updateExercisePerformance(targetEx.exercise_id, targetSet.weight, targetSet.reps, targetEx.sets.length);
          targetEx.hasHistory = true;
          targetEx.prevWeight = targetSet.weight;
          targetEx.prevReps = targetSet.reps;
        }

        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
      });
    });

    // Inputs direct editing
    document.querySelectorAll('.set-input').forEach(input => {
      input.addEventListener('change', async () => {
        const exIdx = parseInt(input.getAttribute('data-ex'), 10);
        const setIdx = parseInt(input.getAttribute('data-set'), 10);
        const field = input.getAttribute('data-field');
        const targetEx = state.activeWorkout.exercises[exIdx];
        const targetSet = targetEx?.sets[setIdx];
        if (!targetSet) return;

        const val = parseFloat(input.value) || 0;
        targetSet[field] = val;

        if (targetEx.exercise_id && (targetSet.weight > 0 || targetSet.reps > 0)) {
          await window.ironPulseDB.updateExercisePerformance(targetEx.exercise_id, targetSet.weight, targetSet.reps, targetEx.sets.length);
          targetEx.hasHistory = true;
          targetEx.prevWeight = targetSet.weight;
          targetEx.prevReps = targetSet.reps;
        }

        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
      });
    });

    // Complete Set Button
    document.querySelectorAll('.complete-set-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const exIdx = parseInt(btn.getAttribute('data-ex'), 10);
        const setIdx = parseInt(btn.getAttribute('data-set'), 10);
        const targetEx = state.activeWorkout.exercises[exIdx];
        const targetSet = targetEx?.sets[setIdx];
        if (!targetSet) return;

        const willBeComplete = !targetSet.completed;
        targetSet.completed = willBeComplete;

        if (targetEx.exercise_id && (targetSet.weight > 0 || targetSet.reps > 0)) {
          await window.ironPulseDB.updateExercisePerformance(targetEx.exercise_id, targetSet.weight, targetSet.reps, targetEx.sets.length);
          targetEx.hasHistory = true;
          targetEx.prevWeight = targetSet.weight;
          targetEx.prevReps = targetSet.reps;

          // Propagate prev target and initial weight/reps to subsequent incomplete sets
          if (willBeComplete) {
            for (let i = setIdx + 1; i < targetEx.sets.length; i++) {
              const nextSet = targetEx.sets[i];
              if (!nextSet.completed) {
                nextSet.prev_weight = targetSet.weight;
                nextSet.prev_reps = targetSet.reps;
                if (nextSet.weight === 0 && nextSet.reps === 0) {
                  nextSet.weight = targetSet.weight;
                  nextSet.reps = targetSet.reps;
                }
              }
            }
          }
        }

        renderUnifiedScheduleView();
        await saveActiveWorkoutState();

        if (willBeComplete) {
          showToast(`Set ${targetSet.set_number} Logged (${targetSet.weight} ${state.unit} × ${targetSet.reps})`, 'check_circle', true);
          startRestTimer(targetEx.rest_seconds || 90);
        }
      });
    });

    // Add Set to Exercise
    document.querySelectorAll('.add-set-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const exIdx = parseInt(btn.getAttribute('data-ex-index'), 10);
        const ex = state.activeWorkout.exercises[exIdx];
        if (!ex) return;

        const lastSet = ex.sets[ex.sets.length - 1];
        const newSetNumber = ex.sets.length + 1;
        const newWeight = lastSet ? lastSet.weight : (ex.prevWeight || 0);
        const newReps = lastSet ? lastSet.reps : (ex.prevReps || 0);

        ex.sets.push({
          set_number: newSetNumber,
          prev_weight: lastSet ? lastSet.weight : null,
          prev_reps: lastSet ? lastSet.reps : null,
          weight: newWeight,
          reps: newReps,
          completed: false
        });

        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
        showToast(`Added Set ${newSetNumber} to ${ex.name}`);
      });
    });

    // Delete Last Set
    document.querySelectorAll('.delete-last-set-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const exIdx = parseInt(btn.getAttribute('data-ex-index'), 10);
        const ex = state.activeWorkout.exercises[exIdx];
        if (!ex || ex.sets.length <= 1) return;

        ex.sets.pop();
        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
      });
    });

    // Remove Movement from Routine (State stays in IndexedDB exercise_history so re-adding restores saved weights!)
    document.querySelectorAll('.remove-movement-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const exIdx = parseInt(btn.getAttribute('data-ex-index'), 10);
        const ex = state.activeWorkout.exercises[exIdx];
        if (!ex) return;

        // Ensure current weights are remembered before removal
        const validSet = ex.sets.find(s => s.weight > 0 || s.reps > 0) || ex.sets[0];
        if (validSet && (validSet.weight > 0 || validSet.reps > 0)) {
          await window.ironPulseDB.updateExercisePerformance(ex.exercise_id, validSet.weight, validSet.reps, ex.sets.length);
        }

        state.activeWorkout.exercises.splice(exIdx, 1);
        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
        showToast(`Removed "${ex.name}" (Data saved in memory)`);
      });
    });

    // Open Parameter Customizer Modal
    document.querySelectorAll('.open-customizer-btn, .open-customizer-pill').forEach(btn => {
      btn.addEventListener('click', () => {
        const exIdx = parseInt(btn.getAttribute('data-ex-index'), 10);
        openParameterSettingsModal(exIdx);
      });
    });

    // Plate Calculator
    document.querySelectorAll('.plate-calc-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const exIdx = parseInt(btn.getAttribute('data-ex-index'), 10);
        const ex = state.activeWorkout.exercises[exIdx];
        const activeWeight = ex?.sets[0]?.weight || 0;
        openPlateCalculatorModal(activeWeight, ex?.name || 'Exercise');
      });
    });

    // Accordion Convert to Workout Button
    document.querySelectorAll('.accordion-convert-btn').forEach(btn => {
      btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        const dayIdx = parseInt(btn.getAttribute('data-convert-day'), 10);
        await loadDayWorkout(dayIdx);
        state.activeWorkout.isRestMode = false;
        renderUnifiedScheduleView();
        window.scrollTo({ top: 0, behavior: 'smooth' });
        showToast('Converted to active workout session!');
      });
    });

    // Accordion Day Click
    document.querySelectorAll('[data-accordion-day]').forEach(item => {
      item.addEventListener('click', async (e) => {
        if (e.target.closest('.accordion-convert-btn')) return;
        const targetDayIdx = parseInt(item.getAttribute('data-accordion-day'), 10);
        await loadDayWorkout(targetDayIdx);
        renderUnifiedScheduleView();
        window.scrollTo({ top: 0, behavior: 'smooth' });
        showToast(`Loaded ${state.activeWorkout.title}`);
      });
    });
  }

  function setupUnifiedScheduleListeners() {
    // 7-Day Strip Click
    const daysStrip = document.getElementById('unifiedDaysStrip');
    if (daysStrip) {
      daysStrip.addEventListener('click', async (e) => {
        const pill = e.target.closest('.unified-day-pill');
        if (!pill) return;
        const dayIdx = parseInt(pill.getAttribute('data-day-index'), 10);
        await loadDayWorkout(dayIdx);
        renderUnifiedScheduleView();
      });
    }

    // Prev / Next Day Switching Buttons
    const prevDayBtn = document.getElementById('prevDayBtn');
    const nextDayBtn = document.getElementById('nextDayBtn');

    if (prevDayBtn) {
      prevDayBtn.addEventListener('click', async () => {
        const activeRoutine = state.routines.find(r => r.id === state.currentSplitId) || state.routines[0];
        const totalDays = activeRoutine ? activeRoutine.days.length : 7;
        const newIdx = (state.selectedDayIndex - 1 + totalDays) % totalDays;
        await loadDayWorkout(newIdx);
        renderUnifiedScheduleView();
      });
    }

    if (nextDayBtn) {
      nextDayBtn.addEventListener('click', async () => {
        const activeRoutine = state.routines.find(r => r.id === state.currentSplitId) || state.routines[0];
        const totalDays = activeRoutine ? activeRoutine.days.length : 7;
        const newIdx = (state.selectedDayIndex + 1) % totalDays;
        await loadDayWorkout(newIdx);
        renderUnifiedScheduleView();
      });
    }

    // Split Template Pills
    document.querySelectorAll('.split-pill').forEach(pill => {
      pill.addEventListener('click', async () => {
        state.currentSplitId = pill.getAttribute('data-split-id') || 'ppl';
        state.selectedDayIndex = 0;
        await window.ironPulseDB.setSetting('selected_split_id', state.currentSplitId);
        await window.ironPulseDB.setSetting('selected_day_index', 0);
        await loadDayWorkout(0);
        renderUnifiedScheduleView();
        showToast(`Active Split: ${pill.textContent.trim()}`);
      });
    });

    // Rest Day Mode Toggle
    const restToggleBtn = document.getElementById('restToggleBtn');
    if (restToggleBtn) {
      restToggleBtn.addEventListener('click', async () => {
        state.activeWorkout.isRestMode = !state.activeWorkout.isRestMode;
        renderUnifiedScheduleView();
        await saveActiveWorkoutState();
        showToast(state.activeWorkout.isRestMode ? 'Rest Day Activated' : 'Active Training Mode');
      });
    }

    // Add Exercise Button (Top Bar) & Browse Catalog Card
    const addExBtn = document.getElementById('addExerciseToDayBtn');
    const browseCardBtn = document.getElementById('browseCatalogCardBtn');
    if (addExBtn) addExBtn.addEventListener('click', () => { window.location.hash = 'exercises'; });
    if (browseCardBtn) browseCardBtn.addEventListener('click', () => { window.location.hash = 'exercises'; });

    // Save Routine Local
    const saveRoutineBtn = document.getElementById('saveRoutineLocalBtn');
    if (saveRoutineBtn) {
      saveRoutineBtn.addEventListener('click', async () => {
        await saveActiveWorkoutState();
        showToast('Routine configuration saved!');
      });
    }

    // Start Today / Finish Workout Button
    const startTodayBtn = document.getElementById('startTodayWorkoutBtn');
    if (startTodayBtn) {
      startTodayBtn.addEventListener('click', async () => {
        let completedCount = 0;
        let totalVol = 0;
        const setsToSave = [];

        state.activeWorkout.exercises.forEach(ex => {
          ex.sets.forEach(s => {
            if (s.completed) {
              completedCount++;
              totalVol += (Number(s.weight) || 0) * (Number(s.reps) || 0);
              setsToSave.push({
                exercise_id: ex.exercise_id,
                set_number: s.set_number,
                weight: s.weight,
                reps: s.reps,
                completed: true
              });
            }
          });
        });

        if (completedCount === 0) {
          showToast('Session Active! Tap [Done] on sets when finished.', 'bolt', true);
          return;
        }

        const sessionData = {
          title: state.activeWorkout.title,
          start_time: state.activeWorkout.startTime,
          duration_seconds: state.activeWorkout.elapsedSeconds,
          unit: state.unit,
          notes: ''
        };

        await window.ironPulseDB.finishWorkout(sessionData, setsToSave);
        showToast(`Logged Workout! Total Tonnage: ${totalVol.toLocaleString()} ${state.unit}`, 'military_tech', true);
        window.location.hash = 'history';
      });
    }
  }

  // --- Parameter Settings & Customizer Modal Engine ---

  function openParameterSettingsModal(exIndex = 0) {
    state.selectedExIndexForCustomizer = exIndex;
    const ex = state.activeWorkout.exercises[exIndex];
    if (!ex) return;

    const modal = document.getElementById('exerciseSettingsModal');
    const titleEl = document.getElementById('settingsExModalTitle');
    const repRangeInput = document.getElementById('settingsRepRangeInput');
    const rpeInput = document.getElementById('settingsRPEInput');
    const restInput = document.getElementById('settingsRestInput');
    const tempoInput = document.getElementById('settingsTempoInput');

    if (titleEl) titleEl.textContent = `Customize: ${ex.name}`;
    if (repRangeInput) repRangeInput.value = ex.target_reps || '3 Sets × 8-10 Reps';
    if (rpeInput) rpeInput.value = ex.target_rpe || '8.0';
    if (restInput) restInput.value = ex.rest_seconds || 90;
    if (tempoInput) tempoInput.value = ex.notes || '';

    if (modal) {
      modal.classList.remove('hidden');
      modal.classList.add('flex');
    }
  }

  function setupParameterSettingsModalListeners() {
    const modal = document.getElementById('exerciseSettingsModal');
    const closeBtn = document.getElementById('closeSettingsModalBtn');
    const saveBtn = document.getElementById('saveExerciseSettingsBtn');

    const repRangeInput = document.getElementById('settingsRepRangeInput');
    const rpeInput = document.getElementById('settingsRPEInput');
    const restInput = document.getElementById('settingsRestInput');
    const tempoInput = document.getElementById('settingsTempoInput');

    function closeModal() {
      if (modal) {
        modal.classList.add('hidden');
        modal.classList.remove('flex');
      }
    }

    if (closeBtn) closeBtn.addEventListener('click', closeModal);
    if (modal) {
      modal.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
      });
    }

    if (saveBtn) {
      saveBtn.addEventListener('click', async () => {
        const ex = state.activeWorkout.exercises[state.selectedExIndexForCustomizer];
        if (ex) {
          ex.target_reps = repRangeInput?.value || ex.target_reps;
          ex.target_rpe = rpeInput?.value || ex.target_rpe;
          ex.rest_seconds = parseInt(restInput?.value, 10) || ex.rest_seconds;
          ex.notes = tempoInput?.value || '';

          renderUnifiedScheduleView();
          await saveActiveWorkoutState();
          showToast(`Applied custom parameters to "${ex.name}"`);
        }
        closeModal();
      });
    }
  }

  // --- Rest Timer Overlay Engine ---

  function startRestTimer(durationSeconds = 90) {
    if (state.restTimer.intervalId) clearInterval(state.restTimer.intervalId);

    state.restTimer.isActive = true;
    state.restTimer.totalSeconds = durationSeconds;
    state.restTimer.remainingSeconds = durationSeconds;

    const timerWidget = document.getElementById('rest-timer-widget');
    if (timerWidget) timerWidget.classList.remove('hidden');

    updateRestTimerUI();

    state.restTimer.intervalId = setInterval(() => {
      if (state.restTimer.remainingSeconds > 0) {
        state.restTimer.remainingSeconds--;
        updateRestTimerUI();
      } else {
        clearInterval(state.restTimer.intervalId);
        state.restTimer.isActive = false;
        playTimerChime();
        showToast('Rest interval complete! Time for next set.', 'timer', true);
        setTimeout(() => {
          if (!state.restTimer.isActive && timerWidget) timerWidget.classList.add('hidden');
        }, 1800);
      }
    }, 1000);
  }

  function updateRestTimerUI() {
    const display = document.getElementById('rest-time-display');
    const linearProgress = document.getElementById('timer-progress');
    const circleProgress = document.getElementById('circle-progress');
    if (!display) return;

    const r = state.restTimer.remainingSeconds;
    const m = Math.floor(r / 60);
    const s = r % 60;
    display.textContent = `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;

    const pct = Math.min(100, Math.max(0, (r / state.restTimer.totalSeconds) * 100));
    if (linearProgress) linearProgress.style.width = pct + '%';
    if (circleProgress) circleProgress.setAttribute('stroke-dasharray', `${pct}, 100`);
  }

  function setupRestTimerListeners() {
    const add30sBtn = document.getElementById('add-rest-30s');
    const skipBtn = document.getElementById('skip-rest-btn');
    const timerWidget = document.getElementById('rest-timer-widget');

    if (add30sBtn) {
      add30sBtn.addEventListener('click', () => {
        state.restTimer.remainingSeconds += 30;
        state.restTimer.totalSeconds = Math.max(state.restTimer.totalSeconds, state.restTimer.remainingSeconds);
        updateRestTimerUI();
        showToast('+30s Rest Added');
      });
    }

    if (skipBtn) {
      skipBtn.addEventListener('click', () => {
        clearInterval(state.restTimer.intervalId);
        state.restTimer.isActive = false;
        state.restTimer.remainingSeconds = 0;
        if (timerWidget) timerWidget.classList.add('hidden');
        showToast('Rest skipped');
      });
    }
  }

  // --- Exercise Catalog Engine ---

  function renderCatalogView() {
    const listContainer = document.getElementById('catalogExerciseList');
    const catalogCountEl = document.getElementById('catalogTotalCount');
    if (!listContainer) return;

    const q = state.catalogSearchQuery.toLowerCase().trim();
    const groupFilter = state.catalogFilterGroup;
    const modalityFilter = state.catalogFilterModality;

    const filtered = state.exercises.filter(ex => {
      const matchQuery = !q || ex.name.toLowerCase().includes(q) || (ex.secondary_muscles && ex.secondary_muscles.some(m => m.toLowerCase().includes(q)));
      
      let matchGroup = true;
      if (groupFilter !== 'all') {
        const mg = (ex.muscle_group || '').toLowerCase();
        if (groupFilter === 'chest') matchGroup = mg.includes('chest');
        else if (groupFilter === 'back') matchGroup = mg.includes('back');
        else if (groupFilter === 'delts' || groupFilter === 'shoulders') matchGroup = mg.includes('shoulder') || mg.includes('delt');
        else if (groupFilter === 'arms') matchGroup = mg.includes('bicep') || mg.includes('tricep') || mg.includes('arm');
        else if (groupFilter === 'forearms') matchGroup = mg.includes('forearm') || mg.includes('wrist') || mg.includes('grip');
        else if (groupFilter === 'neck') matchGroup = mg.includes('neck');
        else if (groupFilter === 'core') matchGroup = mg.includes('core') || mg.includes('ab');
        else if (groupFilter === 'legs') matchGroup = mg.includes('leg') || mg.includes('calf') || mg.includes('calves');
        else matchGroup = mg.includes(groupFilter);
      }

      let matchModality = true;
      if (modalityFilter) {
        matchModality = (ex.modality || '').toLowerCase() === modalityFilter.toLowerCase();
      }

      return matchQuery && matchGroup && matchModality;
    });

    if (catalogCountEl) {
      catalogCountEl.textContent = `${state.exercises.length} Movements`;
    }

    listContainer.innerHTML = filtered.map(ex => {
      return `
        <div class="exercise-card bg-surface-container rounded-xl p-space-md flex flex-col gap-space-sm shadow-md transition-all hover:bg-surface-container-high border border-surface-container-high/30" data-id="${ex.id}">
          <div class="flex items-start justify-between gap-space-xs">
            <div class="flex items-center gap-space-sm min-w-0">
              <div class="w-12 h-12 rounded-xl shrink-0 bg-surface-container-highest flex items-center justify-center text-primary-container shadow-inner">
                <span class="material-symbols-outlined text-[24px]">fitness_center</span>
              </div>
              <div class="flex flex-col min-w-0">
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="font-headline-sm text-headline-sm text-on-surface truncate">${escapeHTML(ex.name)}</span>
                  ${ex.tier ? `<span class="bg-primary-container/20 text-primary-container px-1.5 py-0.5 rounded font-label-caps text-label-caps uppercase shrink-0 font-bold">${escapeHTML(ex.tier)}</span>` : ''}
                </div>
                <span class="font-body-sm text-body-sm text-on-surface-variant truncate">${escapeHTML(ex.mechanic || 'Compound')} • ${escapeHTML(ex.equipment || 'Bodyweight')}</span>
              </div>
            </div>
            <button class="add-to-schedule-btn h-10 px-4 rounded-lg bg-primary-container text-on-primary font-label-numeric-sm text-label-numeric-sm font-bold flex items-center gap-1 active:scale-95 transition-all shadow-sm shrink-0" data-id="${ex.id}">
              <span class="material-symbols-outlined text-[18px]">add</span>
              <span>Add</span>
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-1.5">
            <span class="px-2 py-0.5 rounded bg-surface-container-high text-on-surface font-label-caps text-label-caps uppercase tracking-wider">${escapeHTML(ex.muscle_group)}</span>
            <span class="px-2 py-0.5 rounded bg-surface-container-high text-on-surface-variant font-label-caps text-label-caps uppercase tracking-wider">${escapeHTML(ex.modality)}</span>
          </div>
        </div>
      `;
    }).join('');

    // Attach Add to Schedule listeners (Restores previously saved weight/reps if existing!)
    document.querySelectorAll('.add-to-schedule-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const id = btn.getAttribute('data-id');
        const ex = state.exercises.find(item => item.id === id);
        if (!ex) return;

        // Check if user previously logged weight/reps for this exercise
        const prevData = await window.ironPulseDB.getPreviousPerformance(ex.id);
        const savedWeight = prevData.hasHistory ? prevData.last_weight : 0;
        const savedReps = prevData.hasHistory ? prevData.last_reps : 0;
        const defaultSets = 3;

        const sets = [];
        for (let s = 1; s <= defaultSets; s++) {
          sets.push({
            set_number: s,
            prev_weight: prevData.hasHistory ? prevData.last_weight : null,
            prev_reps: prevData.hasHistory ? prevData.last_reps : null,
            weight: savedWeight,
            reps: savedReps,
            completed: false
          });
        }

        state.activeWorkout.exercises.push({
          exercise_id: ex.id,
          name: ex.name,
          muscle_group: ex.muscle_group,
          modality: ex.modality,
          target_reps: '3 Sets × 8-10 Reps',
          target_rpe: '8.0',
          rest_seconds: 90,
          notes: '',
          hasHistory: prevData.hasHistory,
          prevWeight: prevData.last_weight,
          prevReps: prevData.last_reps,
          sets
        });

        await saveActiveWorkoutState();
        showToast(`Added "${ex.name}" ${prevData.hasHistory ? `(Restored: ${savedWeight} ${state.unit} × ${savedReps})` : ''}`);
        window.location.hash = 'workout';
      });
    });
  }

  function setupCatalogListeners() {
    const searchInput = document.getElementById('catalogSearchInput');
    const clearBtn = document.getElementById('catalogClearSearchBtn');

    if (searchInput) {
      searchInput.addEventListener('input', () => {
        state.catalogSearchQuery = searchInput.value;
        if (clearBtn) clearBtn.classList.toggle('hidden', state.catalogSearchQuery.length === 0);
        renderCatalogView();
      });
    }

    if (clearBtn && searchInput) {
      clearBtn.addEventListener('click', () => {
        searchInput.value = '';
        state.catalogSearchQuery = '';
        clearBtn.classList.add('hidden');
        renderCatalogView();
        searchInput.focus();
      });
    }

    // Muscle Group Pills
    document.querySelectorAll('#catalogMuscleFilterPills .filter-pill').forEach(pill => {
      pill.addEventListener('click', () => {
        document.querySelectorAll('#catalogMuscleFilterPills .filter-pill').forEach(p => {
          p.classList.remove('bg-primary-container', 'text-on-primary');
          p.classList.add('bg-surface-container', 'text-on-surface-variant');
        });
        pill.classList.remove('bg-surface-container', 'text-on-surface-variant');
        pill.classList.add('bg-primary-container', 'text-on-primary');

        state.catalogFilterGroup = pill.getAttribute('data-filter') || 'all';
        renderCatalogView();
      });
    });

    // Modality Chips
    document.querySelectorAll('.catalog-modality-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        const text = chip.getAttribute('data-modality') || chip.textContent.trim();
        if (state.catalogFilterModality === text) {
          state.catalogFilterModality = null;
          chip.classList.remove('bg-tertiary-container', 'text-on-tertiary-container', 'font-bold');
          chip.classList.add('bg-surface-container-low', 'text-on-surface-variant');
        } else {
          document.querySelectorAll('.catalog-modality-chip').forEach(c => {
            c.classList.remove('bg-tertiary-container', 'text-on-tertiary-container', 'font-bold');
            c.classList.add('bg-surface-container-low', 'text-on-surface-variant');
          });
          state.catalogFilterModality = text;
          chip.classList.remove('bg-surface-container-low', 'text-on-surface-variant');
          chip.classList.add('bg-tertiary-container', 'text-on-tertiary-container', 'font-bold');
        }
        renderCatalogView();
      });
    });
  }

  // --- Custom Exercise Modal Engine ---

  function setupCustomExerciseModalListeners() {
    const modal = document.getElementById('customExerciseModal');
    const openBtn = document.getElementById('openCustomExerciseModalBtn');
    const closeBtn = document.getElementById('closeCustomModalBtn');
    const saveBtn = document.getElementById('saveCustomExerciseBtn');
    const nameInput = document.getElementById('customExNameInput');
    const groupSelect = document.getElementById('customExMuscleGroup');
    const modalitySelect = document.getElementById('customExModality');

    function openModal() {
      if (modal) {
        modal.classList.remove('hidden');
        modal.classList.add('flex');
        if (nameInput) setTimeout(() => nameInput.focus(), 80);
      }
    }

    function closeModal() {
      if (modal) {
        modal.classList.add('hidden');
        modal.classList.remove('flex');
      }
    }

    if (openBtn) openBtn.addEventListener('click', openModal);
    if (closeBtn) closeBtn.addEventListener('click', closeModal);

    if (modal) {
      modal.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
      });
    }

    if (saveBtn) {
      saveBtn.addEventListener('click', async () => {
        const name = (nameInput?.value || '').trim();
        if (!name) {
          alert('Please enter an exercise name.');
          return;
        }

        const newEx = await window.ironPulseDB.addCustomExercise({
          name,
          muscle_group: groupSelect?.value || 'Chest',
          modality: modalitySelect?.value || 'Free Weights',
          equipment: 'Custom',
          tier: 'Intermediate'
        });

        state.exercises.unshift(newEx);
        closeModal();
        if (nameInput) nameInput.value = '';

        renderCatalogView();
        showToast(`Created custom exercise: "${name}"`, 'add_circle', true);
      });
    }
  }

  // --- Plate Calculator Modal Engine ---

  function openPlateCalculatorModal(targetWeight = 0, exerciseName = 'Barbell Bench Press') {
    const modal = document.getElementById('plateCalcModal');
    const titleEl = document.getElementById('plateCalcExerciseName');
    const weightInput = document.getElementById('plateCalcWeightInput');
    const barWeightSelect = document.getElementById('plateCalcBarWeight');
    const resultsContainer = document.getElementById('plateCalcPlatesList');
    const totalCalcEl = document.getElementById('plateCalcTotal');
    if (!modal) return;

    const isLbs = state.unit === 'lbs';

    if (titleEl) titleEl.textContent = exerciseName;
    if (weightInput) {
      weightInput.value = targetWeight || (isLbs ? 135 : 60);
      weightInput.step = isLbs ? '5' : '2.5';
    }

    if (barWeightSelect) {
      if (isLbs) {
        barWeightSelect.innerHTML = `
          <option value="45" selected>Olympic Bar (45 lbs)</option>
          <option value="35">Women's Bar (35 lbs)</option>
          <option value="25">EZ-Curl Bar (25 lbs)</option>
          <option value="0">Zero / Dumbbell (0 lbs)</option>
        `;
      } else {
        barWeightSelect.innerHTML = `
          <option value="20" selected>Olympic Bar (20 kg)</option>
          <option value="15">Women's Bar (15 kg)</option>
          <option value="10">EZ-Curl Bar (10 kg)</option>
          <option value="0">Zero / Dumbbell (0 kg)</option>
        `;
      }
    }

    function renderPlates() {
      const target = parseFloat(weightInput?.value) || 0;
      const chosenBar = barWeightSelect ? parseFloat(barWeightSelect.value) : (isLbs ? 45 : 20);
      const calc = calculatePlates(target, isLbs, chosenBar);

      if (totalCalcEl) totalCalcEl.textContent = `${calc.totalCalculated} ${state.unit} ${calc.remainder > 0 ? `(+${calc.remainder}${state.unit} rem)` : ''}`;

      if (resultsContainer) {
        if (calc.platesPerSide.length === 0) {
          resultsContainer.innerHTML = `<span class="text-on-surface-variant font-body-sm">Bar only (${calc.barWeight} ${state.unit}) — No plates needed per side.</span>`;
        } else {
          resultsContainer.innerHTML = `
            <div class="flex flex-col gap-2 w-full">
              <span class="font-label-caps text-on-surface-variant uppercase text-xs font-bold">Plates Per Side:</span>
              <div class="flex items-center gap-2 flex-wrap">
                ${calc.platesPerSide.map(p => {
                  let colorClass = 'bg-primary-container text-on-primary font-bold';
                  if (p >= 35 || (p >= 25 && !isLbs)) colorClass = 'bg-error text-on-error font-bold';
                  else if (p >= 20) colorClass = 'bg-tertiary-container text-on-tertiary-container font-bold';
                  else if (p >= 10) colorClass = 'bg-secondary-container text-on-secondary-container font-bold';
                  return `<span class="px-3 py-1.5 rounded-lg ${colorClass} font-label-numeric-md text-sm shadow-sm">${p} ${state.unit}</span>`;
                }).join('')}
              </div>
            </div>
          `;
        }
      }
    }

    renderPlates();

    if (weightInput) weightInput.oninput = renderPlates;
    if (barWeightSelect) barWeightSelect.onchange = renderPlates;

    modal.classList.remove('hidden');
    modal.classList.add('flex');

    const closeBtn = document.getElementById('closePlateCalcBtn');
    if (closeBtn) {
      closeBtn.onclick = () => {
        modal.classList.add('hidden');
        modal.classList.remove('flex');
      };
    }
  }

  // --- History View Engine ---

  async function renderHistoryView() {
    const listContainer = document.getElementById('historySessionsList');
    const totalTonnageEl = document.getElementById('historyTotalTonnage');
    const sessionsCountEl = document.getElementById('historySessionsCount');
    const prCountEl = document.getElementById('historyPRCount');
    const sparklineEl = document.getElementById('historySparklineContainer');
    if (!listContainer) return;

    state.historySessions = await window.ironPulseDB.getWorkoutHistory();
    const telemetry = await window.ironPulseDB.getTelemetryStats();

    if (totalTonnageEl) totalTonnageEl.textContent = telemetry.total_volume.toLocaleString();
    if (sessionsCountEl) sessionsCountEl.textContent = `${telemetry.total_sessions}`;
    if (prCountEl) prCountEl.textContent = `${Math.max(0, telemetry.total_sessions)}`;

    // Overload 7-Day Sparkline Chart
    if (sparklineEl) {
      const maxDaily = Math.max(1, ...telemetry.daily_distribution);
      const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      sparklineEl.innerHTML = telemetry.daily_distribution.map((vol, idx) => {
        const heightPct = Math.max(8, Math.round((vol / maxDaily) * 100));
        const isToday = idx === telemetry.current_day_index;
        const barColor = vol > 0 ? (isToday ? 'bg-primary-container' : 'bg-secondary') : 'bg-surface-container-highest';
        const labelColor = isToday ? 'text-primary font-bold' : 'text-on-surface-variant';

        return `
          <div class="flex flex-col items-center gap-1 w-8">
            <div class="w-full ${barColor} rounded-t transition-all duration-500" style="height: ${heightPct}px;" title="${vol.toLocaleString()} ${state.unit}"></div>
            <span class="font-label-caps text-label-caps ${labelColor}">${days[idx]}</span>
          </div>
        `;
      }).join('');
    }

    if (state.historySessions.length === 0) {
      listContainer.innerHTML = `
        <div class="bg-surface-container rounded-xl p-space-lg text-center flex flex-col items-center justify-center gap-2 shadow-sm my-2">
          <span class="material-symbols-outlined text-[36px] text-on-surface-variant">calendar_month</span>
          <span class="font-headline-sm text-on-surface font-bold">No Completed Workouts Yet</span>
          <p class="font-body-sm text-on-surface-variant">Log and finish your first training session to view your overload trajectory.</p>
        </div>
      `;
      return;
    }

    listContainer.innerHTML = state.historySessions.map(session => {
      const sDate = new Date(session.date);
      const formattedDate = sDate.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
      const durationMins = Math.round((session.duration_seconds || 0) / 60);
      const unitStr = session.unit || state.unit;

      return `
        <article class="flex flex-col p-space-sm rounded-xl bg-surface-container shadow-md gap-space-sm border border-surface-container-high/30">
          <div class="flex items-start justify-between">
            <div class="flex flex-col min-w-0">
              <h3 class="font-headline-sm text-headline-sm text-on-surface font-bold truncate">${escapeHTML(session.title)}</h3>
              <div class="flex items-center gap-space-xs mt-1 text-on-surface-variant font-body-sm text-body-sm flex-wrap">
                <span class="text-primary font-medium">${formattedDate}</span>
                <span>•</span>
                <span class="flex items-center gap-0.5"><span class="material-symbols-outlined text-[14px]">timer</span> ${durationMins} min</span>
                <span>•</span>
                <span class="font-label-numeric-sm text-label-numeric-sm text-on-surface font-bold">${session.total_volume.toLocaleString()} ${unitStr}</span>
              </div>
            </div>
            <div class="flex items-center gap-1.5 shrink-0">
              <span class="px-2 py-0.5 rounded-full bg-secondary-container/20 text-secondary font-label-caps text-label-caps font-bold">LOGGED</span>
              <button class="delete-history-btn p-1.5 text-on-surface-variant hover:text-error rounded-lg" data-session-id="${session.id}">
                <span class="material-symbols-outlined text-[18px]">delete</span>
              </button>
            </div>
          </div>
        </article>
      `;
    }).join('');

    // Attach Delete Listeners
    document.querySelectorAll('.delete-history-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        const sId = parseInt(btn.getAttribute('data-session-id'), 10);
        if (confirm('Delete this workout log?')) {
          await window.ironPulseDB.deleteWorkoutSession(sId);
          renderHistoryView();
          showToast('Workout log deleted');
        }
      });
    });
  }

  // --- Sync & Settings Engine ---

  async function renderSyncView() {
    updateUnitUI();
  }

  function setupSyncListeners() {
    const exportBtn = document.getElementById('exportBackupBtn');
    if (exportBtn) {
      exportBtn.addEventListener('click', async () => {
        const backup = await window.ironPulseDB.exportBackup();
        const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `ironpulse_backup_${new Date().toISOString().slice(0, 10)}.json`;
        a.click();
        URL.revokeObjectURL(url);
        showToast('Backup JSON exported successfully!');
      });
    }

    const importInput = document.getElementById('importBackupFileInput');
    const importBtn = document.getElementById('importBackupBtn');
    if (importBtn && importInput) {
      importBtn.addEventListener('click', () => importInput.click());
      importInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        try {
          const text = await file.text();
          const json = JSON.parse(text);
          await window.ironPulseDB.importBackup(json);
          state.exercises = await window.ironPulseDB.getAllExercises();
          renderUnifiedScheduleView();
          renderCatalogView();
          renderHistoryView();
          renderSyncView();
          showToast('Backup imported successfully!', 'cloud_done', true);
        } catch (err) {
          alert('Failed to import backup file: ' + err.message);
        }
      });
    }
  }

  // --- Utility Functions ---
  function escapeHTML(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // --- DOM Ready Bootstrapper ---
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }

})();
