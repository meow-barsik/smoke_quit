import 'dart:core';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dataModels.dart';
import 'offline_storage.dart';

class RegService {
  final DatabaseReference databaseReference;
  final User user;

  RegService._({required this.user, required this.databaseReference});

  static Future<RegService> createRegService(
    String email,
    String password,
  ) async {
    try {
      print('Starting registration for: $email');
      
      // Регистрация через Firebase Auth
      final firebase_auth.FirebaseAuth auth = firebase_auth.FirebaseAuth.instance;
      print('Firebase Auth instance created');
      
      final firebase_auth.UserCredential userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        throw Exception('Ошибка: пользователь не был создан');
      }
      
      print('Firebase Auth user created: ${userCredential.user!.uid}');
      final String userId = userCredential.user!.uid;
      
      final DatabaseReference database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com',
      );

      print('Database reference created');
      
      // Создаем пользователя в базе данных
      final User user = User(userId, email, '', false, false); // Пароль не храним в БД
      print('User object created, adding to database...');
      
      await _addUserData(database, user, userId, email);
      
      print('User data added successfully');
      return RegService._(user: user, databaseReference: database);
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      if (e.code == 'weak-password') {
        throw Exception('Пароль слишком слабый');
      } else if (e.code == 'email-already-in-use') {
        throw Exception('Этот email уже зарегистрирован');
      } else if (e.code == 'invalid-email') {
        throw Exception('Неверный формат email');
      } else if (e.code == 'network-request-failed' || e.message?.contains('network') == true) {
        throw Exception('Проблема с интернет-соединением. Проверьте подключение к интернету и попробуйте снова.');
      } else if (e.code == 'too-many-requests') {
        throw Exception('Слишком много попыток. Попробуйте позже.');
      } else {
        throw Exception('Ошибка регистрации: ${e.message ?? e.code}');
      }
    } on Exception catch (e) {
      print('Exception during registration: $e');
      rethrow;
    } catch (e) {
      print('Error registering user: $e');
      print('Error type: ${e.runtimeType}');
      if (e.toString().contains('network') || e.toString().contains('timeout') || e.toString().contains('unreachable')) {
        throw Exception('Проблема с интернет-соединением. Проверьте подключение к интернету и попробуйте снова.');
      }
      rethrow;
    }
  }

  static Future<void> _addUserData(
    DatabaseReference ref,
    User user,
    String key,
    String mail,
  ) async {
    try {
      print('Adding user to users/$key');
      await ref.child('users').child(key).set(user.getMap());
      print('User added to users/$key');
      
      print('Adding user to usersIndex/$key');
      await ref.child('usersIndex').child(key).set(mail);
      print('User added to usersIndex/$key');
      
      print('User registered successfully: $mail');
    } catch (e) {
      print('Error adding user data: $e');
      print('Error type: ${e.runtimeType}');
      rethrow;
    }
  }
}

class AuthService {
  final User? _user;

  AuthService._(this._user);

  static Future<AuthService> createAuthService(
    String email,
    String password,
  ) async {
    try {
      // Авторизация через Firebase Auth
      final firebase_auth.FirebaseAuth auth = firebase_auth.FirebaseAuth.instance;
      final firebase_auth.UserCredential userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        throw Exception('Ошибка: пользователь не найден');
      }
      
      final String userId = userCredential.user!.uid;
      
      // Загружаем данные пользователя из базы данных
      final DatabaseReference database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final User? user = await _getUserData(userId, database);
      
      // Если пользователя нет в базе данных, создаем его
      if (user == null) {
        final newUser = User(userId, email, '', false, false);
        await database.child('users').child(userId).set(newUser.getMap());
        await database.child('usersIndex').child(userId).set(email);
        return AuthService._(newUser);
      }

      return AuthService._(user);
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      if (e.code == 'user-not-found') {
        throw Exception('Пользователь не найден');
      } else if (e.code == 'wrong-password') {
        throw Exception('Неверный пароль');
      } else if (e.code == 'invalid-email') {
        throw Exception('Неверный формат email');
      } else if (e.code == 'user-disabled') {
        throw Exception('Пользователь заблокирован');
      } else if (e.code == 'network-request-failed' || e.message?.contains('network') == true) {
        throw Exception('Проблема с интернет-соединением. Проверьте подключение к интернету и попробуйте снова.');
      } else if (e.code == 'too-many-requests') {
        throw Exception('Слишком много попыток. Попробуйте позже.');
      } else {
        throw Exception('Ошибка авторизации: ${e.message ?? e.code}');
      }
    } on Exception catch (e) {
      print('Exception during auth: $e');
      rethrow;
    } catch (e) {
      print('Error authenticating user: $e');
      if (e.toString().contains('network') || e.toString().contains('timeout') || e.toString().contains('unreachable')) {
        throw Exception('Проблема с интернет-соединением. Проверьте подключение к интернету и попробуйте снова.');
      }
      rethrow;
    }
  }

  static Future<User?> _getUserData(
    String userId,
    DatabaseReference database,
  ) async {
    try {
      final DataSnapshot snapshot = await database
          .child('users')
          .child(userId)
          .get();

      if (!snapshot.exists) {
        return null;
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      return User.fromMap(userId, data);
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  User? get getUserInfo => _user;
}

class OnBoardingService {
  final DatabaseReference database;
  final User user;

  OnBoardingService({required this.database, required this.user});

  static Future<OnBoardingService> createOnboardingService(User user) async {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    return OnBoardingService(database: database, user: user);
  }

  Future<void> onboardingRegistration({
    required int? smokingYears,
    required int smokingMonth,
    required int attempts,
    required DateTime lastDate,
    required String type,
    required SmokingStats stats,
  }) async {
    try {
      // Обновляем тип пользователя
      await database.child('users').child(user.userId).update({
        "isAlternative": type == "Электронные сигареты",
        "isOnboarded": true,
      });

      // Создаем статистику пользователя
      final UserStats userStats = UserStats(
        smokingYears: smokingYears,
        smokingMonth: smokingMonth,
        attempts: attempts,
        lastAttemptDate: lastDate,
        stats: stats,
      );

      // Сохраняем статистику
      await database.child('stats').child(user.userId).set(userStats.toJson());

      // Сохраняем дату начала отказа от курения
      await database.child('quitDates').child(user.userId).set({
        'startDate': DateTime.now().toIso8601String(),
        'lastUpdate': DateTime.now().toIso8601String(),
      });

      print('Onboarding data saved successfully for user: ${user.userId}');
    } catch (e) {
      print('Error saving onboarding data: $e');
      rethrow;
    }
  }

  Future<void> updateProfile({
    required int? smokingYears,
    required int smokingMonth,
    required int attempts,
    required DateTime lastDate,
    required String type,
    required SmokingStats stats,
  }) async {
    try {
      // Создаем обновленную статистику пользователя
      final UserStats userStats = UserStats(
        smokingYears: smokingYears,
        smokingMonth: smokingMonth,
        attempts: attempts,
        lastAttemptDate: lastDate,
        stats: stats,
      );

      // Обновляем пользователя в памяти
      user.isAlternative = type == "Электронные сигареты";
      user.stats = userStats;

      // Всегда сохраняем локально
      await OfflineStorageService.saveUserLocally(user);
      await OfflineStorageService.saveUserStatsLocally(user.userId, userStats);

      final isOnline = await OfflineStorageService.isOnline();

      if (isOnline) {
        try {
          // Обновляем тип пользователя
          await database.child('users').child(user.userId).update({
            "isAlternative": type == "Электронные сигареты",
          });

          // Обновляем статистику
          await database.child('stats').child(user.userId).update(userStats.toJson());

          print('Profile updated successfully for user: ${user.userId}');
        } catch (e) {
          print('Error updating profile in Firebase, saved locally: $e');
          // Добавляем в очередь синхронизации
          await OfflineStorageService.addToSyncQueue('updateProfile', {
            'userId': user.userId,
            'isAlternative': type == "Электронные сигареты",
            'stats': userStats.toJson(),
          });
        }
      } else {
        // Офлайн режим - добавляем в очередь синхронизации
        await OfflineStorageService.addToSyncQueue('updateProfile', {
          'userId': user.userId,
          'isAlternative': type == "Электронные сигареты",
          'stats': userStats.toJson(),
        });
        print('Offline: profile updated locally, will sync when online');
      }
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  Future<void> onboardingAuth() async {
    try {
      final DataSnapshot snap = await database
          .child('stats')
          .child(user.userId)
          .get();

      if (!snap.exists) {
        throw Exception('No stats found for user');
      }

      final data = snap.value as Map<dynamic, dynamic>;
      final userStats = UserStats.fromJson(
        Map<String, dynamic>.from(data),
        user,
      );
      user.stats = userStats;

      print('Onboarding data loaded successfully for user: ${user.userId}');
    } catch (e) {
      print('Error loading onboarding data: $e');
      rethrow;
    }
  }

  // Метод для загрузки статистики отказа при онбординге
  Future<void> loadQuitStats() async {
    try {
      final quitUser = await StartQuit.getActiveQuitStats(user);
      if (quitUser != null) {
        // Загружаем желания для этой попытки
        final database = FirebaseDatabase.instance.refFromURL(
          'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
        );
        await StartQuit._loadCravingsForQuit(database, quitUser);
        user.quitStat = quitUser;
      }
    } catch (e) {
      print('Error loading quit stats: $e');
    }
  }
}

class StartQuit {
  final User user;
  final QuitUser userQuit;

  StartQuit(this.user, this.userQuit);

  static Future<QuitUser?> searchUserQuit(DatabaseReference database, User user) async {
    try {
      final DataSnapshot userInfo = await database.child('quitIndex').get();
      
      if (!userInfo.exists) {
        return null;
      }

      final Map<dynamic, dynamic> usersMap = userInfo.value as Map<dynamic, dynamic>;

      for (var entry in usersMap.entries) {
        if (entry.value == user.userId) {
          final DataSnapshot foundedUser = await database
              .child('quitStats')
              .child(entry.key.toString())
              .get();
          
          if (foundedUser.exists) {
            final Map<String, dynamic> userData = Map<String, dynamic>.from(
              foundedUser.value as Map<dynamic, dynamic>
            );
            return QuitUser.byList(userData, user);
          }
        }
      }
      return null;
    } catch (e) {
      print('Error searching user quit: $e');
      return null;
    }
  }

  // Получить все активные попытки отказа пользователя
  static Future<List<QuitUser>> searchAllUserQuits(DatabaseReference database, User user) async {
    try {
      final DataSnapshot userInfo = await database.child('quitIndex').get();
      
      if (!userInfo.exists) {
        return [];
      }

      final List<QuitUser> quits = [];
      final Map<dynamic, dynamic> usersMap = userInfo.value as Map<dynamic, dynamic>;

      for (var entry in usersMap.entries) {
        if (entry.value == user.userId) {
          final DataSnapshot foundedUser = await database
              .child('quitStats')
              .child(entry.key.toString())
              .get();
          
          if (foundedUser.exists) {
            final Map<String, dynamic> userData = Map<String, dynamic>.from(
              foundedUser.value as Map<dynamic, dynamic>
            );
            final quitUser = QuitUser.byList(userData, user);
            quits.add(quitUser);
          }
        }
      }
      return quits;
    } catch (e) {
      print('Error searching all user quits: $e');
      return [];
    }
  }

  static Future<QuitUser> createUserQuit(DatabaseReference database, User user) async {
    String? key = database.child('quitStats').push().key;
    QuitUser quitStats = QuitUser.newUser(user, key!);

    await database.child('quitStats').child(key).set(quitStats.getMap());
    await database.child('quitIndex').child(key).set(user.userId);

    // Обновляем сводную статистику пользователя: totalAttempts
    try {
      final userSummaryRef = database.child('userSummary').child(user.userId);
      final DataSnapshot userSnap = await userSummaryRef.get();
      int totalAttempts = 1;
      if (userSnap.exists) {
        final Map<dynamic, dynamic> map = userSnap.value as Map<dynamic, dynamic>;
        totalAttempts = (map['totalAttempts'] as num? ?? 0).toInt() + 1;
      }
      await userSummaryRef.update({'totalAttempts': totalAttempts});
    } catch (e) {
      print('Error updating user summary attempts: $e');
    }

    // Обновляем глобальную сводку: totalAttempts
    try {
      final globalRef = database.child('globalSummary');
      final DataSnapshot gSnap = await globalRef.get();
      int totalAttemptsAll = 1;
      if (gSnap.exists) {
        final Map<dynamic, dynamic> map = gSnap.value as Map<dynamic, dynamic>;
        totalAttemptsAll = (map['totalAttempts'] as num? ?? 0).toInt() + 1;
      }
      await globalRef.update({'totalAttempts': totalAttemptsAll});
    } catch (e) {
      print('Error updating global summary attempts: $e');
    }

    return quitStats;
  }

  static Future<StartQuit> startQuit(User user) async {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    
    final isOnline = await OfflineStorageService.isOnline();
    
    // Всегда создаем новую попытку
    QuitUser quitStats;
    if (isOnline) {
      try {
        quitStats = await createUserQuit(database, user);
      } catch (e) {
        print('Error creating quit attempt online, creating locally: $e');
        // Создаем локально с временным ID
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        quitStats = QuitUser.newUser(user, tempId);
        // Добавляем в очередь синхронизации
        await OfflineStorageService.addToSyncQueue('startQuit', quitStats.getMap());
      }
    } else {
      // Офлайн режим - создаем локально
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      quitStats = QuitUser.newUser(user, tempId);
      // Добавляем в очередь синхронизации
      await OfflineStorageService.addToSyncQueue('startQuit', quitStats.getMap());
      print('Offline: quit attempt created locally, will sync when online');
    }
    
    return StartQuit(user, quitStats);
  }

  // Получить все попытки пользователя
  static Future<List<QuitUser>> getAllUserQuits(User user) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final allQuits = await searchAllUserQuits(database, user);
      
      // Загружаем желания для каждой попытки
      for (var quit in allQuits) {
        await _loadCravingsForQuit(database, quit);
      }
      
      return allQuits;
    } catch (e) {
      print('Error getting all user quits: $e');
      return [];
    }
  }

  // Получить активную попытку пользователя
  static Future<QuitUser?> getActiveQuitStats(User user) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final allQuits = await searchAllUserQuits(database, user);
      if (allQuits.isEmpty) return null;
      
      final activeQuit = allQuits.last;
      // Загружаем желания для активной попытки
      await _loadCravingsForQuit(database, activeQuit);
      
      return activeQuit;
    } catch (e) {
      print('Error getting active quit stats: $e');
      return null;
    }
  }

  // Метод для получения актуальной статистики отказа (старое имя, для совместимости)
  static Future<QuitUser?> getCurrentQuitStats(User user) async {
    return getActiveQuitStats(user);
  }

  // Загрузить все желания для конкретной попытки
  static Future<void> _loadCravingsForQuit(DatabaseReference database, QuitUser quitUser) async {
    try {
      final snapshot = await database
          .child('cravings')
          .child(quitUser.quitId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final cravings = <CravingRecord>[];
        
        data.forEach((key, value) {
          try {
            final record = CravingRecord.fromJson(
              Map<String, dynamic>.from(value as Map<dynamic, dynamic>)
            );
            cravings.add(record);
          } catch (e) {
            print('Error parsing craving record: $e');
          }
        });
        
        quitUser.allCravings = cravings;
        print('Loaded ${cravings.length} craving records for quit ${quitUser.quitId}');
      } else {
        quitUser.allCravings = [];
      }
    } catch (e) {
      print('Error loading cravings for quit: $e');
      quitUser.allCravings = [];
    }
  }

  // Метод для завершения попытки отказа
  static Future<void> endQuitAttempt(User user, QuitUser quitUser, String status, {bool failedDueToCraving = false}) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      await database.child('quitStats').child(quitUser.quitId).update({
        'quitEnd': DateTime.now().toIso8601String(),
        'status': status, // 'completed', 'failed'
        'isQuiting': false,
        'failedDueToCraving': failedDueToCraving,
      });

      quitUser.quitEnd = DateTime.now();
      quitUser.status = status;
      quitUser.isQuiting = false;
      quitUser.failedDueToCraving = failedDueToCraving;
    } catch (e) {
      print('Error ending quit attempt: $e');
      rethrow;
    }
  }

  // Метод для обновления статистики отказа
  static Future<void> updateQuitStats(User user, QuitUser quitUser) async {
    try {
      final isOnline = await OfflineStorageService.isOnline();
      final updateData = {
        'daysOut': quitUser.daysWithoutSmoking,
        'moneySaved': quitUser.calculateMoneySaved(user.stats),
        'lastUpdate': DateTime.now().toIso8601String(),
      };

      if (isOnline) {
        try {
          final database = FirebaseDatabase.instance.refFromURL(
            'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
          );
          
          await database.child('quitStats').child(quitUser.quitId).update(updateData);
        } catch (e) {
          print('Error updating quit stats in Firebase, saving to queue: $e');
          // Добавляем в очередь синхронизации
          await OfflineStorageService.addToSyncQueue('updateQuitStats', {
            'quitId': quitUser.quitId,
            ...updateData,
          });
        }
      } else {
        // Офлайн режим - добавляем в очередь синхронизации
        await OfflineStorageService.addToSyncQueue('updateQuitStats', {
          'quitId': quitUser.quitId,
          ...updateData,
        });
        print('Offline: quit stats updated locally, will sync when online');
      }
    } catch (e) {
      print('Error updating quit stats: $e');
      rethrow;
    }
  }

  // Получить статистику пользователя из Firebase
  static Future<Map<String, dynamic>> getUserSummary(String userId) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final snapshot = await database.child('userSummary').child(userId).get();
      
      if (!snapshot.exists) {
        return {
          'totalAttempts': 0,
          'totalCravings': 0,
          'totalOvercome': 0,
          'avgMotivation': 0.0,
          'lastUpdate': DateTime.now().toIso8601String(),
        };
      }

      final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
      return {
        'totalAttempts': (data['totalAttempts'] as num?)?.toInt() ?? 0,
        'totalCravings': (data['totalCravings'] as num?)?.toInt() ?? 0,
        'totalOvercome': (data['totalOvercome'] as num?)?.toInt() ?? 0,
        'avgMotivation': (data['avgMotivation'] as num?)?.toDouble() ?? 0.0,
        'lastUpdate': data['lastUpdate']?.toString() ?? DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error getting user summary: $e');
      return {};
    }
  }

  // Получить глобальную статистику приложения
  static Future<Map<String, dynamic>> getGlobalSummary() async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final snapshot = await database.child('globalSummary').get();
      
      if (!snapshot.exists) {
        return {
          'totalAttempts': 0,
          'totalCravings': 0,
          'totalOvercome': 0,
          'lastUpdate': DateTime.now().toIso8601String(),
        };
      }

      final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
      return {
        'totalAttempts': (data['totalAttempts'] as num?)?.toInt() ?? 0,
        'totalCravings': (data['totalCravings'] as num?)?.toInt() ?? 0,
        'totalOvercome': (data['totalOvercome'] as num?)?.toInt() ?? 0,
        'lastUpdate': data['lastUpdate']?.toString() ?? DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error getting global summary: $e');
      return {};
    }
  }
}

// Сервис для работы со статьями
class ArticleService {
  final DatabaseReference database;

  ArticleService({required this.database});

  // Простой конструктор без Future
  factory ArticleService.create() {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    return ArticleService(database: database);
  }

  // Добавление новой статьи
  Future<void> addArticle({
    required String title,
    required String content,
    required String category,
    required String author,
  }) async {
    try {
      final String? articleId = database.child('articles').push().key;
      if (articleId == null) {
        throw Exception('Failed to create article ID');
      }

      final Article article = Article(
        id: articleId,
        title: title,
        content: content,
        category: category,
        author: author,
        createdAt: DateTime.now(),
        isPublished: true,
      );

      await database.child('articles').child(articleId).set(article.toJson());
      print('Article added successfully: $title');
    } catch (e) {
      print('Error adding article: $e');
      rethrow;
    }
  }

  // Получение всех статей
  Future<List<Article>> getAllArticles() async {
    try {
      final DataSnapshot snapshot = await database.child('articles').get();
      
      if (!snapshot.exists) {
        return [];
      }

      final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
      final List<Article> articles = [];

      data.forEach((key, value) {
        final articleData = Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
        articles.add(Article.fromJson(articleData));
      });

      // Сортируем по дате создания (новые сначала)
      articles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return articles;
    } catch (e) {
      print('Error getting articles: $e');
      return [];
    }
  }

  // Получение статей по категории
  Future<List<Article>> getArticlesByCategory(String category) async {
    try {
      final allArticles = await getAllArticles();
      return allArticles.where((article) => article.category == category).toList();
    } catch (e) {
      print('Error getting articles by category: $e');
      return [];
    }
  }

  // Удаление статьи
  Future<void> deleteArticle(String articleId) async {
    try {
      await database.child('articles').child(articleId).remove();
      print('Article deleted successfully: $articleId');
    } catch (e) {
      print('Error deleting article: $e');
      rethrow;
    }
  }

  // Обновление статьи
  Future<void> updateArticle(Article article) async {
    try {
      await database.child('articles').child(article.id).update(article.toJson());
      print('Article updated successfully: ${article.title}');
    } catch (e) {
      print('Error updating article: $e');
      rethrow;
    }
  }
}

// Сервис для администраторов
class AdminService {
  final DatabaseReference database;

  AdminService({required this.database});

  static Future<AdminService> createAdminService() async {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    return AdminService(database: database);
  }

  // Проверка, является ли пользователь администратором
  static Future<bool> isUserAdmin(String email) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );
      
      final snapshot = await database.child('admins').get();
      
      if (!snapshot.exists) {
        return false;
      }

      final Map<dynamic, dynamic> admins = snapshot.value as Map<dynamic, dynamic>;
      
      for (var adminData in admins.values) {
        if (adminData is Map) {
          final Map<dynamic, dynamic> data = adminData;
          if (data['email'] == email && (data['isActive'] ?? true)) {
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
    }
  }

  // Добавить администратора
  Future<void> addAdmin(String email, String fullName) async {
    try {
      final adminId = database.child('admins').push().key;
      if (adminId == null) {
        throw Exception('Failed to create admin ID');
      }

      await database.child('admins').child(adminId).set({
        'email': email,
        'fullName': fullName,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
        'role': 'moderator',
      });

      print('Admin added successfully: $email');
    } catch (e) {
      print('Error adding admin: $e');
      rethrow;
    }
  }

  // Удалить администратора
  Future<void> removeAdmin(String adminId) async {
    try {
      await database.child('admins').child(adminId).remove();
      print('Admin removed successfully: $adminId');
    } catch (e) {
      print('Error removing admin: $e');
      rethrow;
    }
  }

  // Деактивировать администратора
  Future<void> deactivateAdmin(String adminId) async {
    try {
      await database.child('admins').child(adminId).update({
        'isActive': false,
      });
      print('Admin deactivated: $adminId');
    } catch (e) {
      print('Error deactivating admin: $e');
      rethrow;
    }
  }

  // Активировать администратора
  Future<void> activateAdmin(String adminId) async {
    try {
      await database.child('admins').child(adminId).update({
        'isActive': true,
      });
      print('Admin activated: $adminId');
    } catch (e) {
      print('Error activating admin: $e');
      rethrow;
    }
  }

  // Получить всех администраторов
  Future<List<AdminUser>> getAllAdmins() async {
    try {
      final snapshot = await database.child('admins').get();
      
      if (!snapshot.exists) {
        return [];
      }

      final List<AdminUser> admins = [];
      final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        if (value is Map) {
          final adminData = Map<String, dynamic>.from(value);
          admins.add(AdminUser(
            id: key.toString(),
            email: adminData['email'] ?? '',
            fullName: adminData['fullName'] ?? '',
            isActive: adminData['isActive'] ?? true,
            role: adminData['role'] ?? 'moderator',
            createdAt: DateTime.tryParse(adminData['createdAt'] ?? '') ?? DateTime.now(),
          ));
        }
      });

      return admins;
    } catch (e) {
      print('Error getting admins: $e');
      return [];
    }
  }

  // Получить администратора по email
  Future<AdminUser?> getAdminByEmail(String email) async {
    try {
      final snapshot = await database.child('admins').get();
      
      if (!snapshot.exists) {
        return null;
      }

      final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;

      for (var entry in data.entries) {
        if (entry.value is Map) {
          final adminData = Map<dynamic, dynamic>.from(entry.value);
          if (adminData['email'] == email) {
            return AdminUser(
              id: entry.key.toString(),
              email: adminData['email'] ?? '',
              fullName: adminData['fullName'] ?? '',
              isActive: adminData['isActive'] ?? true,
              role: adminData['role'] ?? 'moderator',
              createdAt: DateTime.tryParse(adminData['createdAt'] ?? '') ?? DateTime.now(),
            );
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting admin by email: $e');
      return null;
    }
  }

  // Обновить роль администратора
  Future<void> updateAdminRole(String adminId, String newRole) async {
    try {
      await database.child('admins').child(adminId).update({
        'role': newRole,
      });
      print('Admin role updated: $adminId -> $newRole');
    } catch (e) {
      print('Error updating admin role: $e');
      rethrow;
    }
  }
}

// Сервис для работы с дневником курения и желаниями
class SmokingDiaryService {
  final DatabaseReference database;

  SmokingDiaryService({required this.database});

  factory SmokingDiaryService.create() {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    return SmokingDiaryService(database: database);
  }

  // Добавить запись о желании курить (глобально для всех попыток)
  Future<void> addCravingRecordGlobal(User user, CravingRecord record) async {
    try {
      // Всегда сохраняем локально
      await OfflineStorageService.saveCravingLocally(record);
      
      final isOnline = await OfflineStorageService.isOnline();

      if (isOnline) {
        try {
          // Сохраняем в глобальный узел желаний пользователя
          await database
              .child('allUserCravings')
              .child(user.userId)
              .child(record.id)
              .set(record.toJson());

          // Обновляем агрегированные сводки
          await _updateUserAndGlobalSummary(user, record);

          print('Global craving record added: ${record.trigger}, overcome: ${record.overcome}');
        } catch (e) {
          print('Error adding to Firebase, saving to sync queue: $e');
          // Добавляем в очередь синхронизации
          await OfflineStorageService.addToSyncQueue('saveCraving', record.toJson());
        }
      } else {
        // Нет интернета - добавляем в очередь синхронизации
        await OfflineStorageService.addToSyncQueue('saveCraving', record.toJson());
        print('Offline: craving saved locally, will sync when online');
      }
    } catch (e) {
      print('Error adding global craving record: $e');
      rethrow;
    }
  }

  // Старый метод для совместимости (сохраняет по попыткам)
  Future<void> addCravingRecord(User user, CravingRecord record) async {
    try {
      final quitUser = user.quitStat;
      if (quitUser == null) throw Exception('Пользователь не начал отказ от курения');

      // Сохраняем основную запись под отдельным узлом cravings/<quitId>/<recordId>
      await database
          .child('cravings')
          .child(quitUser.quitId)
          .child(record.id)
          .set(record.toJson());

      // Также сохраняем глобально
      await addCravingRecordGlobal(user, record);

      quitUser.allCravings.add(record);

      // Обновляем мета-статистику попытки (дни/деньги)
      try {
        await StartQuit.updateQuitStats(user, quitUser);
      } catch (e) {
        print('Error updating quit stats after craving: $e');
      }

      print('Craving record added: ${record.trigger}, overcome: ${record.overcome}');
    } catch (e) {
      print('Error adding craving record: $e');
      rethrow;
    }
  }

  // Обновление пользовательской и глобальной сводки при добавлении записи о тяге
  Future<void> _updateUserAndGlobalSummary(User user, CravingRecord record) async {
    try {
      final userSummaryRef = database.child('userSummary').child(user.userId);
      final DataSnapshot userSnap = await userSummaryRef.get();

      int totalCravings = 0;
      int totalOvercome = 0;
      double avgMotivation = 0.0;

      if (userSnap.exists) {
        final Map<dynamic, dynamic> map = userSnap.value as Map<dynamic, dynamic>;
        totalCravings = (map['totalCravings'] as num? ?? 0).toInt();
        totalOvercome = (map['totalOvercome'] as num? ?? 0).toInt();
        avgMotivation = (map['avgMotivation'] as num? ?? 0).toDouble();
      }

      final int newTotal = totalCravings + 1;
      final int newOvercome = totalOvercome + (record.overcome ? 1 : 0);
      final double newAvgMotivation = newTotal > 0 
          ? (avgMotivation * totalCravings + record.motivationLevel) / newTotal 
          : 0.0;

      await userSummaryRef.update({
        'totalCravings': newTotal,
        'totalOvercome': newOvercome,
        'avgMotivation': newAvgMotivation,
        'lastUpdate': DateTime.now().toIso8601String(),
      });
      
      print('User summary updated: total=$newTotal, overcome=$newOvercome');
    } catch (e) {
      print('Error updating user summary: $e');
    }

    try {
      final globalRef = database.child('globalSummary');
      final DataSnapshot gSnap = await globalRef.get();

      int gTotalCravings = 0;
      int gTotalOvercome = 0;

      if (gSnap.exists) {
        final Map<dynamic, dynamic> gmap = gSnap.value as Map<dynamic, dynamic>;
        gTotalCravings = (gmap['totalCravings'] as num? ?? 0).toInt();
        gTotalOvercome = (gmap['totalOvercome'] as num? ?? 0).toInt();
      }

      final int gNewTotal = gTotalCravings + 1;
      final int gNewOvercome = gTotalOvercome + (record.overcome ? 1 : 0);

      await globalRef.update({
        'totalCravings': gNewTotal,
        'totalOvercome': gNewOvercome,
        'lastUpdate': DateTime.now().toIso8601String(),
      });
      
      print('Global summary updated: total=$gNewTotal, overcome=$gNewOvercome');
    } catch (e) {
      print('Error updating global summary: $e');
    }
  }

  // Получить дневник за день
  Future<SmokingDiary?> getDailyDiary(User user, DateTime date) async {
    try {
      final quitUser = user.quitStat;
      if (quitUser == null) return null;

      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      // Сначала пытаемся загрузить из локального хранилища
      final localDiary = await OfflineStorageService.getDiaryLocally(user.userId, date);
      if (localDiary != null) {
        // Если есть локальная версия, возвращаем её
        // Но также пытаемся обновить из Firebase в фоне (если есть интернет)
        final isOnline = await OfflineStorageService.isOnline();
        if (isOnline) {
          try {
            final snapshot = await database
                .child('diaries')
                .child(quitUser.quitId)
                .child(dateStr)
                .get()
                .timeout(const Duration(seconds: 5));

            if (snapshot.exists) {
              final data = Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>);
              final firebaseDiary = SmokingDiary.fromJson(data, user.userId);
              // Сохраняем обновленную версию локально
              await OfflineStorageService.saveDiaryLocally(firebaseDiary);
              return firebaseDiary;
            }
          } catch (e) {
            print('Error loading diary from Firebase (using local): $e');
            // Возвращаем локальную версию
            return localDiary;
          }
        }
        return localDiary;
      }

      // Если локальной версии нет, пытаемся загрузить из Firebase
      final isOnline = await OfflineStorageService.isOnline();
      if (!isOnline) {
        // Нет интернета и нет локальной версии - возвращаем null
        return null;
      }

      try {
        final snapshot = await database
            .child('diaries')
            .child(quitUser.quitId)
            .child(dateStr)
            .get()
            .timeout(const Duration(seconds: 5));

        if (!snapshot.exists) return null;

        final data = Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>);
        final diary = SmokingDiary.fromJson(data, user.userId);
        // Сохраняем в локальное хранилище
        await OfflineStorageService.saveDiaryLocally(diary);
        return diary;
      } catch (e) {
        print('Error getting daily diary from Firebase: $e');
        return null;
      }
    } catch (e) {
      print('Error getting daily diary: $e');
      return null;
    }
  }

  // Сохранить дневник
  Future<void> saveDiary(User user, SmokingDiary diary) async {
    try {
      final quitUser = user.quitStat;
      if (quitUser == null) throw Exception('Пользователь не начал отказ от курения');

      final dateStr = '${diary.date.year}-${diary.date.month.toString().padLeft(2, '0')}-${diary.date.day.toString().padLeft(2, '0')}';
      
      // Всегда сохраняем локально
      await OfflineStorageService.saveDiaryLocally(diary);

      final isOnline = await OfflineStorageService.isOnline();

      if (isOnline) {
        try {
          await database
              .child('diaries')
              .child(quitUser.quitId)
              .child(dateStr)
              .set(diary.toJson());

          print('Diary saved for date: $dateStr');
        } catch (e) {
          print('Error saving diary to Firebase, saved locally: $e');
          // Добавляем в очередь синхронизации
          await OfflineStorageService.addToSyncQueue('saveDiary', {
            'quitId': quitUser.quitId,
            'dateStr': dateStr,
            'diary': diary.toJson(),
          });
        }
      } else {
        // Офлайн режим - добавляем в очередь синхронизации
        await OfflineStorageService.addToSyncQueue('saveDiary', {
          'quitId': quitUser.quitId,
          'dateStr': dateStr,
          'diary': diary.toJson(),
        });
        print('Offline: diary saved locally, will sync when online');
      }
    } catch (e) {
      print('Error saving diary: $e');
      rethrow;
    }
  }

  // Получить все желания за период
  Future<List<CravingRecord>> getCravingsByPeriod(User user, DateTime from, DateTime to) async {
    try {
      final quitUser = user.quitStat;
      if (quitUser == null) return [];

      final snapshot = await database
          .child('cravings')
          .child(quitUser.quitId)
          .get();

      if (!snapshot.exists) return [];

      final cravings = <CravingRecord>[];
      final data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        final record = CravingRecord.fromJson(Map<String, dynamic>.from(value));
        if (record.timestamp.isAfter(from) && record.timestamp.isBefore(to)) {
          cravings.add(record);
        }
      });

      return cravings;
    } catch (e) {
      print('Error getting cravings by period: $e');
      return [];
    }
  }

  // Получить статистику по триггерам
  Future<Map<String, int>> getTriggerStatistics(User user) async {
    try {
      final quitUser = user.quitStat;
      if (quitUser == null) return {};

      final snapshot = await database
          .child('cravings')
          .child(quitUser.quitId)
          .get();

      if (!snapshot.exists) return {};

      final triggerStats = <String, int>{};
      final data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        final record = CravingRecord.fromJson(Map<String, dynamic>.from(value));
        triggerStats[record.trigger] = (triggerStats[record.trigger] ?? 0) + 1;
      });

      return triggerStats;
    } catch (e) {
      print('Error getting trigger statistics: $e');
      return {};
    }
  }
}