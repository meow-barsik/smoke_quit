import 'dart:core';
import 'package:firebase_database/firebase_database.dart';

class User {
  late final String _userId;
  late final String _mail;
  late final String _password;
  late final bool _isAlternative;
  late bool _isOnboarded;
  late Map<dynamic, dynamic> data;

  User(this._userId, this._mail, this._password, this._isAlternative,
      this._isOnboarded);

  Map<dynamic, dynamic> getMap() {
    data = {
      'userId': _userId,
      'mail': _mail,
      'password': _password,
      'isAlternative': _isAlternative,
      'isOnboarded': _isOnboarded
    };
    return data;
  }

  Map<dynamic, dynamic> getIndex() {
    return {_userId: _mail};
  }

  static User createUserByList(List<dynamic> list) {
    // Добавляем проверки на null и преобразование к bool
    return User(
      list[0] ?? '', // userId
      list[1] ?? '', // mail
      list[2] ?? '', // password
      (list[3] ?? false) as bool, // isAlternative - преобразуем к bool
      (list[4] ?? false) as bool, // isOnboarded - преобразуем к bool
    );
  }

  String get getPasswd => _password;
}

class UserStats {
  late int cigarettesOrPuffsPerDay;
  late int priceCigaretteOrLiquid;
  UserStats(this.cigarettesOrPuffsPerDay, this.priceCigaretteOrLiquid);
}


class RegService {
  final DatabaseReference databaseReference;
  final User user;

  RegService._({required this.user, required this.databaseReference});

  static Future<RegService> createRegService(email, password) async {
    final DatabaseReference _database = FirebaseDatabase.instance.refFromURL(
        'https://smokequit-b0f8f-default-rtdb.firebaseio.com'
    );
    final DatabaseReference ref = _database.child('users').push();
    final String? id = ref.key;

    User? user = User(id!, email, password, true, false);
    addData(_database, user, id, email);

    return RegService._(user: user, databaseReference: _database);
  }

  static Future<void> addData(ref, user, key, mail) async {
    await ref.child('users').child(key).set(user.getMap());
    await ref.child('usersIndex').child(key).set(mail);
  }
}

class AuthService {
  late User? _user;

  AuthService(User? user) {
    _user = user;
  }

  static Future<AuthService> createAuthService(getMail) async {
    print(getMail);
    final database = FirebaseDatabase.instance.refFromURL
      ('https://smokequit-b0f8f-default-rtdb.firebaseio.com/');
    final User? user = await searchUser(database, getMail);

    return AuthService(user);
  }

  static Future<User?> searchUser(database, mail) async {
    DataSnapshot snapshot = await database.child('usersIndex').get();
    Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
    late List<dynamic> list;

    for (dynamic key in data.keys) {

      if (mail == data[key]) {
        print(data[key]);
        list = await getData(key, database);
        return User.createUserByList(list);
      }
    }
    return null;
  }

  static Future<List<dynamic>> getData(key, database) async {
    DataSnapshot snapshot = await database.child('users').child(key).get();
    final data = snapshot.value as Map<dynamic, dynamic>;

    final List<String> titles =
      ['userId', 'mail', 'password', 'isAlternative', 'isOnboarded'];
    List<dynamic> dataList = [];

    for (int i = 0; i < titles.length; i++) {
      dynamic value = data[titles[i]];
      if (titles[i] == 'isAlternative' || titles[i] == 'isOnboarded') {
        value = value ?? false;
      }
      dataList.add(value);
    }
    print(dataList);

    return dataList;
  }
  User? get getUserInfo => _user;
}
