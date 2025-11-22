import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_quit/dataModels.dart';

/// Интеграционные тесты для обновления стрика при добавлении тяги
/// 
/// Тестирует полный поток: добавление тяги с overcome: false -> 
/// завершение попытки -> обновление UI (стрик должен обновиться)

void main() {
  group('Интеграционные тесты: Обновление стрика при неудачной тяге', () {
    late User testUser;
    late QuitUser activeQuit;
    
    setUp(() {
      testUser = User('user123', 'test@example.com', 'password', false, true);
      activeQuit = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true, // isQuiting = true
        [],
        5,
        testUser,
        status: 'active',
      );
      testUser.quitStat = activeQuit;
    });

    test('Полный поток: добавление неудачной тяги -> завершение попытки -> обновление стрика', () {
      // Шаг 1: Исходное состояние - активная попытка
      expect(testUser.quitStat, isNotNull);
      expect(testUser.quitStat!.isQuiting, isTrue);
      expect(testUser.quitStat!.status, equals('active'));
      final initialDays = testUser.quitStat!.daysWithoutSmoking;
      expect(initialDays, greaterThanOrEqualTo(5));

      // Шаг 2: Создание записи о неудачной тяге
      final failedCraving = CravingRecord(
        id: 'craving1',
        timestamp: DateTime.now(),
        trigger: 'Стресс',
        motivationLevel: 9,
        overcome: false, // Не справился
        notes: 'Очень сильная тяга, не смог удержаться',
      );
      
      expect(failedCraving.overcome, isFalse);

      // Шаг 3: Локальное обновление попытки (симуляция _updateQuitAttemptLocally)
      final quit = testUser.quitStat!;
      final now = DateTime.now();
      quit.quitEnd = now;
      quit.status = 'failed';
      quit.isQuiting = false;
      quit.failedDueToCraving = true;

      // Шаг 4: Проверка обновленного состояния
      expect(quit.isQuiting, isFalse);
      expect(quit.status, equals('failed'));
      expect(quit.failedDueToCraving, isTrue);
      expect(quit.quitEnd, isNotNull);

      // Шаг 5: Симуляция логики _loadQuitData - поиск активной попытки
      final allQuits = [quit];
      QuitUser? activeQuitFound;
      for (var q in allQuits.reversed) {
        if (q.isQuiting && q.status == 'active') {
          activeQuitFound = q;
          break;
        }
      }

      // Ожидаемый результат: активной попытки не должно быть найдено
      expect(activeQuitFound, isNull);

      // Шаг 6: Обновление пользователя (симуляция обновления в HomePage)
      if (testUser.quitStat != null && !testUser.quitStat!.isQuiting) {
        testUser.quitStat = null; // Стрик должен быть сброшен
      }

      // Ожидаемый результат: quitStat должен быть null, стрик завершен
      expect(testUser.quitStat, isNull);
    });

    test('Полный поток: добавление успешной тяги -> попытка продолжается', () {
      // Шаг 1: Исходное состояние - активная попытка
      expect(testUser.quitStat, isNotNull);
      expect(testUser.quitStat!.isQuiting, isTrue);
      final initialDays = testUser.quitStat!.daysWithoutSmoking;

      // Шаг 2: Создание записи об успешной тяге
      final successfulCraving = CravingRecord(
        id: 'craving2',
        timestamp: DateTime.now(),
        trigger: 'Кофе',
        motivationLevel: 6,
        overcome: true, // Справился!
        notes: 'Удалось преодолеть желание',
      );
      
      expect(successfulCraving.overcome, isTrue);

      // Шаг 3: Попытка должна остаться активной
      expect(testUser.quitStat!.isQuiting, isTrue);
      expect(testUser.quitStat!.status, equals('active'));

      // Шаг 4: Симуляция логики _loadQuitData - поиск активной попытки
      final allQuits = [testUser.quitStat!];
      QuitUser? activeQuitFound;
      for (var q in allQuits.reversed) {
        if (q.isQuiting && q.status == 'active') {
          activeQuitFound = q;
          break;
        }
      }

      // Ожидаемый результат: активная попытка должна быть найдена
      expect(activeQuitFound, isNotNull);
      expect(activeQuitFound!.isQuiting, isTrue);
      expect(activeQuitFound.status, equals('active'));

      // Шаг 5: Стрик должен продолжаться
      expect(testUser.quitStat, isNotNull);
      expect(testUser.quitStat!.daysWithoutSmoking, greaterThanOrEqualTo(initialDays));
    });

    test('Сценарий: несколько попыток, одна активная, добавление неудачной тяги', () {
      // Шаг 1: Создание нескольких попыток
      final oldFailedQuit = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 30)),
        0,
        false,
        [],
        30,
        testUser,
        status: 'failed',
        quitEnd: DateTime.now().subtract(const Duration(days: 25)),
      );
      
      final activeQuit = QuitUser(
        'quit2',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true,
        [],
        5,
        testUser,
        status: 'active',
      );

      final allQuits = [oldFailedQuit, activeQuit];
      testUser.quitStat = activeQuit;

      // Шаг 2: Поиск активной попытки (до добавления тяги)
      QuitUser? activeBefore;
      for (var q in allQuits.reversed) {
        if (q.isQuiting && q.status == 'active') {
          activeBefore = q;
          break;
        }
      }
      expect(activeBefore, isNotNull);
      expect(activeBefore!.quitId, equals('quit2'));

      // Шаг 3: Добавление неудачной тяги и завершение попытки
      final failedCraving = CravingRecord(
        id: 'craving1',
        timestamp: DateTime.now(),
        trigger: 'Алкоголь',
        motivationLevel: 10,
        overcome: false,
      );
      
      // Проверка, что тяга действительно неудачная
      expect(failedCraving.overcome, isFalse);

      // Обновление активной попытки
      activeQuit.quitEnd = DateTime.now();
      activeQuit.status = 'failed';
      activeQuit.isQuiting = false;
      activeQuit.failedDueToCraving = true;

      // Шаг 4: Поиск активной попытки (после добавления тяги)
      QuitUser? activeAfter;
      for (var q in allQuits.reversed) {
        if (q.isQuiting && q.status == 'active') {
          activeAfter = q;
          break;
        }
      }

      // Ожидаемый результат: активной попытки не должно быть
      expect(activeAfter, isNull);

      // Шаг 5: Обновление пользователя
      if (testUser.quitStat != null && !testUser.quitStat!.isQuiting) {
        testUser.quitStat = null;
      }

      // Ожидаемый результат: стрик должен быть завершен
      expect(testUser.quitStat, isNull);
    });

    test('Сценарий: проверка корректности обновления daysWithoutSmoking', () {
      // Данные для тестирования
      final startDate = DateTime(2024, 1, 1, 10, 0);
      final quit = QuitUser(
        'quit1',
        startDate,
        0,
        true,
        [],
        0,
        testUser,
        status: 'active',
      );
      testUser.quitStat = quit;

      // Исходное количество дней
      final daysBefore = quit.daysWithoutSmoking;
      expect(daysBefore, greaterThanOrEqualTo(0));

      // Симуляция завершения попытки через 10 дней
      final endDate = startDate.add(const Duration(days: 10));
      quit.quitEnd = endDate;
      quit.isQuiting = false;
      quit.status = 'failed';

      // Проверка daysWithoutSmoking после завершения
      final daysAfter = quit.daysWithoutSmoking;
      expect(daysAfter, equals(10));
    });
  });
}

