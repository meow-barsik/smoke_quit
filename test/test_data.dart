/// Тестовые данные для использования в тестах
/// 
/// Этот файл содержит готовые тестовые данные для различных сценариев тестирования

import 'package:smoke_quit/dataModels.dart';

class TestData {
  /// Создает тестового пользователя
  static User createTestUser({
    String userId = 'test_user_123',
    String email = 'test@example.com',
    String password = 'password123',
    bool isAlternative = false,
    bool isOnboarded = true,
  }) {
    return User(userId, email, password, isAlternative, isOnboarded);
  }

  /// Создает активную попытку отказа от курения
  static QuitUser createActiveQuit({
    required User user,
    String quitId = 'quit_active_1',
    int daysAgo = 5,
    int moneySaved = 0,
  }) {
    return QuitUser(
      quitId,
      DateTime.now().subtract(Duration(days: daysAgo)),
      moneySaved,
      true, // isQuiting
      [],
      daysAgo,
      user,
      status: 'active',
    );
  }

  /// Создает завершенную (неудачную) попытку отказа от курения
  static QuitUser createFailedQuit({
    required User user,
    String quitId = 'quit_failed_1',
    int daysAgo = 10,
    int daysLasted = 5,
    bool failedDueToCraving = true,
  }) {
    final startDate = DateTime.now().subtract(Duration(days: daysAgo));
    final endDate = startDate.add(Duration(days: daysLasted));
    
    return QuitUser(
      quitId,
      startDate,
      0,
      false, // isQuiting
      [],
      daysLasted,
      user,
      status: 'failed',
      quitEnd: endDate,
      failedDueToCraving: failedDueToCraving,
    );
  }

  /// Создает успешно завершенную попытку
  static QuitUser createCompletedQuit({
    required User user,
    String quitId = 'quit_completed_1',
    int daysAgo = 20,
    int daysLasted = 15,
  }) {
    final startDate = DateTime.now().subtract(Duration(days: daysAgo));
    final endDate = startDate.add(Duration(days: daysLasted));
    
    return QuitUser(
      quitId,
      startDate,
      0,
      false, // isQuiting
      [],
      daysLasted,
      user,
      status: 'completed',
      quitEnd: endDate,
    );
  }

  /// Создает запись о неудачной тяге
  static CravingRecord createFailedCraving({
    String id = 'craving_failed_1',
    String trigger = 'Стресс',
    int motivationLevel = 8,
    String? notes,
  }) {
    return CravingRecord(
      id: id,
      timestamp: DateTime.now(),
      trigger: trigger,
      motivationLevel: motivationLevel,
      overcome: false, // Не справился
      notes: notes ?? 'Очень сильная тяга, не смог удержаться',
    );
  }

  /// Создает запись об успешной тяге
  static CravingRecord createSuccessfulCraving({
    String id = 'craving_success_1',
    String trigger = 'Кофе',
    int motivationLevel = 5,
    String? notes,
  }) {
    return CravingRecord(
      id: id,
      timestamp: DateTime.now(),
      trigger: trigger,
      motivationLevel: motivationLevel,
      overcome: true, // Справился
      notes: notes ?? 'Удалось преодолеть желание',
    );
  }

  /// Создает список смешанных попыток (активные и завершенные)
  static List<QuitUser> createMixedQuits({
    required User user,
    int activeQuits = 1,
    int failedQuits = 2,
    int completedQuits = 1,
  }) {
    final quits = <QuitUser>[];
    
    // Добавляем завершенные попытки (старые)
    for (int i = 0; i < failedQuits; i++) {
      quits.add(createFailedQuit(
        user: user,
        quitId: 'quit_failed_$i',
        daysAgo: 30 + (i * 10),
        daysLasted: 5 + i,
      ));
    }
    
    // Добавляем активные попытки
    for (int i = 0; i < activeQuits; i++) {
      quits.add(createActiveQuit(
        user: user,
        quitId: 'quit_active_$i',
        daysAgo: 5 + i,
      ));
    }
    
    // Добавляем успешно завершенные попытки
    for (int i = 0; i < completedQuits; i++) {
      quits.add(createCompletedQuit(
        user: user,
        quitId: 'quit_completed_$i',
        daysAgo: 60 + (i * 10),
        daysLasted: 30 + i,
      ));
    }
    
    return quits;
  }

  /// Создает статистику пользователя
  static UserStats createUserStats({
    int? smokingYears = 5,
    int smokingMonth = 6,
    int attempts = 1,
    DateTime? lastAttemptDate,
    bool isAlternative = false,
  }) {
    final stats = isAlternative
        ? VapeStats(
            puffPower: 50,
            bottlePrice: 500,
            daysOnBottle: 7,
            puffPerDay: 200,
          )
        : CigStats(
            cigType: 'thin',
            cigPerDay: 20,
            packPrice: 200,
            cigsPerPack: 20,
          );

    return UserStats(
      smokingYears: smokingYears,
      smokingMonth: smokingMonth,
      attempts: attempts,
      lastAttemptDate: lastAttemptDate ?? DateTime.now().subtract(const Duration(days: 10)),
      stats: stats,
    );
  }
}

/// Ожидаемые результаты для тестов
/// 
/// Этот класс содержит вспомогательные методы для проверки ожидаемых результатов.
/// Используйте эти методы в тестах для более читаемого кода.
/// 
/// Пример использования:
/// ```dart
/// ExpectedResults.expectActiveQuit(activeQuit, expectedQuitId: 'quit1');
/// ```
class ExpectedResults {
  /// Проверяет, что попытка является активной
  /// 
  /// [quit] - попытка для проверки
  /// [expectedQuitId] - ожидаемый ID попытки (опционально)
  static void expectActiveQuit(QuitUser? quit, {String? expectedQuitId}) {
    // Этот метод должен использоваться внутри тестов с expect
    // Здесь мы просто документируем ожидаемые значения
    if (quit == null) {
      throw AssertionError('Активная попытка должна быть найдена');
    }
    assert(quit.isQuiting == true, 'isQuiting должен быть true');
    assert(quit.status == 'active', 'status должен быть "active"');
    if (expectedQuitId != null) {
      assert(quit.quitId == expectedQuitId, 'quitId должен совпадать');
    }
  }

  /// Проверяет, что активной попытки нет
  static void expectNoActiveQuit(QuitUser? quit) {
    assert(quit == null, 'Активной попытки не должно быть');
  }

  /// Проверяет, что попытка завершена как неудачная
  static void expectFailedQuit(QuitUser quit, {bool failedDueToCraving = true}) {
    assert(quit.isQuiting == false, 'isQuiting должен быть false');
    assert(quit.status == 'failed', 'status должен быть "failed"');
    assert(quit.quitEnd != null, 'quitEnd должен быть установлен');
    if (failedDueToCraving) {
      assert(quit.failedDueToCraving == true, 'failedDueToCraving должен быть true');
    }
  }

  /// Проверяет, что запись о тяге указывает на неудачу
  static void expectFailedCraving(CravingRecord craving) {
    assert(craving.overcome == false, 'overcome должен быть false');
  }

  /// Проверяет, что запись о тяге указывает на успех
  static void expectSuccessfulCraving(CravingRecord craving) {
    assert(craving.overcome == true, 'overcome должен быть true');
  }
}

