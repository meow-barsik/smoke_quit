import 'package:firebase_database/firebase_database.dart';
import 'offline_storage.dart';
import 'dataModels.dart';

class SyncService {
  static Future<void> syncAllData(User? user) async {
    if (user == null) return;
    
    final isOnline = await OfflineStorageService.isOnline();
    if (!isOnline) {
      print('No internet connection, skipping sync');
      return;
    }

    try {
      // Синхронизация очереди операций
      await _syncQueue(user);
      
      // Синхронизация данных пользователя
      await _syncUserData(user);
      
      // Синхронизация записей о тяге
      await _syncCravings(user);
      
      print('Sync completed successfully');
    } catch (e) {
      print('Error during sync: $e');
    }
  }

  static Future<void> _syncQueue(User user) async {
    final queue = await OfflineStorageService.getSyncQueue();
    final database = FirebaseDatabase.instance.refFromURL(
      'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
    );

    for (var item in queue) {
      try {
        final operation = item['operation'] as String;
        final data = Map<String, dynamic>.from(item['data'] as Map);

        switch (operation) {
          case 'saveCraving':
            await database
                .child('allUserCravings')
                .child(user.userId)
                .child(data['id'] as String)
                .set(data);
            break;
          case 'saveDiary':
            await database
                .child('diaries')
                .child(data['quitId'] as String)
                .child(data['dateStr'] as String)
                .set(data['diary']);
            break;
          case 'updateStats':
            await database
                .child('stats')
                .child(user.userId)
                .update(data);
            break;
          case 'endQuitAttempt':
            await database
                .child('quitStats')
                .child(data['quitId'] as String)
                .update({
              'quitEnd': DateTime.now().toIso8601String(),
              'status': data['status'] as String,
              'isQuiting': false,
              'failedDueToCraving': data['failedDueToCraving'] as bool? ?? false,
            });
            break;
          case 'startQuit':
            // Создаем новую попытку в Firebase
            final quitId = database.child('quitStats').push().key;
            if (quitId != null) {
              // Обновляем quitId в данных
              final updatedData = Map<String, dynamic>.from(data);
              updatedData['quitId'] = quitId;
              await database.child('quitStats').child(quitId).set(updatedData);
              await database.child('quitIndex').child(quitId).set(user.userId);
              // Обновляем статистику пользователя
              try {
                final userSummaryRef = database.child('userSummary').child(user.userId);
                final userSnap = await userSummaryRef.get();
                int totalAttempts = 1;
                if (userSnap.exists) {
                  final map = userSnap.value as Map<dynamic, dynamic>;
                  totalAttempts = (map['totalAttempts'] as num? ?? 0).toInt() + 1;
                }
                await userSummaryRef.update({'totalAttempts': totalAttempts});
              } catch (e) {
                print('Error updating user summary: $e');
              }
            }
            break;
          case 'updateProfile':
            await database.child('users').child(data['userId'] as String).update({
              'isAlternative': data['isAlternative'] as bool,
            });
            await database.child('stats').child(data['userId'] as String).update(
              Map<String, dynamic>.from(data['stats'] as Map),
            );
            break;
          case 'updateQuitStats':
            await database
                .child('quitStats')
                .child(data['quitId'] as String)
                .update({
              'daysOut': data['daysOut'],
              'moneySaved': data['moneySaved'],
              'lastUpdate': data['lastUpdate'],
            });
            break;
        }

        // Удаляем успешно синхронизированную операцию
        await OfflineStorageService.removeFromSyncQueue(item['id'] as String);
      } catch (e) {
        print('Error syncing queue item ${item['id']}: $e');
        // Оставляем в очереди для повторной попытки
      }
    }
  }

  static Future<void> _syncUserData(User user) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );

      // Загружаем данные пользователя из Firebase
      final userSnapshot = await database.child('users').child(user.userId).get();
      if (userSnapshot.exists) {
        final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
        final updatedUser = User.fromMap(user.userId, userData);
        
        // Сохраняем локально
        await OfflineStorageService.saveUserLocally(updatedUser);
      }

      // Загружаем статистику пользователя
      final statsSnapshot = await database.child('stats').child(user.userId).get();
      if (statsSnapshot.exists) {
        final statsData = Map<String, dynamic>.from(statsSnapshot.value as Map);
        final stats = UserStats.fromJson(statsData, user);
        user.stats = stats;
        await OfflineStorageService.saveUserStatsLocally(user.userId, stats);
      }
    } catch (e) {
      print('Error syncing user data: $e');
    }
  }

  static Future<void> _syncCravings(User user) async {
    try {
      final database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com/',
      );

      // Загружаем все записи о тяге из Firebase
      final snapshot = await database
          .child('allUserCravings')
          .child(user.userId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        for (var entry in data.entries) {
          try {
            final cravingData = Map<String, dynamic>.from(entry.value as Map);
            final craving = CravingRecord.fromJson(cravingData);
            await OfflineStorageService.saveCravingLocally(craving);
          } catch (e) {
            print('Error parsing craving ${entry.key}: $e');
          }
        }
      }
    } catch (e) {
      print('Error syncing cravings: $e');
    }
  }

  // Попытка синхронизации при появлении интернета
  static Future<void> trySyncWhenOnline(User? user) async {
    final isOnline = await OfflineStorageService.isOnline();
    if (isOnline && user != null) {
      await syncAllData(user);
    }
  }
}

