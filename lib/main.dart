import 'dart:core';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/services.dart' hide Size;
import 'backend.dart';
import 'dataModels.dart';
import 'package:firebase_core/firebase_core.dart';
import 'offline_storage.dart';
import 'sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await OfflineStorageService.init();
  runApp(const SmokeQuit());
}

class SmokeQuit extends StatefulWidget {
  const SmokeQuit({super.key});

  @override
  State<SmokeQuit> createState() => _SmokeQuitState();
}

class _SmokeQuitState extends State<SmokeQuit> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final themeModeStr = await OfflineStorageService.getThemeMode();
    setState(() {
      switch (themeModeStr) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
  }

  Future<void> changeThemeMode(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    String modeStr = 'system';
    switch (mode) {
      case ThemeMode.light:
        modeStr = 'light';
        break;
      case ThemeMode.dark:
        modeStr = 'dark';
        break;
      default:
        modeStr = 'system';
    }
    await OfflineStorageService.saveThemeMode(modeStr);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: _themeMode,
      home: MainScreen(
        onThemeChanged: changeThemeMode,
        currentThemeMode: _themeMode,
      ),
      title: "SmokeQuit",
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const MainScreen({super.key, this.onThemeChanged, this.currentThemeMode});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  User? _currentUser;
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isOnline = true;

  final List<Widget> _screens = [];
  final GlobalKey<_DiaryPageState> _diaryPageKey = GlobalKey<_DiaryPageState>();
  final GlobalKey<_StatisticsPageState> _statisticsPageKey = GlobalKey<_StatisticsPageState>();

  @override
  void initState() {
    super.initState();
    _initializeScreens();
    _checkConnectivity();
    _listenToConnectivity();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tryAutoLogin();
      }
    });
  }

  Future<void> _tryAutoLogin() async {
    try {
      // Проверяем, есть ли активная сессия Firebase Auth
      final firebase_auth.FirebaseAuth auth = firebase_auth.FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      
      if (currentUser != null) {
        // Есть активная сессия Firebase Auth - загружаем пользователя
        try {
          final database = FirebaseDatabase.instance.refFromURL(
            'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
          );
          
          // Пытаемся загрузить из Firebase
          final isOnline = await OfflineStorageService.isOnline();
          User? user;
          
          if (isOnline) {
            try {
              final snapshot = await database
                  .child('users')
                  .child(currentUser.uid)
                  .get()
                  .timeout(const Duration(seconds: 5));
              
              if (snapshot.exists) {
                final data = snapshot.value as Map<dynamic, dynamic>;
                user = User.fromMap(currentUser.uid, data);
              }
            } catch (e) {
              print('Error loading user from Firebase: $e');
            }
          }
          
          // Если не удалось загрузить из Firebase, загружаем из локального хранилища
          if (user == null) {
            user = await OfflineStorageService.getUserLocally(currentUser.uid);
            if (user == null) {
              // Создаем пользователя из данных Firebase Auth
              user = User(currentUser.uid, currentUser.email ?? '', '', false, false);
            }
          }
          
          // Загружаем статистику из локального хранилища
          if (user.stats == null) {
            final localStats = await OfflineStorageService.getUserStatsLocally(user.userId, user);
            if (localStats != null) {
              user.stats = localStats;
            }
          }
          
          // Загружаем статистику из Firebase, если есть интернет
          if (isOnline && user.isOnboarded) {
            try {
              final onboardingService = await OnBoardingService.createOnboardingService(user);
              await onboardingService.onboardingAuth().timeout(const Duration(seconds: 5));
              await onboardingService.loadQuitStats().timeout(const Duration(seconds: 5));
            } catch (e) {
              print('Error loading stats from Firebase: $e');
              // Продолжаем с локальными данными
            }
          }
          
          // Проверяем, является ли пользователь администратором
          final isAdmin = await AdminService.isUserAdmin(user.mail);
          
          setState(() {
            _currentUser = user;
            _isAdmin = isAdmin;
            _isLoading = false;
          });
          _updateScreens();
          
          // Сохраняем сессию
          await OfflineStorageService.saveSession(user.userId, user.mail);
          
          // Синхронизируем данные в фоне
          SyncService.syncAllData(user).catchError((e) {
            print('Error syncing data: $e');
          });
          
          return; // Успешно вошли автоматически
        } catch (e) {
          print('Error during auto login: $e');
        }
      }
      
      // Если автоматический вход не удался, показываем диалог
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showAuthDialog();
      }
    } catch (e) {
      print('Error in _tryAutoLogin: $e');
      if (mounted) {
        _showAuthDialog();
      }
    }
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await OfflineStorageService.isOnline();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  void _listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      final isOnline = result.contains(ConnectivityResult.mobile) ||
                      result.contains(ConnectivityResult.wifi) ||
                      result.contains(ConnectivityResult.ethernet);
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        if (isOnline && _currentUser != null) {
          // Синхронизируем при появлении интернета
          SyncService.syncAllData(_currentUser).catchError((e) {
            print('Error syncing after connection restored: $e');
          });
        }
      }
    });
  }

  void _initializeScreens() {
    _screens.addAll([
      HomePage(
        key: const Key('home_page'),
        user: _currentUser,
        onUserUpdated: (user) {
          setState(() {
            _currentUser = user;
          });
          _updateScreens();
        },
        onCravingAdded: () {
          // Принудительно обновляем дневник и статистику
          _diaryPageKey.currentState?.refreshData();
          _statisticsPageKey.currentState?.refreshData();
        },
      ),
      ArticlesPage(
        key: const Key('articles_page'),
        user: _currentUser,
      ),
      StatisticsPage(
        key: _statisticsPageKey,
        user: _currentUser,
      ),
      DiaryPage(
        key: _diaryPageKey,
        user: _currentUser,
      ),
    ]);
  }

  void _updateScreens() {
    setState(() {
      _screens.clear();
      _screens.addAll([
        HomePage(
          key: const Key('home_page'),
          user: _currentUser,
          onUserUpdated: (user) {
            setState(() {
              _currentUser = user;
            });
            _updateScreens();
          },
          onCravingAdded: () {
            // Принудительно обновляем дневник и статистику
            _diaryPageKey.currentState?.refreshData();
            _statisticsPageKey.currentState?.refreshData();
          },
        ),
        ArticlesPage(
          key: const Key('articles_page'),
          user: _currentUser,
        ),
        StatisticsPage(
          key: _statisticsPageKey,
          user: _currentUser,
        ),
        DiaryPage(
          key: _diaryPageKey,
          user: _currentUser,
        ),
      ]);
    });
  }

  void _navigateToAdminPanel() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdminPanel(user: _currentUser!),
      ),
    );
  }

  void _showAuthDialog() {
    AuthReg.show(
      context,
      onUserAuthenticated: (user) async {
        // Проверяем, является ли пользователь администратором
        final isAdmin = await AdminService.isUserAdmin(user.mail);
        
        // Загружаем данные из локального хранилища
        final localUser = await OfflineStorageService.getUserLocally(user.userId);
        if (localUser != null) {
          user = localUser;
        }
        
        // Загружаем статистику из локального хранилища
        if (user.stats == null) {
          final localStats = await OfflineStorageService.getUserStatsLocally(user.userId, user);
          if (localStats != null) {
            user.stats = localStats;
          }
        }
        
        setState(() {
          _currentUser = user;
          _isAdmin = isAdmin;
          _isLoading = false;
        });
        _updateScreens();

        // Синхронизируем данные в фоне
        SyncService.syncAllData(user).catchError((e) {
          print('Error syncing data: $e');
        });

        // Слушаем изменения подключения
        Connectivity().onConnectivityChanged.listen((result) {
          if (result.contains(ConnectivityResult.mobile) ||
              result.contains(ConnectivityResult.wifi) ||
              result.contains(ConnectivityResult.ethernet)) {
            // Интернет появился - синхронизируем
            SyncService.syncAllData(user).catchError((e) {
              print('Error syncing after connection restored: $e');
            });
          }
        });

        if (!user.getOnboarded) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => OnBoardingWindow(user: user),
            ),
          ).then((_) {
            // После онбординга обновляем данные
            setState(() {
              _currentUser = user;
            });
            _updateScreens();
          });
        }
      },
    );
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _navigateToProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfilePage(
          user: _currentUser,
          isAdmin: _isAdmin,
          onAdminAccess: () {
            _navigateToAdminPanel();
          },
          onLogout: () {
            _handleLogout();
          },
          onAccountDeleted: () {
            _handleLogout();
          },
          onUserUpdated: (user) {
            setState(() {
              _currentUser = user;
            });
            _updateScreens();
          },
          onThemeChanged: widget.onThemeChanged,
          currentThemeMode: widget.currentThemeMode,
        ),
      ),
    );
  }

  void _handleLogout() {
    setState(() {
      _currentUser = null;
      _isAdmin = false;
      _isLoading = false;
      _currentIndex = 0;
    });
    _updateScreens();
    _showAuthDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 56,
        actions: [
          // Индикатор офлайн-режима
          if (!_isOnline)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.shade900.withOpacity(0.3)
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.shade700
                      : Colors.orange.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 16,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade300
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Офлайн',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade300
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: Icon(
              _currentUser != null ? Icons.person : Icons.person_outline,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: _currentUser != null ? _navigateToProfile : null,
            tooltip: 'Профиль',
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: _onTabSelected,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Theme.of(context).bottomAppBarTheme.color,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Colors.grey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Главная',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.article_outlined),
          activeIcon: Icon(Icons.article),
          label: 'Статьи',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.trending_up_outlined),
          activeIcon: Icon(Icons.trending_up),
          label: 'Статистика',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.book_outlined),
          activeIcon: Icon(Icons.book),
          label: 'Дневник',
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  final User? user;
  final Function(User)? onUserUpdated;
  final VoidCallback? onCravingAdded;

  const HomePage({super.key, this.user, this.onUserUpdated, this.onCravingAdded});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? _currentUser;
  QuitUser? _quitUser;
  List<QuitUser> _allQuits = [];
  bool _isLoading = true;
  Timer? _updateTimer;
  StreamSubscription? _cravingSubscription;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startAutoUpdate();
  }

  void _initializeData() {
    _currentUser = widget.user;
    _quitUser = _currentUser?.quitStat;
    _isLoading = _currentUser == null;
    
    if (_currentUser != null) {
      _loadQuitData();
      // Обновляем подписку при изменении пользователя
      _cravingSubscription?.cancel();
      _listenForCravingUpdates();
    } else {
      _isLoading = false;
      _cravingSubscription?.cancel();
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      _cravingSubscription?.cancel();
      _initializeData();
      _listenForCravingUpdates();
    }
  }

  // Автообновление статистики каждую минуту
  void _startAutoUpdate() {
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_quitUser != null && mounted) {
        setState(() {});
      }
    });
  }

  // Подписка на обновления тяги в реальном времени
  void _listenForCravingUpdates() {
    if (_currentUser == null) return;
    
    // Отменяем предыдущую подписку, если она существует
    _cravingSubscription?.cancel();
    
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    
    // Слушаем обновления желаний пользователя
    _cravingSubscription = database
        .child('allUserCravings')
        .child(_currentUser!.userId)
        .onValue
        .listen(
          (event) {
            if (mounted && _currentUser != null) {
              _loadQuitData();
            }
          },
          onError: (error) {
            print('Error in home page subscription: $error');
          },
        );
  }

  Future<void> _loadQuitData() async {
    if (_currentUser == null) return;

    try {
      final allQuits = await StartQuit.getAllUserQuits(_currentUser!);
      // Находим активную попытку (isQuiting == true и status == 'active')
      // Ищем в обратном порядке, чтобы найти последнюю активную попытку
      QuitUser? activeQuit;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuit = quit;
          break;
        }
      }
      // Если не нашли активную, activeQuit остается null
      // Это правильно, так как завершенные попытки не должны отображаться как активные
      
      if (mounted) {
        setState(() {
          _allQuits = allQuits;
          _quitUser = activeQuit;
          _currentUser?.quitStat = activeQuit;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading quit data: $e');
      // Если ошибка, проверяем локальное состояние пользователя
      if (mounted) {
        setState(() {
          // Если quitStat существует, но isQuiting == false, то нет активной попытки
          if (_currentUser?.quitStat != null && !_currentUser!.quitStat!.isQuiting) {
            _quitUser = null;
          } else {
            _quitUser = _currentUser?.quitStat;
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startQuitSmoking() async {
    if (_currentUser == null) {
      _showError('Пользователь не авторизован');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final startQuit = await StartQuit.startQuit(_currentUser!);
      setState(() {
        _quitUser = startQuit.userQuit;
        _currentUser?.quitStat = _quitUser;
        _allQuits.add(_quitUser!);
      });
      
      // Обновляем пользователя в родительском виджете
      if (widget.onUserUpdated != null) {
        widget.onUserUpdated!(_currentUser!);
      }
      
      _showSuccess('Вы начали новую попытку отказа от курения! 💪');
      
    } catch (e) {
      _showError('Ошибка при начале отказа от курения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Расчет сэкономленных денег
  double get _moneySaved {
    if (_quitUser == null || _currentUser?.stats == null) return 0.0;
    return _quitUser!.calculateMoneySaved(_currentUser!.stats);
  }

  // Получение дней без курения
  int get _daysWithoutSmoking {
    return _quitUser?.daysWithoutSmoking ?? 0;
  }

  // Получение улучшений здоровья
  Map<String, String> get _healthImprovements {
    return _quitUser?.getHealthImprovements() ?? {};
  }

  Widget _buildProgressCircle() {
    final days = _daysWithoutSmoking;
    final color = Theme.of(context).colorScheme.primary;
    
    if (days == 0 && _quitUser == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smoke_free,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Начните свой путь',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'к свободе от курения',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            color.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                days.toString(),
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 8),
                child: Text(
                  _getDaysWord(days),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'без курения',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.95),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDaysWord(int days) {
    final lastDigit = days % 10;
    final lastTwoDigits = days % 100;
    
    if (lastTwoDigits >= 11 && lastTwoDigits <= 14) {
      return 'дней';
    }
    
    if (lastDigit == 1) {
      return 'день';
    } else if (lastDigit >= 2 && lastDigit <= 4) {
      return 'дня';
    } else {
      return 'дней';
    }
  }

  Widget _buildMoneySavedCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.savings,
                  color: Colors.green,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  "₽${_moneySaved.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Сэкономлено средств",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_currentUser?.stats != null) ...[
              const SizedBox(height: 8),
              Text(
                "₽${(_currentUser!.stats!.getMonthlySavings()).toStringAsFixed(2)} в месяц",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthImprovements() {
    final improvements = _healthImprovements;
    
    if (improvements.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  "Улучшение здоровья",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...improvements.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6, right: 12),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    if (_quitUser != null && _quitUser!.isQuiting) {
      return Column(
        children: [
          Card(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.green.shade900.withOpacity(0.3)
                : Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(
                    Icons.celebration,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.shade300
                        : Colors.green,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Активная попытка: ${_allQuits.length}',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade300
                          : Colors.green.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Вы в процессе отказа от курения!',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade200
                          : Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Начало: ${_quitUser!.quitStart.day}.${_quitUser!.quitStart.month}.${_quitUser!.quitStart.year}',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade300
                          : Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_daysWithoutSmoking} дней без курения',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade300
                          : Colors.green.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCravingHelp,
                  icon: const Icon(Icons.favorite),
                  label: const Text('Тяга'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.shade900.withOpacity(0.3)
                        : Colors.red.shade50,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.shade300
                        : Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showEndAttemptDialog(),
                  icon: const Icon(Icons.stop),
                  label: const Text('Стоп'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade900.withOpacity(0.3)
                        : Colors.orange.shade50,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade300
                        : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _startQuitSmoking,
          icon: const Icon(Icons.smoke_free),
          label: const Text('Начать отказ от курения'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  void _showEndAttemptDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить попытку'),
        content: const Text('Вы уверены, что хотите завершить текущую попытку отказа от курения?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _endCurrentAttempt();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }

  Future<void> _endCurrentAttempt() async {
    if (_currentUser == null || _quitUser == null) return;

    try {
      await StartQuit.endQuitAttempt(_currentUser!, _quitUser!, 'failed');
      setState(() {
        _quitUser?.isQuiting = false;
      });
      _showSuccess('Попытка завершена. Вы можете начать новую!');
    } catch (e) {
      _showError('Ошибка при завершении попытки: $e');
    }
  }

  void _showCravingHelp() {
    showDialog(
      context: context,
      builder: (context) => _CravingRecordDialog(
        user: _currentUser,
        onCravingRecorded: () async {
          // Сначала обновляем _currentUser из widget.user, если он был изменен
          // Это важно, так как попытка может быть завершена локально
          if (widget.user != null) {
            setState(() {
              _currentUser = widget.user;
              // Если попытка была завершена (isQuiting == false), обновляем _quitUser
              if (_currentUser?.quitStat != null) {
                if (!_currentUser!.quitStat!.isQuiting) {
                  _quitUser = null;
                } else {
                  _quitUser = _currentUser!.quitStat;
                }
              }
            });
          }
          
          // Перезагружаем данные после сохранения записи
          await _loadQuitData();
          
          // После загрузки данных проверяем, завершена ли попытка
          if (_currentUser?.quitStat != null && !_currentUser!.quitStat!.isQuiting) {
            setState(() {
              _quitUser = null;
            });
          }
          
          // Обновляем пользователя в родительском виджете
          if (widget.onUserUpdated != null && _currentUser != null) {
            widget.onUserUpdated!(_currentUser!);
          }
          
          // Принудительно обновляем дневник и статистику через callback
          widget.onCravingAdded?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: MediaQuery.of(context).padding.top + 56), // Отступ для AppBar
              _buildProgressCircle(),
              const SizedBox(height: 32),
              _buildMoneySavedCard(),
              const SizedBox(height: 16),
              _buildHealthImprovements(),
              const SizedBox(height: 24),
              _buildStartButton(),
              if (_currentUser == null) ...[
                const SizedBox(height: 16),
                Text(
                  'Войдите в аккаунт чтобы начать отсчет',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _cravingSubscription?.cancel();
    super.dispose();
  }
}

class ArticlesPage extends StatefulWidget {
  final User? user;

  const ArticlesPage({super.key, this.user});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  final ArticleService _articleService = ArticleService.create();
  List<Article> _articles = [];
  bool _isLoading = true;
  String _selectedCategory = 'Все';

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    try {
      final articles = await _articleService.getAllArticles();
      if (mounted) {
        setState(() {
          _articles = articles;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading articles: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Article> get _filteredArticles {
    if (_selectedCategory == 'Все') return _articles;
    return _articles.where((article) => article.category == _selectedCategory).toList();
  }

  List<String> get _categories {
    final categories = _articles.map((article) => article.category).toSet().toList();
    categories.insert(0, 'Все');
    return categories;
  }

  void _showArticleDetails(Article article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(article.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(article.category),
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade900.withOpacity(0.4)
                        : Colors.blue.shade100,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    article.formattedDate,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                article.content,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Автор: ${article.author}',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Фильтр по категориям
                  Container(
                    padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((category) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Список статей
                Expanded(
                  child: _filteredArticles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.article,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Статьи пока не добавлены',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredArticles.length,
                          itemBuilder: (context, index) {
                            final article = _filteredArticles[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Text(
                                  article.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    Text(article.previewContent),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(article.category),
                                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.blue.shade900.withOpacity(0.4)
                                              : Colors.blue.shade50,
                                          labelStyle: const TextStyle(fontSize: 12),
                                        ),
                                        const Spacer(),
                                        Text(
                                          article.formattedDate,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () => _showArticleDetails(article),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      ),
    );
  }
}

class DiaryPage extends StatefulWidget {
  final User? user;

  const DiaryPage({super.key, this.user});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final SmokingDiaryService _diaryService = SmokingDiaryService.create();
  SmokingDiary? _todayDiary;
  bool _isLoading = true;
  StreamSubscription? _cravingSubscription;

  @override
  void initState() {
    super.initState();
    _loadTodayDiary();
    _listenForCravingUpdates();
  }

  // Метод для принудительного обновления данных из Firebase
  void refreshData() {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
      _loadTodayDiary();
    }
  }

  void _listenForCravingUpdates() {
    if (widget.user == null) return;
    
    // Отменяем предыдущую подписку, если она существует
    _cravingSubscription?.cancel();
    
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    
    // Слушаем обновления желаний пользователя
    _cravingSubscription = database
        .child('allUserCravings')
        .child(widget.user!.userId)
        .onValue
        .listen(
          (event) {
            if (mounted) {
              // Небольшая задержка, чтобы убедиться, что данные синхронизировались
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _loadTodayDiary();
                }
              });
            }
          },
          onError: (error) {
            print('Error in diary subscription: $error');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        );
  }

  @override
  void didUpdateWidget(DiaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      // Обновляем подписку при изменении пользователя
      _listenForCravingUpdates();
      _loadTodayDiary();
    }
  }

  Future<void> _loadTodayDiary() async {
    if (widget.user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final today = DateTime.now();
      final todayFormatted = DateTime(today.year, today.month, today.day);

      final todaysCravings = <CravingRecord>[];
      
      // Сначала загружаем из локального хранилища
      final localCravings = await OfflineStorageService.getAllCravingsLocally();
      for (var craving in localCravings) {
        final cravingDate = DateTime(
          craving.timestamp.year,
          craving.timestamp.month,
          craving.timestamp.day,
        );
        if (cravingDate == todayFormatted) {
          todaysCravings.add(craving);
        }
      }

      // Затем пытаемся загрузить из Firebase (если есть интернет)
      final isOnline = await OfflineStorageService.isOnline();
      if (isOnline) {
        try {
          final database = FirebaseDatabase.instance.refFromURL(
            'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
          );

          final snapshot = await database
              .child('allUserCravings')
              .child(widget.user!.userId)
              .get();

          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            data.forEach((key, value) {
              try {
                final record = CravingRecord.fromJson(
                  Map<String, dynamic>.from(value as Map<dynamic, dynamic>)
                );
                final cravingDate = DateTime(
                  record.timestamp.year,
                  record.timestamp.month,
                  record.timestamp.day,
                );
                if (cravingDate == todayFormatted) {
                  // Добавляем только если еще нет в списке (избегаем дубликатов)
                  if (!todaysCravings.any((c) => c.id == record.id)) {
                    todaysCravings.add(record);
                  }
                }
                // Сохраняем в локальное хранилище
                OfflineStorageService.saveCravingLocally(record);
              } catch (e) {
                print('Error parsing craving: $e');
              }
            });
          }
        } catch (e) {
          print('Error loading cravings from Firebase: $e');
          // Продолжаем с локальными данными
        }
      }

      // Загружаем дневник за сегодня (с таймаутом для офлайн-режима)
      SmokingDiary? diary;
      try {
        diary = await _diaryService.getDailyDiary(widget.user!, today)
            .timeout(const Duration(seconds: 8), onTimeout: () {
          print('Timeout loading diary, using local storage');
          return null;
        });
      } catch (e) {
        print('Error loading diary (timeout or error): $e');
        // Пытаемся загрузить из локального хранилища напрямую
        try {
          diary = await OfflineStorageService.getDiaryLocally(widget.user!.userId, today);
        } catch (e2) {
          print('Error loading from local storage: $e2');
          diary = null;
        }
      }

      if (diary == null) {
        final newDiary = SmokingDiary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: widget.user!.userId,
          date: today,
        );

        for (var craving in todaysCravings) {
          newDiary.addCravingRecord(craving);
        }

        if (mounted) {
          setState(() {
            _todayDiary = newDiary;
            _isLoading = false;
          });
        }
      } else {
        // Очищаем старые записи и добавляем все заново, чтобы избежать дублирования
        diary.cravings.clear();
        for (var craving in todaysCravings) {
          diary.addCravingRecord(craving);
        }

        if (mounted) {
          setState(() {
            _todayDiary = diary;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading diary: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Показываем пользователю сообщение об ошибке только если это критично
        if (e.toString().contains('permission') || e.toString().contains('network')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки данных: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _updateDiary() async {
    if (widget.user == null) {
      _showError('Пожалуйста, авторизируйтесь');
      return;
    }

    if (_todayDiary == null) {
      _todayDiary = SmokingDiary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: widget.user!.userId,
        date: DateTime.now(),
      );
      try {
        await _diaryService.saveDiary(widget.user!, _todayDiary!);
      } catch (e) {
        print('Error initializing diary: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => _DiaryEditDialog(
        diary: _todayDiary!,
        onSave: (cigaretteCount, mood, motivationScore) async {
          try {
            _todayDiary!.cigarettesSmoked = cigaretteCount;
            _todayDiary!.mood = mood;
            _todayDiary!.motivationScore = motivationScore;

            await _diaryService.saveDiary(widget.user!, _todayDiary!);

            if (mounted) {
              setState(() {});
              _showSuccess('Дневник обновлен!');
            }
          } catch (e) {
            print('Error updating diary: $e');
            _showError('Ошибка при обновлении: $e');
          }
        },
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.user == null) {
      return Scaffold(
        body: const Center(
          child: Text('Войдите в аккаунт для доступа к дневнику'),
        ),
      );
    }

    if (_todayDiary == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_outlined, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Нет данных на сегодня',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Начните фиксировать желания курить',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _todayDiary!.getDayStats();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Статистика за сегодня',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Желаний', '${stats['totalCravings'] ?? 0}', Icons.favorite),
                          _buildStatItem('Преодолено', '${stats['overcome'] ?? 0}', Icons.check_circle),
                          _buildStatItem('Не справился', '${stats['failed'] ?? 0}', Icons.cancel),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Успех: ${stats['successRate'] ?? '0'}%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Мотивационная карточка
              _buildMotivationalCard(stats),
              const SizedBox(height: 24),
              Text(
                'История желаний (сегодня)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if ((_todayDiary!.cravings).isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('Нет записей о желаниях'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _todayDiary!.cravings.length,
                  itemBuilder: (context, index) {
                    final craving = _todayDiary!.cravings[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          craving.overcome ? Icons.check_circle : Icons.cancel,
                          color: craving.overcome ? Colors.green : Colors.red,
                        ),
                        title: Text(craving.trigger),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Мотивация: ${craving.motivationLevel}/10'),
                            if (craving.notes != null) ...[
                              const SizedBox(height: 4),
                              Text(craving.notes!),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMotivationalCard(Map<String, dynamic> stats) {
    final totalCravings = stats['totalCravings'] ?? 0;
    final overcome = stats['overcome'] ?? 0;
    final successRate = double.tryParse(stats['successRate']?.toString() ?? '0') ?? 0.0;
    
    String message;
    IconData icon;
    Color color;
    
    if (totalCravings == 0) {
      message = 'Отличное начало! Продолжайте в том же духе! 💪';
      icon = Icons.celebration;
      color = Colors.green.shade400;
    } else if (successRate >= 80) {
      message = 'Потрясающе! Вы справляетесь отлично! 🌟';
      icon = Icons.star;
      color = Colors.green.shade600;
    } else if (successRate >= 50) {
      message = 'Хорошая работа! Вы на правильном пути! 👍';
      icon = Icons.thumb_up;
      color = Colors.green.shade500;
    } else if (overcome > 0) {
      message = 'Каждая победа важна! Продолжайте бороться! 💪';
      icon = Icons.fitness_center;
      color = Colors.green.shade500;
    } else {
      message = 'Не сдавайтесь! Завтра будет лучше! 🌈';
      icon = Icons.favorite;
      color = Colors.green.shade400;
    }
    
    return Card(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade900.withOpacity(0.3)
          : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Мотивация',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cravingSubscription?.cancel();
    super.dispose();
  }
}

class ProfilePage extends StatefulWidget {
  final User? user;
  final bool isAdmin;
  final VoidCallback? onAdminAccess;
  final VoidCallback? onLogout;
  final VoidCallback? onAccountDeleted;
  final Function(User)? onUserUpdated;
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const ProfilePage({
    super.key,
    this.user,
    this.isAdmin = false,
    this.onAdminAccess,
    this.onLogout,
    this.onAccountDeleted,
    this.onUserUpdated,
    this.onThemeChanged,
    this.currentThemeMode,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isDeleting = false;
  bool _isLoggingOut = false;

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход из аккаунта'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      final firebase_auth.FirebaseAuth auth = firebase_auth.FirebaseAuth.instance;
      await auth.signOut();
      
      // Очищаем сессию
      await OfflineStorageService.clearSession();
      
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем страницу профиля
        if (widget.onLogout != null) {
          widget.onLogout!();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выходе: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление аккаунта'),
        content: const Text(
          'Вы уверены, что хотите удалить аккаунт? Это действие нельзя отменить. Все ваши данные будут удалены безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Дополнительное подтверждение
    final doubleConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Последнее предупреждение'),
        content: const Text(
          'Это действие необратимо. Все ваши данные, статистика и история будут удалены навсегда. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Да, удалить'),
          ),
        ],
      ),
    );

    if (doubleConfirm != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final firebase_auth.FirebaseAuth auth = firebase_auth.FirebaseAuth.instance;
      final user = auth.currentUser;

      if (user == null) {
        throw Exception('Пользователь не найден');
      }

      // Удаляем данные из базы данных
      if (widget.user != null) {
        try {
          final database = FirebaseDatabase.instance.refFromURL(
            'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
          );
          
          final userId = widget.user!.userId;
          
          // Удаляем все данные пользователя
          await database.child('users').child(userId).remove();
          await database.child('usersIndex').child(userId).remove();
          await database.child('allUserCravings').child(userId).remove();
          await database.child('userQuits').child(userId).remove();
          await database.child('userStats').child(userId).remove();
          await database.child('smokingDiaries').child(userId).remove();
          
          print('User data deleted from database');
        } catch (e) {
          print('Error deleting user data from database: $e');
          // Продолжаем удаление аккаунта даже если не удалось удалить данные из БД
        }
      }

      // Удаляем аккаунт из Firebase Auth
      await user.delete();

      if (mounted) {
        Navigator.of(context).pop(); // Закрываем страницу профиля
        if (widget.onAccountDeleted != null) {
          widget.onAccountDeleted!();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении аккаунта: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String subtitle, {Color? iconColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.primary, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    
    if (widget.user == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 80,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 24),
              Text(
                'Войдите в аккаунт',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Чтобы просмотреть свой профиль',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = widget.user!;
    final daysWithoutSmoking = user.quitStat?.daysWithoutSmoking ?? 0;
    final moneySaved = user.stats != null && user.quitStat != null
        ? user.quitStat!.calculateMoneySaved(user.stats!)
        : 0.0;
    final monthlySavings = user.stats?.getMonthlySavings() ?? 0.0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Заголовок с градиентом
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            backgroundColor: primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              centerTitle: false,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor,
                      primaryColor.withOpacity(0.7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 50, bottom: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Аватар
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.person,
                            size: 45,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Email
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            user.mail,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Контент
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Статистика
                  if (user.quitStat != null) ...[
                    Text(
                      'Статистика',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildStatCard(
                          'Дней без курения',
                          daysWithoutSmoking.toString(),
                          Icons.calendar_today,
                          Colors.green,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Сэкономлено',
                          '₽${moneySaved.toStringAsFixed(0)}',
                          Icons.savings,
                          Colors.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.purple.withOpacity(0.3), width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.trending_up, color: Colors.purple, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₽${monthlySavings.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                                Text(
                                  'Экономия в месяц',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Информация о пользователе
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Информация',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (user.isOnboarded)
                        TextButton.icon(
                          onPressed: () async {
                            final updatedUser = await Navigator.of(context).push<User>(
                              MaterialPageRoute(
                                builder: (context) => EditProfileWindow(
                                  user: user,
                                  onProfileUpdated: (updatedUser) {
                                    if (widget.onUserUpdated != null) {
                                      widget.onUserUpdated!(updatedUser);
                                    }
                                  },
                                ),
                              ),
                            );
                            if (updatedUser != null && widget.onUserUpdated != null) {
                              widget.onUserUpdated!(updatedUser);
                            }
                            if (mounted) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Редактировать'),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTile(
                    Icons.email,
                    'Email',
                    user.mail,
                    iconColor: Colors.blue,
                  ),
                  _buildInfoTile(
                    Icons.smoking_rooms,
                    'Тип курения',
                    user.isAlternative ? 'Электронные сигареты' : 'Обычные сигареты',
                    iconColor: Colors.orange,
                  ),
                  _buildInfoTile(
                    Icons.check_circle,
                    'Статус',
                    user.isOnboarded ? 'Профиль настроен' : 'Требуется настройка',
                    iconColor: user.isOnboarded ? Colors.green : Colors.orange,
                  ),
                  if (user.stats != null)
                    _buildInfoTile(
                      Icons.history,
                      'Опыт курения',
                      '${user.stats!.getTotalSmokingMonths()} месяцев',
                      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(height: 24),

                  // Админ панель
                  if (widget.isAdmin) ...[
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: Theme.of(context).brightness == Brightness.dark
                              ? [Colors.blue.shade900.withOpacity(0.4), Colors.blue.shade800.withOpacity(0.4)]
                              : [Colors.blue.shade50, Colors.blue.shade100],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade700
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.admin_panel_settings,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        title: const Text(
                          'Панель администратора',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: const Text('Управление статьями и контентом'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: widget.onAdminAccess,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Действия
                  Text(
                    'Действия',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Смена темы
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.purple.shade900.withOpacity(0.3)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.purple.shade700
                            : Colors.blue.shade200,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.purple
                              : Colors.blue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.currentThemeMode == ThemeMode.dark
                              ? Icons.dark_mode
                              : widget.currentThemeMode == ThemeMode.light
                                  ? Icons.light_mode
                                  : Icons.brightness_auto,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Тема приложения',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        widget.currentThemeMode == ThemeMode.dark
                            ? 'Темная'
                            : widget.currentThemeMode == ThemeMode.light
                                ? 'Светлая'
                                : 'Системная',
                      ),
                      trailing: DropdownButton<ThemeMode>(
                        value: widget.currentThemeMode ?? ThemeMode.system,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('Системная'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Светлая'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Темная'),
                          ),
                        ],
                        onChanged: widget.onThemeChanged != null
                            ? (ThemeMode? mode) {
                                if (mode != null && widget.onThemeChanged != null) {
                                  widget.onThemeChanged!(mode);
                                }
                              }
                            : null,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  
                  // Выход
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade900.withOpacity(0.3)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.orange.shade700
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isLoggingOut
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.logout,
                                color: Theme.of(context).colorScheme.onPrimary,
                                size: 20,
                              ),
                      ),
                      title: const Text(
                        'Выйти из аккаунта',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: const Text('Выйти из текущего аккаунта'),
                      trailing: _isLoggingOut ? null : const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _isLoggingOut ? null : _handleLogout,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  
                  // Удаление аккаунта
                  Container(
                    margin: const EdgeInsets.only(bottom: 32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.red.shade900.withOpacity(0.3)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red.shade700
                            : Colors.red.shade200,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isDeleting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.delete_forever,
                                color: Theme.of(context).colorScheme.onPrimary,
                                size: 20,
                              ),
                      ),
                      title: const Text(
                        'Удалить аккаунт',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.red,
                        ),
                      ),
                      subtitle: const Text(
                        'Удалить аккаунт и все данные',
                        style: TextStyle(color: Colors.red),
                      ),
                      trailing: _isDeleting ? null : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                      onTap: _isDeleting ? null : _handleDeleteAccount,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
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

class AdminPanel extends StatefulWidget {
  final User user;

  const AdminPanel({super.key, required this.user});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final ArticleService _articleService = ArticleService.create();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String _selectedCategory = articleCategories.first;
  bool _isLoading = false;
  List<Article> _articles = [];

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    try {
      final articles = await _articleService.getAllArticles();
      if (mounted) {
        setState(() {
          _articles = articles;
        });
      }
    } catch (e) {
      print('Error loading articles: $e');
    }
  }

  Future<void> _addArticle() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      _showError('Заполните все поля');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _articleService.addArticle(
        title: _titleController.text,
        content: _contentController.text,
        category: _selectedCategory,
        author: widget.user.mail,
      );

      _titleController.clear();
      _contentController.clear();
      _loadArticles();
      _showSuccess('Статья успешно добавлена!');
    } catch (e) {
      _showError('Ошибка при добавлении статьи: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteArticle(String articleId) async {
    try {
      setState(() => _isLoading = true);
      await _articleService.deleteArticle(articleId);
      _loadArticles();
      _showSuccess('Статья успешно удалена!');
    } catch (e) {
      _showError('Ошибка при удалении статьи: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Управление статьями', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(labelText: 'Контент', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              onChanged: (value) => setState(() => _selectedCategory = value!),
              items: articleCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
              decoration: const InputDecoration(labelText: 'Категория', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _isLoading ? null : _addArticle, child: const Text('Добавить статью')),
            const SizedBox(height: 24),
            Text('Список статей', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _articles.length,
                itemBuilder: (context, index) {
                  final article = _articles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(article.title),
                      subtitle: Text(article.category),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteArticle(article.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}

class _DiaryEditDialog extends StatefulWidget {
  final SmokingDiary diary;
  final Function(int cigaretteCount, String mood, double motivationScore) onSave;

  const _DiaryEditDialog({required this.diary, required this.onSave});

  @override
  State<_DiaryEditDialog> createState() => _DiaryEditDialogState();
}

class _DiaryEditDialogState extends State<_DiaryEditDialog> {
  late int _cigaretteCount;
  late String _mood;
  late double _motivationScore;

  @override
  void initState() {
    super.initState();
    _cigaretteCount = widget.diary.cigarettesSmoked;
    _mood = widget.diary.mood ?? 'Нормальное';
    _motivationScore = widget.diary.motivationScore ?? 5.0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Обновить дневник'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: _cigaretteCount.toString()),
              onChanged: (value) => _cigaretteCount = int.tryParse(value) ?? 0,
              decoration: const InputDecoration(labelText: 'Выкурено сигарет', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _mood,
              onChanged: (value) => setState(() => _mood = value!),
              items: ['Хорошее', 'Нормальное', 'Плохое'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              decoration: const InputDecoration(labelText: 'Настроение', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Мотивация: ${_motivationScore.toStringAsFixed(1)}/10'),
            Slider(
              value: _motivationScore,
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (value) => setState(() => _motivationScore = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_cigaretteCount, _mood, _motivationScore);
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// Диалог для записи тяги
class _CravingRecordDialog extends StatefulWidget {
  final User? user;
  final VoidCallback? onCravingRecorded;

  const _CravingRecordDialog({this.user, this.onCravingRecorded});

  @override
  State<_CravingRecordDialog> createState() => _CravingRecordDialogState();
}

class _CravingRecordDialogState extends State<_CravingRecordDialog> {
  late String _selectedTrigger;
  int _motivationLevel = 5;
  final _notesController = TextEditingController();
  late List<String> _availableReasons;

  @override
  void initState() {
    super.initState();
    _availableReasons = getCravingsReasons(widget.user);
    _selectedTrigger = _availableReasons.first;
  }

  @override
  void didUpdateWidget(_CravingRecordDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      _availableReasons = getCravingsReasons(widget.user);
      if (!_availableReasons.contains(_selectedTrigger)) {
        _selectedTrigger = _availableReasons.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Запись о тяге',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Что спровоцировало тягу?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedTrigger,
                isExpanded: true,
                menuMaxHeight: 300,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedTrigger = value;
                    });
                  }
                },
                items: _availableReasons.map((reason) {
                  return DropdownMenuItem<String>(
                    value: reason,
                    child: Text(
                      reason,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  );
                }).toList(),
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                ),
                selectedItemBuilder: (BuildContext context) {
                  return _availableReasons.map((reason) {
                    return Text(
                      reason,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    );
                  }).toList();
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Уровень мотивации',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _motivationLevel.toDouble(),
                onChanged: (value) {
                  setState(() {
                    _motivationLevel = value.toInt();
                  });
                },
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_motivationLevel',
                activeColor: Colors.green,
                inactiveColor: Theme.of(context).colorScheme.surfaceVariant,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Заметки (необязательно)',
                  border: OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _recordAndShowHelp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Записать и получить совет',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordAndShowHelp() async {
    if (widget.user == null) {
      _showError('Ошибка: пользователь не авторизован');
      return;
    }

    // Создаем запись о тяге, но НЕ сохраняем в Firebase пока
    final record = CravingRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      trigger: _selectedTrigger,
      motivationLevel: _motivationLevel,
      overcome: false, // По умолчанию false, изменится после выбора пользователя
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    // Закрываем диалог ввода
    Navigator.pop(context);

    // Показываем диалог с советами (данные еще не сохранены)
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // Нельзя закрыть без выбора
        builder: (context) => _CravingHelpDialog(
          user: widget.user,
          cravingRecord: record,
          onCravingRecorded: widget.onCravingRecorded,
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }
}

// Диалог с советами при тяге
class _CravingHelpDialog extends StatefulWidget {
  final User? user;
  final CravingRecord cravingRecord;
  final VoidCallback? onCravingRecorded;

  const _CravingHelpDialog({this.user, required this.cravingRecord, this.onCravingRecorded});

  @override
  State<_CravingHelpDialog> createState() => _CravingHelpDialogState();
}

class _CravingHelpDialogState extends State<_CravingHelpDialog> {
  bool _isSaving = false;
  
  final List<Map<String, String>> _copingStrategies = [
    {
      'title': '💧 Пить воду',
      'description': 'Выпейте стакан холодной воды.',
    },
    {
      'title': '🚶 Прогулка',
      'description': 'Пройдитесь на свежем воздухе.',
    },
    {
      'title': '🧘 Дыхательное упражнение',
      'description': 'Глубокий вдох на 4 счета, задержка на 7, выдох на 8.',
    },
    {
      'title': '🍎 Перекус',
      'description': 'Съешьте фрукт или жевательную резинку.',
    },
    {
      'title': '📞 Позвоните другу',
      'description': 'Общение отвлекает и поддерживает мотивацию.',
    },
    {
      'title': '🎵 Музыка',
      'description': 'Слушайте вашу любимую музыку.',
    },
    {
      'title': '✍️ Дневник',
      'description': 'Запишите свои чувства и мысли.',
    },
    {
      'title': '💪 Упражнения',
      'description': 'Отжимания, приседания или прыжки.',
    },
    {
      'title': '🧊 Холодный душ',
      'description': 'Примите холодный душ или умойте лицо.',
    },
    {
      'title': '🧩 Головоломка',
      'description': 'Решайте кроссворды или судоку.',
    },
    {
      'title': '🛀 Ванна',
      'description': 'Расслабьтесь в теплой ванне.',
    },
    {
      'title': '🧈 Леденцы',
      'description': 'Жвачка без сахара или мятные леденцы.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: 600,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Colors.red, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Способы борьбы с тягой',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _copingStrategies.length,
                itemBuilder: (context, index) {
                  final strategy = _copingStrategies[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(strategy['title']!),
                      subtitle: Text(strategy['description']!),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveCravingAsOvercome,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Справился! ✓',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _updateCravingAsFailed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Не справился ✗',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Сохранить тягу как преодоленную
  Future<void> _saveCravingAsOvercome() async {
    if (widget.user == null) {
      _showError('Ошибка: пользователь не авторизован');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Создаем запись с overcome: true
      final record = CravingRecord(
        id: widget.cravingRecord.id,
        timestamp: widget.cravingRecord.timestamp,
        trigger: widget.cravingRecord.trigger,
        motivationLevel: widget.cravingRecord.motivationLevel,
        overcome: true, // Справился!
        notes: widget.cravingRecord.notes,
      );

      final diaryService = SmokingDiaryService.create();
      
      // Сохраняем желание глобально (для всех попыток)
      await diaryService.addCravingRecordGlobal(widget.user!, record);

      // Проверяем подключение к интернету
      final isOnline = await OfflineStorageService.isOnline();

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        
        // Небольшая задержка только если онлайн
        if (isOnline) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Вызываем callback для обновления UI
        widget.onCravingRecorded?.call();
      }
    } catch (e) {
      _showError('Ошибка при сохранении: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Сохранить тягу как не преодоленную
  Future<void> _updateCravingAsFailed() async {
    if (widget.user == null) {
      _showError('Ошибка: пользователь не авторизован');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Создаем запись с overcome: false
      final record = CravingRecord(
        id: widget.cravingRecord.id,
        timestamp: widget.cravingRecord.timestamp,
        trigger: widget.cravingRecord.trigger,
        motivationLevel: widget.cravingRecord.motivationLevel,
        overcome: false, // Не справился
        notes: widget.cravingRecord.notes,
      );

      final diaryService = SmokingDiaryService.create();
      
      // Сохраняем желание глобально (для всех попыток)
      await diaryService.addCravingRecordGlobal(widget.user!, record);

      // Проверяем подключение к интернету
      final isOnline = await OfflineStorageService.isOnline();

      // Если есть активная попытка, завершаем её как неудачную
      if (widget.user!.quitStat != null) {
        if (isOnline) {
          try {
            await StartQuit.endQuitAttempt(
              widget.user!, 
              widget.user!.quitStat!, 
              'failed', 
              failedDueToCraving: true
            );
            // Обновляем локально после успешного завершения в Firebase
            _updateQuitAttemptLocally();
          } catch (e) {
            print('Error ending quit attempt online, updating locally: $e');
            // Обновляем локально, если не удалось в Firebase
            _updateQuitAttemptLocally();
            // Добавляем в очередь синхронизации
            await OfflineStorageService.addToSyncQueue('endQuitAttempt', {
              'quitId': widget.user!.quitStat!.quitId,
              'status': 'failed',
              'failedDueToCraving': true,
            });
          }
        } else {
          // Офлайн режим - обновляем локально и добавляем в очередь
          _updateQuitAttemptLocally();
          await OfflineStorageService.addToSyncQueue('endQuitAttempt', {
            'quitId': widget.user!.quitStat!.quitId,
            'status': 'failed',
            'failedDueToCraving': true,
          });
        }
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        
        // Небольшая задержка только если онлайн
        if (isOnline) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // Вызываем callback для обновления UI
        widget.onCravingRecorded?.call();
      }
    } catch (e) {
      _showError('Ошибка при сохранении: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _updateQuitAttemptLocally() {
    if (widget.user?.quitStat != null) {
      widget.user!.quitStat!.quitEnd = DateTime.now();
      widget.user!.quitStat!.status = 'failed';
      widget.user!.quitStat!.isQuiting = false;
      widget.user!.quitStat!.failedDueToCraving = true;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class StatisticsPage extends StatefulWidget {
  final User? user;

  const StatisticsPage({super.key, this.user});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final SmokingDiaryService _diaryService = SmokingDiaryService.create();
  List<CravingRecord> _cravings = [];
  Map<String, int> _triggerStats = {};
  Map<String, int> _timeOfDayStats = {}; // Статистика по времени суток
  Map<String, int> _dayOfWeekStats = {}; // Статистика по дням недели
  double _averageMotivation = 0.0; // Средний уровень мотивации
  int _longestStreak = 0; // Самая длинная серия успешных дней
  bool _isLoading = true;
  StreamSubscription? _statisticsSubscription;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
    _listenForStatisticsUpdates();
  }

  // Метод для принудительного обновления данных из Firebase
  void refreshData() {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
      _loadStatistics();
    }
  }

  void _listenForStatisticsUpdates() {
    if (widget.user == null) return;

    // Отменяем предыдущую подписку, если она существует
    _statisticsSubscription?.cancel();

    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );

    // Слушаем обновления всех желаний пользователя
    _statisticsSubscription = database
        .child('allUserCravings')
        .child(widget.user!.userId)
        .onValue
        .listen(
          (event) {
            if (mounted) {
              _loadStatistics();
            }
          },
          onError: (error) {
            print('Error in statistics subscription: $error');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        );
  }

  @override
  void didUpdateWidget(StatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      // Обновляем подписку при изменении пользователя
      _listenForStatisticsUpdates();
      _loadStatistics();
    }
  }

  Future<void> _loadStatistics() async {
    if (widget.user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Сначала загружаем из локального хранилища
      final allCravings = await OfflineStorageService.getAllCravingsLocally();
      
      // Затем пытаемся загрузить из Firebase (если есть интернет)
      final isOnline = await OfflineStorageService.isOnline();
      if (isOnline) {
        try {
          final database = FirebaseDatabase.instance.refFromURL(
            'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
          );

          final snapshot = await database
              .child('allUserCravings')
              .child(widget.user!.userId)
              .get();
          
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            data.forEach((key, value) {
              try {
                final record = CravingRecord.fromJson(
                  Map<String, dynamic>.from(value as Map<dynamic, dynamic>)
                );
                // Добавляем только если еще нет в списке
                if (!allCravings.any((c) => c.id == record.id)) {
                  allCravings.add(record);
                }
                // Сохраняем в локальное хранилище
                OfflineStorageService.saveCravingLocally(record);
              } catch (e) {
                print('Error parsing craving: $e');
              }
            });
          }
        } catch (e) {
          print('Error loading statistics from Firebase: $e');
          // Продолжаем с локальными данными
        }
      }

      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      // Фильтруем записи за последние 30 дней (включая сегодня)
      final cravings = allCravings
          .where((c) => c.timestamp.isAfter(thirtyDaysAgo.subtract(const Duration(seconds: 1))) && 
                       c.timestamp.isBefore(now.add(const Duration(seconds: 1))))
          .toList();

      final triggerStats = <String, int>{};
      final timeOfDayStats = <String, int>{};
      final dayOfWeekStats = <String, int>{};
      int totalMotivation = 0;
      
      for (var craving in cravings) {
        // Статистика по триггерам
        triggerStats[craving.trigger] = (triggerStats[craving.trigger] ?? 0) + 1;
        
        // Статистика по времени суток
        final hour = craving.timestamp.hour;
        String timeOfDay;
        if (hour >= 6 && hour < 12) {
          timeOfDay = 'Утро (6-12)';
        } else if (hour >= 12 && hour < 18) {
          timeOfDay = 'День (12-18)';
        } else if (hour >= 18 && hour < 22) {
          timeOfDay = 'Вечер (18-22)';
        } else {
          timeOfDay = 'Ночь (22-6)';
        }
        timeOfDayStats[timeOfDay] = (timeOfDayStats[timeOfDay] ?? 0) + 1;
        
        // Статистика по дням недели
        final dayNames = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
        final dayOfWeek = dayNames[craving.timestamp.weekday - 1];
        dayOfWeekStats[dayOfWeek] = (dayOfWeekStats[dayOfWeek] ?? 0) + 1;
        
        // Суммируем мотивацию
        totalMotivation += craving.motivationLevel;
      }
      
      // Вычисляем среднюю мотивацию
      final averageMotivation = cravings.isNotEmpty ? totalMotivation / cravings.length : 0.0;
      
      // Вычисляем самую длинную серию успешных дней
      final longestStreak = _calculateLongestStreak(cravings);

      if (mounted) {
        setState(() {
          _cravings = cravings;
          _triggerStats = triggerStats;
          _timeOfDayStats = timeOfDayStats;
          _dayOfWeekStats = dayOfWeekStats;
          _averageMotivation = averageMotivation;
          _longestStreak = longestStreak;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading statistics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        // Показываем пользователю сообщение об ошибке только если это критично
        if (e.toString().contains('permission') || e.toString().contains('network')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки статистики: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  int _getCravingsOvercomePercentage() {
    if (_cravings.isEmpty) return 0;
    final overcome = _cravings.where((c) => c.overcome).length;
    return ((overcome / _cravings.length) * 100).toInt();
  }

  // Вычисление самой длинной серии успешных дней
  int _calculateLongestStreak(List<CravingRecord> cravings) {
    if (cravings.isEmpty) return 0;
    
    // Группируем по дням и определяем успешность дня
    final Map<String, bool> daySuccess = {};
    for (var craving in cravings) {
      final dayKey = '${craving.timestamp.year}-${craving.timestamp.month}-${craving.timestamp.day}';
      if (!daySuccess.containsKey(dayKey)) {
        daySuccess[dayKey] = true; // Предполагаем успех, если нет неудач
      }
      if (!craving.overcome) {
        daySuccess[dayKey] = false; // День считается неуспешным, если есть хотя бы одна неудача
      }
    }
    
    // Сортируем дни по дате
    final sortedDays = daySuccess.keys.toList()..sort();
    
    // Находим самую длинную серию успешных дней
    int maxStreak = 0;
    int currentStreak = 0;
    
    for (var day in sortedDays) {
      if (daySuccess[day] == true) {
        currentStreak++;
        maxStreak = currentStreak > maxStreak ? currentStreak : maxStreak;
      } else {
        currentStreak = 0;
      }
    }
    
    return maxStreak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : widget.user == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Войдите в аккаунт', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  )
                : _cravings.isEmpty && _triggerStats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('Нет данных для отображения', style: TextStyle(fontSize: 18)),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Статистика', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatCard(
                                      'Дней', 
                                      widget.user!.quitStat != null 
                                        ? '${widget.user!.quitStat!.daysWithoutSmoking}' 
                                        : '0', 
                                      Icons.calendar_today, 
                                      Colors.blue
                                    ),
                                    _buildStatCard('Желаний', '${_cravings.length}', Icons.favorite, Colors.red),
                                    _buildStatCard('Успех', '${_getCravingsOvercomePercentage()}%', Icons.check_circle, Colors.green),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Дополнительная статистика
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Дополнительная статистика', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatCard(
                                      'Средняя мотивация',
                                      _averageMotivation > 0 
                                        ? '${_averageMotivation.toStringAsFixed(1)}/10'
                                        : '0/10',
                                      Icons.trending_up,
                                      Colors.purple
                                    ),
                                    _buildStatCard(
                                      'Серия успеха',
                                      '$_longestStreak дн.',
                                      Icons.local_fire_department,
                                      Colors.orange
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Статистика по времени суток
                        if (_timeOfDayStats.isNotEmpty) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Время суток', style: Theme.of(context).textTheme.titleLarge),
                                  const SizedBox(height: 16),
                                  ..._timeOfDayStats.entries.map((e) {
                                    final total = _timeOfDayStats.values.fold<int>(0, (sum, value) => sum + value);
                                    final percentage = total > 0 ? (e.value / total * 100).toInt() : 0;
                                    final progressValue = total > 0 ? e.value / total : 0.0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(e.key),
                                              Text('${e.value} ($percentage%)'),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(value: progressValue),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // Статистика по дням недели
                        if (_dayOfWeekStats.isNotEmpty) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Дни недели', style: Theme.of(context).textTheme.titleLarge),
                                  const SizedBox(height: 16),
                                  ..._dayOfWeekStats.entries.map((e) {
                                    final total = _dayOfWeekStats.values.fold<int>(0, (sum, value) => sum + value);
                                    final percentage = total > 0 ? (e.value / total * 100).toInt() : 0;
                                    final progressValue = total > 0 ? e.value / total : 0.0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(e.key),
                                              Text('${e.value} ($percentage%)'),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(value: progressValue),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Триггеры', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 16),
                                ..._triggerStats.entries.map((e) {
                                  // Вычисляем общее количество всех триггеров
                                  final totalTriggers = _triggerStats.values.fold<int>(0, (sum, value) => sum + value);
                                  // Вычисляем процент от общего количества
                                  final percentage = totalTriggers > 0 ? (e.value / totalTriggers * 100).toInt() : 0;
                                  // Для визуализации используем процент от общего (0.0 до 1.0)
                                  final progressValue = totalTriggers > 0 ? e.value / totalTriggers : 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(e.key),
                                            Text('${e.value} ($percentage%)'),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(value: progressValue),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _statisticsSubscription?.cancel();
    super.dispose();
  }
}

// Класс для авторизации и регистрации
class AuthReg {
  static void show(
    BuildContext context, {
    required Function(User) onUserAuthenticated,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AuthRegDialog(
        onUserAuthenticated: onUserAuthenticated,
      ),
    );
  }
}

// Диалог авторизации/регистрации
class _AuthRegDialog extends StatefulWidget {
  final Function(User) onUserAuthenticated;

  const _AuthRegDialog({required this.onUserAuthenticated});

  @override
  State<_AuthRegDialog> createState() => _AuthRegDialogState();
}

class _AuthRegDialogState extends State<_AuthRegDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Заполните все поля';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      User? user;

      if (_isLogin) {
        // Авторизация через Firebase Auth
        final authService = await AuthService.createAuthService(email, password);
        user = authService.getUserInfo;
      } else {
        // Регистрация через Firebase Auth
        final regService = await RegService.createRegService(email, password);
        user = regService.user;
      }

      if (user == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Ошибка: не удалось создать пользователя';
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        // Загружаем статистику пользователя, если она есть
        if (user.isOnboarded) {
          try {
            final onboardingService = await OnBoardingService.createOnboardingService(user);
            await onboardingService.onboardingAuth();
            await onboardingService.loadQuitStats();
          } catch (e) {
            print('Error loading user stats: $e');
          }
        }

        setState(() {
          _isLoading = false;
        });

        Navigator.of(context).pop();
        // Сохраняем сессию
        await OfflineStorageService.saveSession(user.userId, user.mail);
        widget.onUserAuthenticated(user);
      }
    } catch (e) {
      print('Auth error: $e');
      if (mounted) {
        setState(() {
          String errorMsg = e.toString().replaceFirst('Exception: ', '');
          // Улучшаем сообщения об ошибках
          if (errorMsg.contains('network') || errorMsg.contains('timeout') || errorMsg.contains('unreachable')) {
            errorMsg = 'Проблема с интернет-соединением. Проверьте подключение к интернету и попробуйте снова.';
          }
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isLogin ? 'Вход' : 'Регистрация',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleAuth,
                      child: Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _errorMessage = null;
                      });
                    },
                    child: Text(
                      _isLogin
                          ? 'Нет аккаунта? Зарегистрироваться'
                          : 'Уже есть аккаунт? Войти',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Окно онбординга
class OnBoardingWindow extends StatefulWidget {
  final User user;

  const OnBoardingWindow({super.key, required this.user});

  @override
  State<OnBoardingWindow> createState() => _OnBoardingWindowState();
}

class _OnBoardingWindowState extends State<OnBoardingWindow> {
  final _formKey = GlobalKey<FormState>();
  final _smokingYearsController = TextEditingController();
  final _smokingMonthController = TextEditingController(text: '0');
  final _attemptsController = TextEditingController(text: '0');
  final _lastAttemptDateController = TextEditingController();
  String _selectedType = 'Обычные сигареты';
  bool _isLoading = false;

  // Для обычных сигарет
  final _cigTypeController = TextEditingController(text: 'thin');
  final _cigPerDayController = TextEditingController();
  final _packPriceController = TextEditingController();
  final _cigsPerPackController = TextEditingController(text: '20');

  // Для электронных сигарет
  final _puffPowerController = TextEditingController();
  final _bottlePriceController = TextEditingController();
  final _daysOnBottleController = TextEditingController();
  final _puffPerDayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lastAttemptDateController.text = DateTime.now().toString().split(' ')[0];
  }

  @override
  void dispose() {
    _smokingYearsController.dispose();
    _smokingMonthController.dispose();
    _attemptsController.dispose();
    _lastAttemptDateController.dispose();
    _cigTypeController.dispose();
    _cigPerDayController.dispose();
    _packPriceController.dispose();
    _cigsPerPackController.dispose();
    _puffPowerController.dispose();
    _bottlePriceController.dispose();
    _daysOnBottleController.dispose();
    _puffPerDayController.dispose();
    super.dispose();
  }

  Future<void> _submitOnboarding() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final smokingYears = int.tryParse(_smokingYearsController.text);
      final smokingMonth = int.tryParse(_smokingMonthController.text) ?? 0;
      final attempts = int.tryParse(_attemptsController.text) ?? 0;
      final lastDate = DateTime.tryParse(_lastAttemptDateController.text) ?? DateTime.now();

      SmokingStats stats;

      if (_selectedType == 'Обычные сигареты') {
        final cigPerDay = int.tryParse(_cigPerDayController.text) ?? 0;
        final packPrice = int.tryParse(_packPriceController.text) ?? 0;
        final cigsPerPack = int.tryParse(_cigsPerPackController.text) ?? 20;

        stats = CigStats(
          cigType: _cigTypeController.text,
          cigPerDay: cigPerDay,
          packPrice: packPrice,
          cigsPerPack: cigsPerPack,
        );
      } else {
        final puffPower = int.tryParse(_puffPowerController.text) ?? 0;
        final bottlePrice = int.tryParse(_bottlePriceController.text) ?? 0;
        final daysOnBottle = int.tryParse(_daysOnBottleController.text) ?? 1;
        final puffPerDay = int.tryParse(_puffPerDayController.text) ?? 0;

        stats = VapeStats(
          puffPower: puffPower,
          bottlePrice: bottlePrice,
          daysOnBottle: daysOnBottle,
          puffPerDay: puffPerDay,
        );
      }

      final onboardingService = await OnBoardingService.createOnboardingService(widget.user);
      await onboardingService.onboardingRegistration(
        smokingYears: smokingYears,
        smokingMonth: smokingMonth,
        attempts: attempts,
        lastDate: lastDate,
        type: _selectedType,
        stats: stats,
      );

      // Обновляем пользователя
      widget.user.isOnboarded = true;
      widget.user.isAlternative = _selectedType == 'Электронные сигареты';

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Расскажите о себе',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _smokingYearsController,
                  decoration: const InputDecoration(
                    labelText: 'Сколько лет курите (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _smokingMonthController,
                  decoration: const InputDecoration(
                    labelText: 'Сколько месяцев курите',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Введите количество месяцев';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _attemptsController,
                  decoration: const InputDecoration(
                    labelText: 'Количество попыток бросить',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastAttemptDateController,
                  decoration: const InputDecoration(
                    labelText: 'Дата последней попытки',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Тип курения',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Обычные сигареты',
                      child: Text('Обычные сигареты'),
                    ),
                    DropdownMenuItem(
                      value: 'Электронные сигареты',
                      child: Text('Электронные сигареты'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value!;
                    });
                  },
                ),
                const SizedBox(height: 24),
                if (_selectedType == 'Обычные сигареты') ...[
                  Text(
                    'Информация о сигаретах',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _cigTypeController.text,
                    decoration: const InputDecoration(
                      labelText: 'Тип сигарет',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'thin', child: Text('Тонкие')),
                      DropdownMenuItem(value: 'regular', child: Text('Обычные')),
                    ],
                    onChanged: (value) {
                      _cigTypeController.text = value ?? 'thin';
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cigPerDayController,
                    decoration: const InputDecoration(
                      labelText: 'Сигарет в день',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите количество';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _packPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Цена пачки (₽)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите цену';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cigsPerPackController,
                    decoration: const InputDecoration(
                      labelText: 'Сигарет в пачке',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ] else ...[
                  Text(
                    'Информация об электронных сигаретах',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _puffPowerController,
                    decoration: const InputDecoration(
                      labelText: 'Мощность затяжки',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bottlePriceController,
                    decoration: const InputDecoration(
                      labelText: 'Цена бутылки (₽)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите цену';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _daysOnBottleController,
                    decoration: const InputDecoration(
                      labelText: 'Дней на бутылку',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите количество дней';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _puffPerDayController,
                    decoration: const InputDecoration(
                      labelText: 'Затяжек в день',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitOnboarding,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class EditProfileWindow extends StatefulWidget {
  final User user;
  final Function(User)? onProfileUpdated;

  const EditProfileWindow({super.key, required this.user, this.onProfileUpdated});

  @override
  State<EditProfileWindow> createState() => _EditProfileWindowState();
}

class _EditProfileWindowState extends State<EditProfileWindow> {
  final _formKey = GlobalKey<FormState>();
  final _smokingYearsController = TextEditingController();
  final _smokingMonthController = TextEditingController();
  final _attemptsController = TextEditingController();
  final _lastAttemptDateController = TextEditingController();
  String _selectedType = 'Обычные сигареты';
  bool _isLoading = false;

  // Для обычных сигарет
  final _cigTypeController = TextEditingController();
  final _cigPerDayController = TextEditingController();
  final _packPriceController = TextEditingController();
  final _cigsPerPackController = TextEditingController();

  // Для электронных сигарет
  final _puffPowerController = TextEditingController();
  final _bottlePriceController = TextEditingController();
  final _daysOnBottleController = TextEditingController();
  final _puffPerDayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final user = widget.user;
    final stats = user.stats;
    
    if (stats != null) {
      _smokingYearsController.text = stats.smokingYears?.toString() ?? '';
      _smokingMonthController.text = stats.smokingMonth.toString();
      _attemptsController.text = stats.attempts.toString();
      _lastAttemptDateController.text = stats.lastAttemptDate.toString().split(' ')[0];
    } else {
      _lastAttemptDateController.text = DateTime.now().toString().split(' ')[0];
    }

    _selectedType = user.isAlternative ? 'Электронные сигареты' : 'Обычные сигареты';

    if (stats != null) {
      if (stats.stats is CigStats) {
        final cigStats = stats.stats as CigStats;
        _cigTypeController.text = cigStats.cigType;
        _cigPerDayController.text = cigStats.cigPerDay.toString();
        _packPriceController.text = cigStats.packPrice.toString();
        _cigsPerPackController.text = cigStats.cigsPerPack.toString();
      } else if (stats.stats is VapeStats) {
        final vapeStats = stats.stats as VapeStats;
        _puffPowerController.text = vapeStats.puffPower.toString();
        _bottlePriceController.text = vapeStats.bottlePrice.toString();
        _daysOnBottleController.text = vapeStats.daysOnBottle.toString();
        _puffPerDayController.text = vapeStats.puffPerDay.toString();
      }
    }
  }

  @override
  void dispose() {
    _smokingYearsController.dispose();
    _smokingMonthController.dispose();
    _attemptsController.dispose();
    _lastAttemptDateController.dispose();
    _cigTypeController.dispose();
    _cigPerDayController.dispose();
    _packPriceController.dispose();
    _cigsPerPackController.dispose();
    _puffPowerController.dispose();
    _bottlePriceController.dispose();
    _daysOnBottleController.dispose();
    _puffPerDayController.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final smokingYears = _smokingYearsController.text.isEmpty 
          ? null 
          : int.tryParse(_smokingYearsController.text);
      final smokingMonth = int.tryParse(_smokingMonthController.text) ?? 0;
      final attempts = int.tryParse(_attemptsController.text) ?? 0;
      final lastDate = DateTime.tryParse(_lastAttemptDateController.text) ?? DateTime.now();

      SmokingStats stats;

      if (_selectedType == 'Обычные сигареты') {
        final cigPerDay = int.tryParse(_cigPerDayController.text) ?? 0;
        final packPrice = int.tryParse(_packPriceController.text) ?? 0;
        final cigsPerPack = int.tryParse(_cigsPerPackController.text) ?? 20;

        stats = CigStats(
          cigType: _cigTypeController.text.isEmpty ? 'thin' : _cigTypeController.text,
          cigPerDay: cigPerDay,
          packPrice: packPrice,
          cigsPerPack: cigsPerPack,
        );
      } else {
        final puffPower = int.tryParse(_puffPowerController.text) ?? 0;
        final bottlePrice = int.tryParse(_bottlePriceController.text) ?? 0;
        final daysOnBottle = int.tryParse(_daysOnBottleController.text) ?? 1;
        final puffPerDay = int.tryParse(_puffPerDayController.text) ?? 0;

        stats = VapeStats(
          puffPower: puffPower,
          bottlePrice: bottlePrice,
          daysOnBottle: daysOnBottle,
          puffPerDay: puffPerDay,
        );
      }

      final onboardingService = await OnBoardingService.createOnboardingService(widget.user);
      await onboardingService.updateProfile(
        smokingYears: smokingYears,
        smokingMonth: smokingMonth,
        attempts: attempts,
        lastDate: lastDate,
        type: _selectedType,
        stats: stats,
      );

      // Перезагружаем статистику из Firebase для синхронизации
      await onboardingService.onboardingAuth();

      // Обновляем пользователя
      widget.user.isAlternative = _selectedType == 'Электронные сигареты';

      if (mounted) {
        Navigator.of(context).pop(widget.user);
        if (widget.onProfileUpdated != null) {
          widget.onProfileUpdated!(widget.user);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Профиль успешно обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Информация о курении',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _smokingYearsController,
                    decoration: const InputDecoration(
                      labelText: 'Сколько лет курите (необязательно)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _smokingMonthController,
                    decoration: const InputDecoration(
                      labelText: 'Сколько месяцев курите',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите количество месяцев';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _attemptsController,
                    decoration: const InputDecoration(
                      labelText: 'Количество попыток бросить',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lastAttemptDateController,
                    decoration: const InputDecoration(
                      labelText: 'Дата последней попытки',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Тип курения',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Обычные сигареты',
                        child: Text('Обычные сигареты'),
                      ),
                      DropdownMenuItem(
                        value: 'Электронные сигареты',
                        child: Text('Электронные сигареты'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_selectedType == 'Обычные сигареты') ...[
                    Text(
                      'Информация о сигаретах',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _cigTypeController.text.isEmpty ? 'thin' : _cigTypeController.text,
                      decoration: const InputDecoration(
                        labelText: 'Тип сигарет',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'thin', child: Text('Тонкие')),
                        DropdownMenuItem(value: 'regular', child: Text('Обычные')),
                      ],
                      onChanged: (value) {
                        _cigTypeController.text = value ?? 'thin';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cigPerDayController,
                      decoration: const InputDecoration(
                        labelText: 'Сигарет в день',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите количество';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _packPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Цена пачки (₽)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите цену';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cigsPerPackController,
                      decoration: const InputDecoration(
                        labelText: 'Сигарет в пачке',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ] else ...[
                    Text(
                      'Информация об электронных сигаретах',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _puffPowerController,
                      decoration: const InputDecoration(
                        labelText: 'Мощность затяжки',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bottlePriceController,
                      decoration: const InputDecoration(
                        labelText: 'Цена бутылки (₽)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите цену';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _daysOnBottleController,
                      decoration: const InputDecoration(
                        labelText: 'Дней на бутылку',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите количество дней';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _puffPerDayController,
                      decoration: const InputDecoration(
                        labelText: 'Затяжек в день',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitProfile,
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Сохранить изменения'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}