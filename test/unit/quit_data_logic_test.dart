import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_quit/dataModels.dart';

/// Юнит-тесты для логики поиска активной попытки отказа от курения
/// 
/// Тестирует логику, которая используется в _loadQuitData() для определения
/// активной попытки из списка всех попыток пользователя.

void main() {
  group('Логика поиска активной попытки', () {
    late User testUser;
    
    setUp(() {
      testUser = User('user123', 'test@example.com', 'password', false, true);
    });

    test('Должна найти активную попытку, когда она единственная', () {
      // Данные для тестирования
      final activeQuit = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true, // isQuiting
        [],
        5,
        testUser,
        status: 'active',
      );

      final allQuits = [activeQuit];
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат
      expect(activeQuitFound, isNotNull);
      expect(activeQuitFound!.quitId, equals('quit1'));
      expect(activeQuitFound.isQuiting, isTrue);
      expect(activeQuitFound.status, equals('active'));
    });

    test('Должна найти последнюю активную попытку из нескольких активных', () {
      // Данные для тестирования: несколько активных попыток
      final quit1 = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 10)),
        0,
        true,
        [],
        10,
        testUser,
        status: 'active',
      );
      
      final quit2 = QuitUser(
        'quit2',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true,
        [],
        5,
        testUser,
        status: 'active',
      );

      final allQuits = [quit1, quit2]; // quit2 - последняя
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат: должна найти quit2 (последняя активная)
      expect(activeQuitFound, isNotNull);
      expect(activeQuitFound!.quitId, equals('quit2'));
    });

    test('Не должна находить активную попытку, если все завершены', () {
      // Данные для тестирования: все попытки завершены
      final failedQuit = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 10)),
        0,
        false, // isQuiting = false
        [],
        10,
        testUser,
        status: 'failed',
        quitEnd: DateTime.now().subtract(const Duration(days: 5)),
        failedDueToCraving: true,
      );
      
      final completedQuit = QuitUser(
        'quit2',
        DateTime.now().subtract(const Duration(days: 20)),
        0,
        false, // isQuiting = false
        [],
        20,
        testUser,
        status: 'completed',
        quitEnd: DateTime.now().subtract(const Duration(days: 10)),
      );

      final allQuits = [failedQuit, completedQuit];
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат: activeQuit должен быть null
      expect(activeQuitFound, isNull);
    });

    test('Должна найти активную попытку среди смешанных (активные и завершенные)', () {
      // Данные для тестирования: смешанные попытки
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
        true, // isQuiting = true
        [],
        5,
        testUser,
        status: 'active',
      );
      
      final oldCompletedQuit = QuitUser(
        'quit3',
        DateTime.now().subtract(const Duration(days: 60)),
        0,
        false,
        [],
        60,
        testUser,
        status: 'completed',
        quitEnd: DateTime.now().subtract(const Duration(days: 50)),
      );

      final allQuits = [oldFailedQuit, activeQuit, oldCompletedQuit];
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат: должна найти quit2 (единственная активная)
      expect(activeQuitFound, isNotNull);
      expect(activeQuitFound!.quitId, equals('quit2'));
      expect(activeQuitFound.isQuiting, isTrue);
    });

    test('Должна корректно обрабатывать пустой список попыток', () {
      // Данные для тестирования
      final allQuits = <QuitUser>[];
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат: activeQuit должен быть null
      expect(activeQuitFound, isNull);
    });

    test('Не должна находить попытку со status != "active" даже если isQuiting = true', () {
      // Данные для тестирования: попытка с isQuiting=true, но status != 'active'
      final quitWithWrongStatus = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true, // isQuiting = true
        [],
        5,
        testUser,
        status: 'failed', // но status != 'active'
      );

      final allQuits = [quitWithWrongStatus];
      
      // Логика поиска (копия из _loadQuitData)
      QuitUser? activeQuitFound;
      for (var quit in allQuits.reversed) {
        if (quit.isQuiting && quit.status == 'active') {
          activeQuitFound = quit;
          break;
        }
      }

      // Ожидаемый результат: activeQuit должен быть null
      expect(activeQuitFound, isNull);
    });
  });
}

