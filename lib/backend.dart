import 'dart:core';
import 'package:firebase_database/firebase_database.dart';
import 'dataModels.dart';

class RegService {
  final DatabaseReference databaseReference;
  final User user;

  RegService._({required this.user, required this.databaseReference});

  static Future<RegService> createRegService(
    String email,
    String password,
  ) async {
    final DatabaseReference database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com',
    );
    final DatabaseReference ref = database.child('users').push();
    final String? id = ref.key;

    if (id == null) {
      throw Exception('Failed to create user ID');
    }

    final User user = User(id, email, password, false, false);
    await _addUserData(database, user, id, email);

    return RegService._(user: user, databaseReference: database);
  }

  static Future<void> _addUserData(
    DatabaseReference ref,
    User user,
    String key,
    String mail,
  ) async {
    try {
      await ref.child('users').child(key).set(user.getMap());
      await ref.child('usersIndex').child(key).set(mail);
      print('User registered successfully: $mail');
    } catch (e) {
      print('Error registering user: $e');
      rethrow;
    }
  }
}

class AuthService {
  final User? _user;

  AuthService._(this._user);

  static Future<AuthService> createAuthService(String email) async {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );
    final User? user = await _searchUser(database, email);
    return AuthService._(user);
  }

  static Future<User?> searchUser(
    DatabaseReference database,
    String mail,
  ) async {
    return await _searchUser(database, mail);
  }

  static Future<User?> _searchUser(
    DatabaseReference database,
    String mail,
  ) async {
    try {
      final DataSnapshot snapshot = await database.child('usersIndex').get();

      if (!snapshot.exists) {
        return null;
      }

      final Map<dynamic, dynamic> data =
          snapshot.value as Map<dynamic, dynamic>;

      for (dynamic key in data.keys) {
        if (mail == data[key]) {
          print('User found: ${data[key]}');
          final userData = await _getUserData(key.toString(), database);
          return userData;
        }
      }
      return null;
    } catch (e) {
      print('Error searching user: $e');
      return null;
    }
  }

  static Future<User> _getUserData(
    String key,
    DatabaseReference database,
  ) async {
    try {
      final DataSnapshot snapshot = await database
          .child('users')
          .child(key)
          .get();

      if (!snapshot.exists) {
        throw Exception('User data not found');
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      return User.fromMap(key, data);
    } catch (e) {
      print('Error getting user data: $e');
      rethrow;
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
      final quitUser = await StartQuit.getCurrentQuitStats(user);
      user.quitStat = quitUser;
    } catch (e) {
      print('Error loading quit stats: $e');
    }
  }
}

class StartQuit {
  final User user;
  final QuitUser userQuit;

  StartQuit(this.user, this.userQuit);

  static Future<QuitUser?> searchUserQuit(
    DatabaseReference database,
    User user,
  ) async {
    try {
      final DataSnapshot userInfo = await database.child('quitIndex').get();

      if (!userInfo.exists) {
        return null;
      }

      final Map<dynamic, dynamic> usersMap =
          userInfo.value as Map<dynamic, dynamic>;

      for (var entry in usersMap.entries) {
        if (entry.value == user.userId) {
          final DataSnapshot foundedUser = await database
              .child('quitStats')
              .child(entry.key.toString())
              .get();

          if (foundedUser.exists) {
            final Map<String, dynamic> userData = Map<String, dynamic>.from(
              foundedUser.value as Map<dynamic, dynamic>,
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

  static Future<QuitUser> createUserQuit(
    DatabaseReference database,
    User user,
  ) async {
    String? key = database.child('quitStats').push().key;
    QuitUser quitStats = QuitUser.newUser(user, key!);

    await database.child('quitStats').child(key).set(quitStats.getMap());
    await database.child('quitIndex').child(key).set(user.userId);

    return quitStats;
  }

  static Future<StartQuit> startQuit(User user) async {
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );

    QuitUser? quitStats = await searchUserQuit(database, user);
    if (quitStats != null) {
      return StartQuit(user, quitStats);
    } else {
      quitStats = await createUserQuit(database, user);
      return StartQuit(user, quitStats);
    }
  }

  // Метод для получения актуальной статистики отказа
  static Future<QuitUser?> getCurrentQuitStats(User user) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );

      return await searchUserQuit(database, user);
    } catch (e) {
      print('Error getting quit stats: $e');
      return null;
    }
  }

  // Метод для обновления статистики отказа
  static Future<void> updateQuitStats(User user, QuitUser quitUser) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );

      await database.child('quitStats').child(quitUser.quitId).update({
        'daysOut': quitUser.daysWithoutSmoking,
        'moneySaved': quitUser.calculateMoneySaved(user.stats),
        'lastUpdate': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error updating quit stats: $e');
      rethrow;
    }
  }
}
