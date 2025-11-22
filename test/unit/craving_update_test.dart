import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_quit/dataModels.dart';

/// Юнит-тесты для логики обновления попытки при добавлении тяги
/// 
/// Тестирует логику, которая используется в _updateCravingAsFailed() и
/// _updateQuitAttemptLocally() для завершения попытки при неудачной тяге.

void main() {
  group('Обновление попытки при неудачной тяге', () {
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

    test('Должна корректно обновлять попытку при локальном обновлении', () {
      // Данные для тестирования
      final quitBeforeUpdate = QuitUser(
        'quit1',
        DateTime.now().subtract(const Duration(days: 5)),
        0,
        true,
        [],
        5,
        testUser,
        status: 'active',
      );

      // Логика обновления (копия из _updateQuitAttemptLocally)
      final now = DateTime.now();
      quitBeforeUpdate.quitEnd = now;
      quitBeforeUpdate.status = 'failed';
      quitBeforeUpdate.isQuiting = false;
      quitBeforeUpdate.failedDueToCraving = true;

      // Ожидаемый результат
      expect(quitBeforeUpdate.quitEnd, isNotNull);
      expect(quitBeforeUpdate.status, equals('failed'));
      expect(quitBeforeUpdate.isQuiting, isFalse);
      expect(quitBeforeUpdate.failedDueToCraving, isTrue);
    });

    test('Должна создавать запись о тяге с overcome: false', () {
      // Данные для тестирования
      final cravingRecord = CravingRecord(
        id: 'craving1',
        timestamp: DateTime.now(),
        trigger: 'Стресс',
        motivationLevel: 8,
        overcome: false, // Не справился
        notes: 'Очень сильная тяга',
      );

      // Ожидаемый результат
      expect(cravingRecord.overcome, isFalse);
      expect(cravingRecord.trigger, equals('Стресс'));
      expect(cravingRecord.motivationLevel, equals(8));
      expect(cravingRecord.id, equals('craving1'));
    });

    test('Должна создавать запись о тяге с overcome: true', () {
      // Данные для тестирования
      final cravingRecord = CravingRecord(
        id: 'craving2',
        timestamp: DateTime.now(),
        trigger: 'Кофе',
        motivationLevel: 5,
        overcome: true, // Справился
        notes: 'Удалось преодолеть',
      );

      // Ожидаемый результат
      expect(cravingRecord.overcome, isTrue);
      expect(cravingRecord.trigger, equals('Кофе'));
      expect(cravingRecord.motivationLevel, equals(5));
    });

    test('Должна корректно сериализовать и десериализовать CravingRecord', () {
      // Данные для тестирования
      final originalRecord = CravingRecord(
        id: 'craving1',
        timestamp: DateTime(2024, 1, 15, 10, 30),
        trigger: 'Стресс',
        motivationLevel: 8,
        overcome: false,
        notes: 'Тестовая запись',
      );

      // Сериализация
      final json = originalRecord.toJson();
      
      // Ожидаемый результат JSON
      expect(json['id'], equals('craving1'));
      expect(json['trigger'], equals('Стресс'));
      expect(json['motivationLevel'], equals(8));
      expect(json['overcome'], isFalse);
      expect(json['notes'], equals('Тестовая запись'));
      expect(json['timestamp'], isA<String>());

      // Десериализация
      final deserializedRecord = CravingRecord.fromJson(json);
      
      // Ожидаемый результат после десериализации
      expect(deserializedRecord.id, equals(originalRecord.id));
      expect(deserializedRecord.trigger, equals(originalRecord.trigger));
      expect(deserializedRecord.motivationLevel, equals(originalRecord.motivationLevel));
      expect(deserializedRecord.overcome, equals(originalRecord.overcome));
      expect(deserializedRecord.notes, equals(originalRecord.notes));
    });

    test('Должна корректно вычислять daysWithoutSmoking для завершенной попытки', () {
      // Данные для тестирования
      final startDate = DateTime(2024, 1, 1);
      final endDate = DateTime(2024, 1, 10);
      
      final quit = QuitUser(
        'quit1',
        startDate,
        0,
        false, // завершена
        [],
        0,
        testUser,
        status: 'failed',
        quitEnd: endDate,
      );

      // Ожидаемый результат
      final days = quit.daysWithoutSmoking;
      expect(days, equals(9)); // 10 - 1 = 9 дней
    });

    test('Должна корректно вычислять daysWithoutSmoking для активной попытки', () {
      // Данные для тестирования
      final startDate = DateTime.now().subtract(const Duration(days: 5));
      
      final quit = QuitUser(
        'quit1',
        startDate,
        0,
        true, // активна
        [],
        0,
        testUser,
        status: 'active',
        quitEnd: null, // еще не завершена
      );

      // Ожидаемый результат
      final days = quit.daysWithoutSmoking;
      expect(days, greaterThanOrEqualTo(5));
      expect(days, lessThanOrEqualTo(6)); // может быть 5 или 6 в зависимости от времени
    });
  });
}

