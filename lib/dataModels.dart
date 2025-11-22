import 'dart:core';

class User {
  final String _userId;
  final String _mail;
  final String _password;
  bool _isAlternative;
  bool _isOnboarded;
  UserStats? stats;
  QuitUser? _quitStat;
  Map<String, dynamic>? userSummary; // статистика пользователя

  User(
    this._userId,
    this._mail,
    this._password,
    this._isAlternative,
    this._isOnboarded,
  );

  Map<String, dynamic> getMap() {
    return {
      'userId': _userId,
      'mail': _mail,
      'password': _password,
      'isAlternative': _isAlternative,
      'isOnboarded': _isOnboarded,
    };
  }

  Map<String, dynamic> getIndex() {
    return {_userId: _mail};
  }

  static User createUserByList(List<dynamic> list) {
    return User(
      list[0] ?? '',
      list[1] ?? '',
      list[2] ?? '',
      (list[3] ?? false) as bool,
      (list[4] ?? false) as bool,
    );
  }

  static User fromMap(String userId, Map<dynamic, dynamic> data) {
    return User(
      userId,
      data['mail']?.toString() ?? '',
      data['password']?.toString() ?? '',
      (data['isAlternative'] ?? false) as bool,
      (data['isOnboarded'] ?? false) as bool,
    );
  }

  String get getPasswd => _password;
  String get userId => _userId;
  String get mail => _mail;
  bool get isAlternative => _isAlternative;
  bool get isOnboarded => _isOnboarded;
  set isAlternative(bool value) => _isAlternative = value;

  String get getId => _userId;
  bool get getOnboarded => _isOnboarded;

  QuitUser? get quitStat => _quitStat;
  set quitStat(QuitUser? value) => _quitStat = value;
  
  set isOnboarded(bool value) => _isOnboarded = value;
}

abstract class SmokingStats {
  double calculateMonthlyCost();
  Map<String, dynamic> toJson();
  String get type;
}

class VapeStats implements SmokingStats {
  final int puffPower;
  final int bottlePrice;
  final int daysOnBottle;
  final int puffPerDay;

  VapeStats({
    required this.puffPower,
    required this.bottlePrice,
    required this.daysOnBottle,
    required this.puffPerDay,
  }) : assert(bottlePrice > 0),
       assert(daysOnBottle > 0);

  factory VapeStats.fromJson(Map<String, dynamic> json) {
    return VapeStats(
      puffPower: (json['puffPower'] as num?)?.toInt() ?? 0,
      bottlePrice: (json['bottlePrice'] as num?)?.toInt() ?? 0,
      daysOnBottle: (json['daysOnBottle'] as num?)?.toInt() ?? 0,
      puffPerDay: (json['puffPerDay'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  double calculateMonthlyCost() {
    return (bottlePrice / daysOnBottle) * 30;
  }

  @override
  Map<String, dynamic> toJson() => {
    'puffPower': puffPower,
    'bottlePrice': bottlePrice,
    'daysOnBottle': daysOnBottle,
    'puffPerDay': puffPerDay,
    'type': 'vape',
  };

  @override
  String get type => 'vape';
}

class CigStats implements SmokingStats {
  final String cigType;
  final int cigPerDay;
  final int packPrice;
  final int cigsPerPack;

  CigStats({
    required this.cigType,
    required this.cigPerDay,
    required this.packPrice,
    this.cigsPerPack = 20,
  }) : assert(packPrice > 0),
       assert(cigPerDay >= 0);

  factory CigStats.fromJson(Map<String, dynamic> json) {
    return CigStats(
      cigType: json['cigType']?.toString() ?? 'thin',
      cigPerDay: (json['cigPerDay'] as num?)?.toInt() ?? 0,
      packPrice: (json['packPrice'] as num?)?.toInt() ?? 0,
      cigsPerPack: (json['cigsPerPack'] as num?)?.toInt() ?? 20,
    );
  }

  @override
  double calculateMonthlyCost() {
    final packsPerDay = cigPerDay / cigsPerPack;
    return (packPrice * packsPerDay) * 30;
  }

  @override
  Map<String, dynamic> toJson() => {
    'cigType': cigType,
    'cigPerDay': cigPerDay,
    'packPrice': packPrice,
    'cigsPerPack': cigsPerPack,
    'type': 'cigarette',
  };

  @override
  String get type => 'cigarette';
}

class UserStats {
  final int? smokingYears;
  final int smokingMonth;
  final int attempts;
  final DateTime lastAttemptDate;
  final SmokingStats stats;

  UserStats({
    this.smokingYears,
    required this.smokingMonth,
    required this.attempts,
    required this.lastAttemptDate,
    required this.stats,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      "smokingYears": smokingYears,
      "smokingMonth": smokingMonth,
      "attempts": attempts,
      'lastAttemptDate': lastAttemptDate.toIso8601String(),
    };
    data.addAll(stats.toJson());
    return data;
  }

  factory UserStats.fromJson(Map<String, dynamic> json, User user) {
    final SmokingStats smokingStats;

    if (user.isAlternative) {
      smokingStats = VapeStats.fromJson(json);
    } else {
      smokingStats = CigStats.fromJson(json);
    }

    DateTime lastAttemptDate;
    try {
      lastAttemptDate = DateTime.parse(
        json['lastAttemptDate']?.toString() ?? '',
      );
    } catch (e) {
      lastAttemptDate = DateTime.now();
    }

    return UserStats(
      smokingYears: (json['smokingYears'] as num?)?.toInt(),
      smokingMonth: (json['smokingMonth'] as num?)?.toInt() ?? 0,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastAttemptDate: lastAttemptDate,
      stats: smokingStats,
    );
  }

  double getMonthlySavings() {
    return stats.calculateMonthlyCost();
  }

  int getTotalSmokingMonths() {
    return (smokingYears ?? 0) * 12 + smokingMonth;
  }
}

// Общие триггеры для всех типов курения
List<String> _commonCravingsReasons = [
  'Алкоголь',
  'Компания',
  'Утренний ритуал',
  'Перерыв на работе',
  'Кофейный или чайный перерыв',
  'Стресс',
  'Перекур после еды',
];

// Триггеры специфичные для обычных сигарет
List<String> _cigaretteSpecificReasons = [
  'Запах табака',
  'Физическая привычка (держать в руках)',
];

// Триггеры специфичные для электронных сигарет
List<String> _vapeSpecificReasons = [
  'Скука/безделье',
  'Игра с устройством',
  'Желание попробовать новый вкус',
  'Никотиновый ритуал',
];

// Функция для получения списка триггеров в зависимости от типа курения
List<String> getCravingsReasons(User? user) {
  if (user == null) {
    return _commonCravingsReasons;
  }
  
  if (user.isAlternative) {
    // Для электронных сигарет: общие + специфичные для вейпа
    return [
      ..._commonCravingsReasons,
      ..._vapeSpecificReasons,
    ];
  } else {
    // Для обычных сигарет: общие + специфичные для сигарет
    return [
      ..._commonCravingsReasons,
      ..._cigaretteSpecificReasons,
    ];
  }
}

// Для обратной совместимости
List<String> get cravingsReason => _commonCravingsReasons;

// Модель для записи о желании курить
class CravingRecord {
  final String id;
  final DateTime timestamp;
  final String trigger;
  final int motivationLevel; // 1-10
  final bool overcome; // удалось ли преодолеть желание
  final String? notes;

  CravingRecord({
    required this.id,
    required this.timestamp,
    required this.trigger,
    required this.motivationLevel,
    required this.overcome,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'trigger': trigger,
    'motivationLevel': motivationLevel,
    'overcome': overcome,
    'notes': notes,
  };

  factory CravingRecord.fromJson(Map<String, dynamic> json) {
    return CravingRecord(
      id: json['id']?.toString() ?? '',
      timestamp: DateTime.parse(json['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
      trigger: json['trigger']?.toString() ?? 'Другое',
      motivationLevel: (json['motivationLevel'] as num?)?.toInt() ?? 5,
      overcome: (json['overcome'] ?? false) as bool,
      notes: json['notes']?.toString(),
    );
  }
}

// Модель для дневника курения
class SmokingDiary {
  final String id;
  final String userId;
  final DateTime date;
  int cigarettesSmoked; // количество выкуренных сигарет
  int creaturesResisted; // количество преодоленных желаний
  List<CravingRecord> cravings;
  String? mood; // настроение: хорошее, нормальное, плохое
  double? motivationScore; // оценка мотивации 1-10

  SmokingDiary({
    required this.id,
    required this.userId,
    required this.date,
    this.cigarettesSmoked = 0,
    this.creaturesResisted = 0,
    List<CravingRecord>? cravings,
    this.mood,
    this.motivationScore,
  }) : cravings = cravings ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'date': date.toIso8601String(),
    'cigarettesSmoked': cigarettesSmoked,
    'creaturesResisted': creaturesResisted,
    'cravings': cravings.map((c) => c.toJson()).toList(),
    'mood': mood,
    'motivationScore': motivationScore,
  };

  factory SmokingDiary.fromJson(Map<String, dynamic> json, String userId) {
    final cravingsList = <CravingRecord>[];
    if (json['cravings'] is List) {
      cravingsList.addAll(
        (json['cravings'] as List).map((c) => CravingRecord.fromJson(c as Map<String, dynamic>))
      );
    }

    return SmokingDiary(
      id: json['id']?.toString() ?? '',
      userId: userId,
      date: DateTime.parse(json['date']?.toString() ?? DateTime.now().toIso8601String()),
      cigarettesSmoked: (json['cigarettesSmoked'] as num?)?.toInt() ?? 0,
      creaturesResisted: (json['creaturesResisted'] as num?)?.toInt() ?? 0,
      cravings: cravingsList,
      mood: json['mood']?.toString(),
      motivationScore: (json['motivationScore'] as num?)?.toDouble(),
    );
  }

  // Добавить запись о желании курить
  void addCravingRecord(CravingRecord record) {
    cravings.add(record);
    if (record.overcome) {
      creaturesResisted++;
    }
  }

  // Получить статистику дня
  Map<String, dynamic> getDayStats() {
    final overcomeCount = cravings.where((c) => c.overcome).length;
    final totalCravings = cravings.length;
    
    return {
      'totalCravings': totalCravings,
      'overcome': overcomeCount,
      'failed': totalCravings - overcomeCount,
      'successRate': totalCravings > 0 ? (overcomeCount / totalCravings * 100).toStringAsFixed(1) : '0',
      'cigarettesSmoked': cigarettesSmoked,
      'mood': mood ?? 'Не указано',
      'motivationScore': motivationScore ?? 0,
    };
  }
}

// модель данных для статистики бросания человека
class QuitUser {
  final String quitId;
  final User user;
  final DateTime quitStart;
  final int moneySaved;
  bool isQuiting;
  List<String> cravings = [];
  int daysOut;
  List<SmokingDiary> diaries = []; // дневники курения
  List<CravingRecord> allCravings = []; // все записи о желаниях
  DateTime? quitEnd; // дата окончания попытки (если прервана)
  String status; // 'active', 'completed', 'failed'
  bool failedDueToCraving; // завершена ли из-за непреодоленной тяги

  QuitUser(
    this.quitId,
    this.quitStart,
    this.moneySaved,
    this.isQuiting,
    this.cravings,
    this.daysOut,
    this.user, {
    this.quitEnd,
    this.status = 'active',
    this.failedDueToCraving = false,
  }) {
    user.quitStat = this;
  }

  factory QuitUser.newUser(User user, String quitId) {
    final DateTime start = DateTime.now();
    return QuitUser(quitId, start, 0, true, [], 0, user, status: 'active');
  }

  factory QuitUser.byList(Map<String, dynamic> values, User user) {
    List<String> keys = [
      "quitId",
      'quitStart',
      'moneySaved',
      'isQuiting',
      'cravings',
      'daysOut',
      'quitEnd',
      'status',
      'failedDueToCraving',
    ];
    Map<String, dynamic> sortedMap = {};

    values.forEach((key, value) {
      for (String label in keys) {
        if (key == label) {
          sortedMap[key] = value;
        }
      }
    });

    DateTime quitStart;
    try {
      if (sortedMap['quitStart'] is String) {
        quitStart = DateTime.parse(sortedMap['quitStart']);
      } else {
        quitStart = DateTime.now();
      }
    } catch (e) {
      quitStart = DateTime.now();
    }

    DateTime? quitEnd;
    try {
      if (sortedMap['quitEnd'] is String && sortedMap['quitEnd'] != null) {
        quitEnd = DateTime.parse(sortedMap['quitEnd']);
      }
    } catch (e) {
      quitEnd = null;
    }

    List<String> cravingsList = [];
    if (sortedMap['cravings'] is List) {
      cravingsList = List<String>.from(sortedMap['cravings']);
    }

    return QuitUser(
      sortedMap['quitId']?.toString() ?? '',
      quitStart,
      (sortedMap['moneySaved'] as num?)?.toInt() ?? 0,
      (sortedMap['isQuiting'] ?? false) as bool,
      cravingsList,
      (sortedMap['daysOut'] as num?)?.toInt() ?? 0,
      user,
      quitEnd: quitEnd,
      status: sortedMap['status']?.toString() ?? 'active',
      failedDueToCraving: (sortedMap['failedDueToCraving'] ?? false) as bool,
    );
  }

  Map<String, dynamic> getMap() {
    return {
      'quitId': quitId,
      'quitStart': quitStart.toIso8601String(),
      'moneySaved': moneySaved,
      'isQuiting': isQuiting,
      'cravings': cravings,
      'daysOut': daysOut,
      'quitEnd': quitEnd?.toIso8601String(),
      'status': status,
      'failedDueToCraving': failedDueToCraving,
      'diaries': diaries.map((d) => d.toJson()).toList(),
      'allCravings': allCravings.map((c) => c.toJson()).toList(),
    };
  }

  Map<String, String> getIndex() {
    return {quitId: user.userId};
  }

  int get daysWithoutSmoking {
    final now = DateTime.now();
    final endDate = quitEnd ?? now;
    return endDate.difference(quitStart).inDays;
  }

  double calculateMoneySaved(UserStats? userStats) {
    if (userStats == null) return 0.0;
    
    final days = daysWithoutSmoking;
    final monthlyCost = userStats.getMonthlySavings();
    final dailyCost = monthlyCost / 30;
    
    return dailyCost * days;
  }

  Map<String, String> getHealthImprovements() {
    final days = daysWithoutSmoking;
    
    if (days <= 0) return {};
    
    final improvements = <String, String>{};
    final isVape = user.isAlternative;
    
    if (isVape) {
      // Улучшения для электронных сигарет (более мягкие, но все равно важные)
      if (days >= 1) improvements['1 день'] = 'Снижается потребление никотина';
      if (days >= 3) improvements['3 дня'] = 'Улучшается гидратация организма';
      if (days >= 7) improvements['1 неделя'] = 'Восстанавливается вкус и обоняние';
      if (days >= 14) improvements['2 недели'] = 'Улучшается состояние ротовой полости';
      if (days >= 30) improvements['1 месяц'] = 'Снижается зависимость от никотина';
      if (days >= 90) improvements['3 месяца'] = 'Улучшается общее самочувствие';
      if (days >= 180) improvements['6 месяцев'] = 'Значительно снижается никотиновая зависимость';
      if (days >= 365) improvements['1 год'] = 'Почти полное избавление от никотиновой зависимости';
    } else {
      // Улучшения для обычных сигарет (более выраженные улучшения)
      if (days >= 1) improvements['1 день'] = 'Нормализуется давление и пульс';
      if (days >= 2) improvements['2 дня'] = 'Восстанавливается обоняние и вкус';
      if (days >= 3) improvements['3 дня'] = 'Улучшается дыхание, уходит угарный газ';
      if (days >= 7) improvements['1 неделя'] = 'Снижается риск инфаркта, очищаются легкие от смол';
      if (days >= 14) improvements['2 недели'] = 'Улучшается кровообращение, кожа становится здоровее';
      if (days >= 30) improvements['1 месяц'] = 'Увеличивается объем легких, кашель уменьшается';
      if (days >= 90) improvements['3 месяца'] = 'Значительно улучшается функция легких';
      if (days >= 180) improvements['6 месяцев'] = 'Снижается риск рака легких и других заболеваний';
      if (days >= 365) improvements['1 год'] = 'Риск сердечных заболеваний снижается вдвое';
    }
    
    return improvements;
  }

  String getLatestAchievement() {
    final days = daysWithoutSmoking;
    final achievements = getHealthImprovements();
    
    if (achievements.isEmpty) return 'Сделайте первый шаг!';
    
    final lastKey = achievements.keys.last;
    return '${achievements[lastKey]} ($lastKey)';
  }

  // Получить или создать дневник на сегодня
  SmokingDiary getTodayDiary() {
    final today = DateTime.now();
    final todayFormatted = DateTime(today.year, today.month, today.day);
    
    try {
      return diaries.firstWhere(
        (d) => DateTime(d.date.year, d.date.month, d.date.day) == todayFormatted,
      );
    } catch (e) {
      final newDiary = SmokingDiary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: user.userId,
        date: today,
      );
      diaries.add(newDiary);
      return newDiary;
    }
  }

  // Получить статистику по преодоленным желаниям
  Map<String, int> getCravingStats() {
    int totalCravings = 0;
    int overcome = 0;
    int failed = 0;

    for (var craving in allCravings) {
      totalCravings++;
      if (craving.overcome) {
        overcome++;
      } else {
        failed++;
      }
    }

    return {
      'total': totalCravings,
      'overcome': overcome,
      'failed': failed,
    };
  }

  // Получить самый частый триггер
  String? getMostCommonTrigger() {
    if (allCravings.isEmpty) return null;

    final triggerCounts = <String, int>{};
    for (var craving in allCravings) {
      triggerCounts[craving.trigger] = (triggerCounts[craving.trigger] ?? 0) + 1;
    }

    return triggerCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // Получить среднюю мотивацию
  double getAverageMotivation() {
    if (allCravings.isEmpty) return 0.0;
    final sum = allCravings.fold<int>(0, (prev, c) => prev + c.motivationLevel);
    return sum / allCravings.length;
  }

  String getStatusMessage() {
    if (status == 'active') {
      return 'Активная попытка';
    } else if (status == 'completed') {
      return 'Успешно завершена ✓';
    } else if (status == 'failed') {
      if (failedDueToCraving) {
        return 'Завершена: непреодолимая тяга ❌';
      }
      return 'Прервана ✗';
    }
    return 'Неизвестный статус';
  }
}

// Модель статьи
class Article {
  final String id;
  final String title;
  final String content;
  final String category;
  final String author;
  final DateTime createdAt;
  final bool isPublished;

  Article({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.author,
    required this.createdAt,
    required this.isPublished,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'author': author,
      'createdAt': createdAt.toIso8601String(),
      'isPublished': isPublished,
    };
  }

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Общее',
      author: json['author']?.toString() ?? 'Администратор',
      createdAt: DateTime.parse(json['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
      isPublished: (json['isPublished'] ?? true) as bool,
    );
  }

  // Форматированная дата создания
  String get formattedDate {
    return '${createdAt.day}.${createdAt.month}.${createdAt.year}';
  }

  // Сокращенный контент для превью
  String get previewContent {
    if (content.length <= 150) return content;
    return '${content.substring(0, 150)}...';
  }
}

// Категории статей
List<String> articleCategories = [
  'Здоровье',
  'Советы',
  'Мотивация',
  'Наука',
  'Истории успеха',
  'Общее'
];

// Модель администратора
class AdminUser {
  final String id;
  final String email;
  final String fullName;
  final bool isActive;
  final String role; // 'admin', 'moderator', 'editor'
  final DateTime createdAt;

  AdminUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.role,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'isActive': isActive,
      'role': role,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AdminUser.fromJson(String id, Map<String, dynamic> json) {
    return AdminUser(
      id: id,
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      isActive: json['isActive'] ?? true,
      role: json['role'] ?? 'moderator',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}