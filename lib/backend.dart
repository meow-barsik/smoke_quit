import 'dart:core';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class User {
  late final String _userId;
  late final String _mail;
  late final String _password;
  late final String _userName;
  late final bool _isAlternative;
  late bool _isOnboarded;
  late Map<dynamic, dynamic> data;

  User(this._userId, this._mail, this._password, this._userName, this._isAlternative,
      this._isOnboarded);

  Map<dynamic, dynamic> getMap() {
    data = {
      'userId': _userId,
      'mail': _mail,
      'password': _password,
      'userName': _userName,
      'isAlternative': _isAlternative,
      'isOnboarded': _isOnboarded
    };
    return data;
  }
}

class UserStats {
  late int cigarettesOrPuffsPerDay;
  late int priceCigaretteOrLiquid;
  UserStats(this.cigarettesOrPuffsPerDay, this.priceCigaretteOrLiquid);
}

class AuthService {
  final DatabaseReference _database = FirebaseDatabase.instance.refFromURL
  ("https://smokequit-b0f8f-default-rtdb.firebaseio.com");
  bool authStatus = false;
}

class RegService {
  final DatabaseReference _database = FirebaseDatabase.instance.refFromURL
    ("https://smokequit-b0f8f-default-rtdb.firebaseio.com");
  Future<User> registration(mail, password, userName, isAlternative) async {

    DatabaseReference ref = _database.child('users').push();
    User userInfo = User(ref as String, mail, password, userName, isAlternative,
        false);
    var data = userInfo.getMap();
    await ref.set(data);

    return userInfo;
  }
}

class DatabaseUtils {
  static Future<void> performHeavyDatabaseOperation(Function operation) async {
    await Future.delayed(Duration.zero); // Освобождаем event loop
    await operation();
  }
}
