import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'calendar_page.dart';
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

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;
  late PageController pageController;
  DateTime selectedDate = DateTime.now();

  OverlayEntry? _confettiEntry;

  final GlobalKey<TodayPageState> todayKey = GlobalKey<TodayPageState>();
  final GlobalKey<CalendarPageState> calendarKey = GlobalKey<CalendarPageState>();
  final GlobalKey<StatisticsPageState> statsKey = GlobalKey<StatisticsPageState>();
  final GlobalKey<RoutinesPageState> routinesKey = GlobalKey<RoutinesPageState>();

  @override
  void initState() {
    super.initState();
    pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNotificationOnce());
  }

  Future<void> _askNotificationOnce() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  void dispose() {
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

  void _openDeepSeek() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeepSeekWebScreen(
          db: widget.db,
          onDatabaseChanged: globalRefresh,
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
          color: const Color(0xEB151A24),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
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
    );
  }
}
