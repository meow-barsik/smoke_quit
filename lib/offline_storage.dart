import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dataModels.dart';

class OfflineStorageService {
  static const String _userBoxName = 'users';
  static const String _statsBoxName = 'stats';
  static const String _cravingsBoxName = 'cravings';
  static const String _diariesBoxName = 'diaries';
  static const String _quitStatsBoxName = 'quitStats';
  static const String _syncQueueBoxName = 'syncQueue';
  static const String _articlesBoxName = 'articles';
  static const String _settingsBoxName = 'settings';
  static const String _sessionBoxName = 'session';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    
    await Hive.initFlutter();
    _initialized = true;
  }

  // Проверка подключения к интернету
  static Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) ||
           connectivityResult.contains(ConnectivityResult.wifi) ||
           connectivityResult.contains(ConnectivityResult.ethernet);
  }

  // Сохранение пользователя локально
  static Future<void> saveUserLocally(User user) async {
    final box = await Hive.openBox(_userBoxName);
    await box.put(user.userId, {
      'userId': user.userId,
      'mail': user.mail,
      'password': user.getPasswd,
      'isAlternative': user.isAlternative,
      'isOnboarded': user.isOnboarded,
    });
  }

  // Загрузка пользователя из локального хранилища
  static Future<User?> getUserLocally(String userId) async {
    try {
      final box = await Hive.openBox(_userBoxName);
      final data = box.get(userId);
      if (data == null) return null;
      
      final userData = Map<String, dynamic>.from(data as Map);
      return User.fromMap(userId, userData);
    } catch (e) {
      print('Error loading user locally: $e');
      return null;
    }
  }

  // Сохранение статистики пользователя локально
  static Future<void> saveUserStatsLocally(String userId, UserStats stats) async {
    final box = await Hive.openBox(_statsBoxName);
    await box.put(userId, stats.toJson());
  }

  // Загрузка статистики пользователя из локального хранилища
  static Future<UserStats?> getUserStatsLocally(String userId, User user) async {
    try {
      final box = await Hive.openBox(_statsBoxName);
      final data = box.get(userId);
      if (data == null) return null;
      
      final statsData = Map<String, dynamic>.from(data as Map);
      return UserStats.fromJson(statsData, user);
    } catch (e) {
      print('Error loading stats locally: $e');
      return null;
    }
  }

  // Сохранение записи о тяге локально
  static Future<void> saveCravingLocally(CravingRecord craving) async {
    final box = await Hive.openBox(_cravingsBoxName);
    await box.put(craving.id, craving.toJson());
  }

  // Загрузка всех записей о тяге локально
  static Future<List<CravingRecord>> getAllCravingsLocally() async {
    try {
      final box = await Hive.openBox(_cravingsBoxName);
      final cravings = <CravingRecord>[];
      
      for (var key in box.keys) {
        try {
          final data = box.get(key);
          if (data != null) {
            final cravingData = Map<String, dynamic>.from(data as Map);
            cravings.add(CravingRecord.fromJson(cravingData));
          }
        } catch (e) {
          print('Error parsing craving $key: $e');
        }
      }
      
      return cravings;
    } catch (e) {
      print('Error loading cravings locally: $e');
      return [];
    }
  }

  // Сохранение дневника локально
  static Future<void> saveDiaryLocally(SmokingDiary diary) async {
    final box = await Hive.openBox(_diariesBoxName);
    await box.put('${diary.userId}_${diary.date.toIso8601String().split('T')[0]}', diary.toJson());
  }

  // Загрузка дневника локально
  static Future<SmokingDiary?> getDiaryLocally(String userId, DateTime date) async {
    try {
      final box = await Hive.openBox(_diariesBoxName);
      final key = '${userId}_${date.toIso8601String().split('T')[0]}';
      final data = box.get(key);
      if (data == null) return null;
      
      final diaryData = Map<String, dynamic>.from(data as Map);
      return SmokingDiary.fromJson(diaryData, userId);
    } catch (e) {
      print('Error loading diary locally: $e');
      return null;
    }
  }

  // Добавление операции в очередь синхронизации
  static Future<void> addToSyncQueue(String operation, Map<String, dynamic> data) async {
    final box = await Hive.openBox(_syncQueueBoxName);
    final queueItem = {
      'operation': operation,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    await box.put(queueItem['id'], queueItem);
  }

  // Получение всех операций из очереди синхронизации
  static Future<List<Map<String, dynamic>>> getSyncQueue() async {
    try {
      final box = await Hive.openBox(_syncQueueBoxName);
      final queue = <Map<String, dynamic>>[];
      
      for (var key in box.keys) {
        final item = box.get(key);
        if (item != null) {
          queue.add(Map<String, dynamic>.from(item as Map));
        }
      }
      
      // Сортируем по timestamp
      queue.sort((a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String));
      return queue;
    } catch (e) {
      print('Error loading sync queue: $e');
      return [];
    }
  }

  // Удаление операции из очереди синхронизации
  static Future<void> removeFromSyncQueue(String id) async {
    final box = await Hive.openBox(_syncQueueBoxName);
    await box.delete(id);
  }

  // Сохранение сессии пользователя
  static Future<void> saveSession(String userId, String email) async {
    final box = await Hive.openBox(_sessionBoxName);
    await box.put('currentSession', {
      'userId': userId,
      'email': email,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Получение сохраненной сессии
  static Future<Map<String, String>?> getSession() async {
    try {
      final box = await Hive.openBox(_sessionBoxName);
      final data = box.get('currentSession');
      if (data == null) return null;
      
      final sessionData = Map<String, dynamic>.from(data as Map);
      return {
        'userId': sessionData['userId']?.toString() ?? '',
        'email': sessionData['email']?.toString() ?? '',
      };
    } catch (e) {
      print('Error loading session: $e');
      return null;
    }
  }

  // Очистка сессии
  static Future<void> clearSession() async {
    try {
      final box = await Hive.openBox(_sessionBoxName);
      await box.delete('currentSession');
    } catch (e) {
      print('Error clearing session: $e');
    }
  }

  // Очистка всех данных локального хранилища
  static Future<void> clearAll() async {
    try {
      await Hive.deleteBoxFromDisk(_userBoxName);
      await Hive.deleteBoxFromDisk(_statsBoxName);
      await Hive.deleteBoxFromDisk(_cravingsBoxName);
      await Hive.deleteBoxFromDisk(_diariesBoxName);
      await Hive.deleteBoxFromDisk(_quitStatsBoxName);
      await Hive.deleteBoxFromDisk(_syncQueueBoxName);
      await Hive.deleteBoxFromDisk(_articlesBoxName);
      await Hive.deleteBoxFromDisk(_sessionBoxName);
    } catch (e) {
      print('Error clearing offline storage: $e');
    }
  }

  // Сохранение статей локально
  static Future<void> saveArticlesLocally(List<Article> articles) async {
    final box = await Hive.openBox(_articlesBoxName);
    await box.put('articles_list', articles.map((a) => a.toJson()).toList());
  }

  // Загрузка статей из локального хранилища
  static Future<List<Article>> getArticlesLocally() async {
    try {
      final box = await Hive.openBox(_articlesBoxName);
      final data = box.get('articles_list');
      if (data == null) return [];
      
      final articlesList = data as List;
      return articlesList.map((a) => Article.fromJson(Map<String, dynamic>.from(a as Map))).toList();
    } catch (e) {
      print('Error loading articles locally: $e');
      return [];
    }
  }

  // Сохранение темы
  static Future<void> saveThemeMode(String themeMode) async {
    final box = await Hive.openBox(_settingsBoxName);
    await box.put('themeMode', themeMode);
  }

  // Загрузка темы
  static Future<String> getThemeMode() async {
    try {
      final box = await Hive.openBox(_settingsBoxName);
      return box.get('themeMode', defaultValue: 'system') as String;
    } catch (e) {
      print('Error loading theme mode: $e');
      return 'system';
    }
  }
}

