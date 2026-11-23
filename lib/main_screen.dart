import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_service.dart';
import 'app_database.dart';
import 'app_theme.dart';
import 'calendar_page.dart';
import 'focus_timer_dialog.dart';
import 'live_voice_screen.dart';
import 'routines_page.dart';
import 'screens/deepseek_web_screen.dart';
import 'settings_page.dart';
import 'statistics_page.dart';
import 'today_page.dart';

class MainScreen extends StatefulWidget {
  final AppDatabase db;
  final String appTitle;
  final ValueChanged<ThemeMode> onThemeChanged;
  final Future<void> Function({String? title, int? leadTime, String? refreshMode}) onAppSettingsChanged;

  const MainScreen({
    super.key,
    required this.db,
    required this.appTitle,
    required this.onThemeChanged,
    required this.onAppSettingsChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int currentIndex = 0;
  late PageController pageController;
  DateTime selectedDate = DateTime.now();

  OverlayEntry? _confettiEntry;
  static const MethodChannel _widgetChannel = MethodChannel('taskify/widget');

  final GlobalKey<TodayPageState> todayKey = GlobalKey<TodayPageState>();
  final GlobalKey<CalendarPageState> calendarKey = GlobalKey<CalendarPageState>();
  final GlobalKey<StatisticsPageState> statsKey = GlobalKey<StatisticsPageState>();
  final GlobalKey<RoutinesPageState> routinesKey = GlobalKey<RoutinesPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pageController = PageController(initialPage: 0);
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAction' && call.arguments is String) {
        _handleWidgetAction(call.arguments as String);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AiService.warmUp(widget.db);
      _checkInitialWidgetAction();
    });
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide').catchError((_) {});
      globalRefresh();
    }
  }

  Future<void> _checkInitialWidgetAction() async {
    try {
      final act = await _widgetChannel.invokeMethod<String>('getInitialAction');
      if (act != null && act.isNotEmpty) {
        _handleWidgetAction(act);
      }
    } catch (_) {}
  }

  void _handleWidgetAction(String act) {
    if (!mounted) return;
    switch (act) {
      case 'add_task':
        pageController.jumpToPage(0);
        Future.delayed(const Duration(milliseconds: 120), () {
          todayKey.currentState?.addTask();
        });
        break;
      case 'voice_orb':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveVoiceScreen(db: widget.db, onChanged: globalRefresh),
          ),
        );
        break;
      case 'offline_ai':
        _openDeepSeek(initialTab: 0);
        break;
      case 'api_ai':
        _openDeepSeek(initialTab: 1);
        break;
      case 'deepseek_web':
        _openDeepSeek(initialTab: 2);
        break;
      case 'focus_timer':
        showDialog(
          context: context,
          builder: (_) => const FocusTimerDialog(
            taskTitle: 'Quick Focus',
            initialStartMinutes: 360,
          ),
        );
        break;
      case 'calendar':
        pageController.jumpToPage(1);
        break;
      case 'stats':
        pageController.jumpToPage(2);
        break;
      default:
        pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeConfetti();
    pageController.dispose();
    super.dispose();
  }

  void _removeConfetti() {
    _confettiEntry?.remove();
    _confettiEntry = null;
  }

  void triggerCompletionCelebration(Offset position) {
    _removeConfetti();
    _confettiEntry = OverlayEntry(
      builder: (context) => ConfettiOverlayWidget(
        origin: position,
        onFinished: _removeConfetti,
      ),
    );
    Overlay.of(context).insert(_confettiEntry!);
  }

  void globalRefresh() {
    todayKey.currentState?.load();
    calendarKey.currentState?.load();
    statsKey.currentState?.load();
    routinesKey.currentState?.load();
    setState(() {});
  }

  void handleDateSelect(DateTime date) {
    setState(() {
      selectedDate = date;
    });
    statsKey.currentState?.setDate(date);
  }

  void resetToToday() {
    setState(() {
      selectedDate = DateTime.now();
    });
    todayKey.currentState?.load();
    statsKey.currentState?.setDate(DateTime.now());
    pageController.animateToPage(0, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  void _openDeepSeek({int initialTab = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeepSeekWebScreen(
          db: widget.db,
          onDatabaseChanged: globalRefresh,
          initialTab: initialTab,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          db: widget.db,
          appTitle: widget.appTitle,
          onThemeChanged: widget.onThemeChanged,
          onAppSettingsChanged: widget.onAppSettingsChanged,
          onChanged: globalRefresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        key: todayKey,
        db: widget.db,
        appTitle: widget.appTitle,
        date: selectedDate,
        onChanged: globalRefresh,
        onCelebrate: triggerCompletionCelebration,
        onResetToToday: resetToToday,
        onOpenSettings: _openSettings,
      ),
      CalendarPage(
        key: calendarKey,
        db: widget.db,
        selectedDate: selectedDate,
        onDateSelected: handleDateSelect,
        onOpenSettings: _openSettings,
      ),
      StatisticsPage(
        key: statsKey,
        db: widget.db,
        targetDate: selectedDate,
        onDatePicked: (date) {
          handleDateSelect(date);
          pageController.jumpToPage(0);
        },
        onOpenSettings: _openSettings,
      ),
      RoutinesPage(
        key: routinesKey,
        db: widget.db,
        onChanged: globalRefresh,
        onOpenSettings: _openSettings,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          PageView(
            controller: pageController,
            onPageChanged: (idx) => setState(() => currentIndex = idx),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: pages,
          ),
        ],
      ),
      bottomNavigationBar: _LiquidFloatingDock(
        pageController: pageController,
        selectedIndex: currentIndex,
        onChanged: (i) => pageController.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
        onOpenAI: _openDeepSeek,
      ),
    );
  }
}

class _LiquidFloatingDock extends StatelessWidget {
  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenAI;

  const _LiquidFloatingDock({
    required this.pageController,
    required this.selectedIndex,
    required this.onChanged,
    required this.onOpenAI,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Today'),
      (Icons.calendar_month_rounded, 'Calendar'),
      (Icons.insights_rounded, 'Stats'),
      (Icons.all_inclusive_rounded, 'Routines'),
    ];

    return SafeArea(
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        height: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(color: AppColors.violet.withOpacity(0.18), blurRadius: 24, spreadRadius: 0.5),
            const BoxShadow(color: Color(0x77000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xCC1E2538), Color(0xB3121724)],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.1),
              ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalSlots = items.length + 1;
            final tabWidth = constraints.maxWidth / totalSlots;

            return Stack(
              children: [
                AnimatedBuilder(
                  animation: pageController,
                  builder: (context, child) {
                    double page = selectedIndex.toDouble();
                    if (pageController.hasClients && pageController.position.hasContentDimensions) {
                      page = pageController.page ?? selectedIndex.toDouble();
                    }
                    return Positioned(
                      left: page * tabWidth + 4,
                      top: 5,
                      width: tabWidth - 8,
                      height: 56,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.violet.withOpacity(0.28), AppColors.cyan.withOpacity(0.15)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.violet.withOpacity(0.35)),
                        ),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    ...List.generate(items.length, (i) {
                      final selected = selectedIndex == i;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(items[i].$1, size: 20, color: selected ? Colors.white : AppColors.textMuted),
                              const SizedBox(height: 2),
                              Text(
                                items[i].$2,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onOpenAI,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 21, color: AppColors.cyan),
                            SizedBox(height: 2),
                            Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
          ),
        ),
      ),
    );
  }
}
