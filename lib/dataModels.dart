import 'dart:async';
import 'dart:core';
import 'dart:ffi';

import 'package:firebase_database/firebase_database.dart';

class User {
  final String _userId;
  final String _mail;
  final String _password;
  bool _isAlternative;
  bool _isOnboarded;
  UserStats? stats;
  QuitUser? quitStat;

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
      'isOnboarded': _isOnboarded
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

  set quitUser(QuitUser quitUser) {}
  set isOnboarded(bool value) => _isOnboarded = value;}

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
  })  : assert(bottlePrice > 0),
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
  })  : assert(packPrice > 0),
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
      lastAttemptDate = DateTime.parse(json['lastAttemptDate']?.toString() ?? '');
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

List<String> cravingsReason = ['Алкоголь', 'Компания', 'Утренний ритуал',
  'Перерыв на работе', 'Кофейный или чайный перерыв', 'Стресс',
  'Перекур после еды'];

// модель данных для статистики бросания человека
class QuitUser {
  final String quitId;
  final User user;
  final DateTime quitStart;
  final int moneySaved;
  bool isQuiting;
  List<String> cravings = [];
  int daysOut;

  QuitUser(this.quitId, this.quitStart, this.moneySaved, this.isQuiting,
  this.cravings, this.daysOut, this.user) {
    user.quitUser = this;
  }

  factory QuitUser.newUser(user, quitId) {
    final DateTime start = DateTime.now();

    return QuitUser(quitId, start, 0, true, [], 0, user);
  }

  factory QuitUser.byList(Map<String, dynamic> values, user) {
    List<String> keys = ["quitId", 'quitStart', 'moneySaved',
      'isQuiting', 'cravings', 'daysOut'];
    Map<String, dynamic> sortedMap= {};

    values.forEach((key, value) {
      for (String label in keys) {
        if (key == label) {
          sortedMap[key] = value;
        }
      }
    });

    return QuitUser(sortedMap['quitId'], sortedMap['quitStart'],
        sortedMap['moneySaved'], sortedMap['isQuiting'],
        sortedMap['cravings'], sortedMap['daysOut'], user);
  }

  Map<String, dynamic> getMap() {
    return {
      'quitId': quitId,
      'quitStart': quitStart,
      'moneySaved': moneySaved,
      'isQuiting': isQuiting,
      'cravings': cravings,
      'daysOut': daysOut
    };
  }

  Map<String, String> getIndex() {
    return {quitId: user.userId};
  }


}


