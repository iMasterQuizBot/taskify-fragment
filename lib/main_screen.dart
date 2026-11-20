import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_database.dart';
import 'app_theme.dart';
import 'calendar_page.dart';
import 'routines_page.dart';
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
    _requestAllRequiredPermissions();
  }

  Future<void> _requestAllRequiredPermissions() async {
    await [
      Permission.notification,
      Permission.storage,
      Permission.audio,
      Permission.manageExternalStorage,
    ].request();
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
      ),
      CalendarPage(
        key: calendarKey,
        db: widget.db,
        selectedDate: selectedDate,
        onDateSelected: handleDateSelect,
      ),
      StatisticsPage(
        key: statsKey,
        db: widget.db,
        targetDate: selectedDate,
        onDatePicked: (date) {
          handleDateSelect(date);
          pageController.jumpToPage(0);
        },
      ),
      RoutinesPage(
        key: routinesKey,
        db: widget.db,
        onChanged: globalRefresh,
      ),
      SettingsPage(
        db: widget.db,
        appTitle: widget.appTitle,
        onThemeChanged: widget.onThemeChanged,
        onAppSettingsChanged: widget.onAppSettingsChanged,
        onChanged: globalRefresh,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
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
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -180,
              right: -160,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.violet.withOpacity(0.14), Colors.transparent]),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: -220,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.cyan.withOpacity(0.08), Colors.transparent]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidFloatingDock extends StatelessWidget {
  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _LiquidFloatingDock({
    required this.pageController,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Today'),
      (Icons.calendar_month_rounded, 'Calendar'),
      (Icons.insights_rounded, 'Stats'),
      (Icons.all_inclusive_rounded, 'Routines'),
      (Icons.settings_rounded, 'Settings'),
    ];

    return SafeArea(
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
            final tabWidth = constraints.maxWidth / items.length;

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
                  children: List.generate(items.length, (i) {
                    final selected = selectedIndex == i;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(items[i].$1, size: 21, color: selected ? Colors.white : AppColors.textMuted),
                            const SizedBox(height: 2),
                            Text(
                              items[i].$2,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected ? Colors.white : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
