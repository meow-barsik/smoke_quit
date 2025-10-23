import 'dart:ffi';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'backend.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async{
  runApp(const SmokeQuit());
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
}

class SmokeQuit extends StatelessWidget {
  const SmokeQuit({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
      title: "SmokeQuit",
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  final List<Widget> _screens = [
    const HomePage(),
    const PlaceholderWidget(title: 'Статистика'),
    const PlaceholderWidget(title: 'Достижения'),
    const PlaceholderWidget(title: 'Профиль'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => OnBoardingWindow()));
        //AuthReg.show(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onTabSelected(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const ClampingScrollPhysics(),
        children: _screens,
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: _onTabSelected,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Theme.of(context).bottomAppBarTheme.color,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Colors.grey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Главная',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_outlined),
          activeIcon: Icon(Icons.bar_chart),
          label: 'Статистика',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.emoji_events_outlined),
          activeIcon: Icon(Icons.emoji_events),
          label: 'Достижения',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outlined),
          activeIcon: Icon(Icons.person),
          label: 'Профиль',
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _daysWithoutSmoking = 0;
  double _moneySaved = 0.0;

  void _resetProgress() {
    setState(() {
      _daysWithoutSmoking = 0;
      _moneySaved = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmokeQuit'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _daysWithoutSmoking.toString(),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Дней без курения",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        "₽${_moneySaved.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Сэкономлено средств",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _resetProgress,
                child: const Text('Сбросить прогресс'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthReg extends StatefulWidget {
  const AuthReg({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => const AuthReg(),
    );
  }
  @override
  State<AuthReg> createState() => _AuthState();
}

class _AuthState extends State<AuthReg> {
  bool _isLogin = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }

  Future<void> _submitForm() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar('Заполните все поля');
      return;
    }
    setState(() {
      _isLoading = true;
    });

    if (_isLogin) {
      final AuthService auth = await AuthService.createAuthService(email);
      User? user = auth.getUserInfo;
      print(user?.getPasswd);
      if (user != null) {
        if (password == user.getPasswd) {
          Navigator.of(context).pop();
        }
        else {
          _showErrorSnackBar("Неверный пароль");
        }
      }
      else {
        _showErrorSnackBar("Пользователя не существует");
      }
    }
    else {
          User? user = await AuthService.searchUser(
          FirebaseDatabase.instance.refFromURL
            ('https://smokequit-b0f8f-default-rtdb.firebaseio.com/'), email);
      if (user == null) {
        final RegService reg = await RegService.createRegService(email, password);
        user = reg.user;
        print(user.getMap());
        setState(() {
          Navigator.of(context).pop();
        });
      }
      else {
        _showErrorSnackBar("Пользователь существует");
      }

    }
    setState(() {
      _isLoading = false;
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible( child:
              Text(
                _isLogin ? "Вход" : "Регистрация",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Почта",
                hintText: "Введите почту",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Пароль",
                hintText: "Введите пароль",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _toggleAuthMode,
                  child: Text(
                    _isLogin ? "Создать аккаунт" : "Уже есть аккаунт?",
                  ),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  child: _isLoading
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Flexible( child:
                        Text(_isLogin ? "Войти" : "Продолжить"),
                  )
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class OnBoardingWindow extends StatefulWidget {
  const OnBoardingWindow({super.key});

  @override
  State<StatefulWidget> createState() => OnBoardingWindowState();
}

class OnBoardingWindowState extends State<OnBoardingWindow> {
  String? _selectedValue;
  final List<String> _types = ["Обычные сигареты", "Электронные сигареты"];
  String _cigType = "thin";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Форма курящего", textAlign: TextAlign.center),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "Тип курения",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            _smokingType(),
            SizedBox(height: 20),
            ..._selectContent(),
          ],
        ),
      ),
    );
  }

  Widget _smokingType() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: _selectedValue,
        isExpanded: true,
        hint: Text("Выберите тип"),
        items: _types.map((type) {
          return DropdownMenuItem<String>(
            value: type,
            child: Text(type),
          );
        }).toList(),
        onChanged: (String? newVal) {
          setState(() {
            _selectedValue = newVal;
          });
        },
        underline: SizedBox(), // Убираем стандартную линию
      ),
    );
  }

  List<Widget> _selectContent() {
    if (_selectedValue == null) {
      return [
        Text(
          "Выберите тип курения",
          style: TextStyle(
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ];
    }
    switch (_selectedValue) {
      case "Обычные сигареты":
        return _cigContent();
      case "Электронные сигареты":
        return _electroContent();
      default:
        return [];
    }
  }

  List<Widget> _cigContent() {
    return [
      SizedBox(height: 16),
      TextField(
        decoration: InputDecoration(
          labelText: "Сигарет в день",
          hintText: "Например: 20",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      SizedBox(height: 12),
      TextField(
        decoration: InputDecoration(
          labelText: "Стоимость пачки",
          hintText: "Например: 200",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      SizedBox(height: 16),
      Text(
        "Тип сигарет:",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      SizedBox(height: 8),
      // Исправленные Radio кнопки
      Row(
        children: <Widget>[
          Expanded(
            child: RadioListTile<String>(
              title: Text("Тонкие"),
              value: "thin",
              groupValue: _cigType,
              onChanged: (String? value) {
                setState(() {
                  _cigType = value!;
                });
              },
            ),
          ),
          Expanded(
            child: RadioListTile<String>(
              title: Text("Толстые"),
              value: "thick",
              groupValue: _cigType,
              onChanged: (String? value) {
                setState(() {
                  _cigType = value!;
                });
              },
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _electroContent() {
    return [
      SizedBox(height: 16),
      TextField(
        decoration: InputDecoration(
          labelText: "Затяжек в день",
          hintText: "Например: 200",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      SizedBox(height: 12),
      TextField(
        decoration: InputDecoration(
          labelText: "Стоимость жидкости",
          hintText: "Например: 500",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      SizedBox(height: 12),
      TextField(
        decoration: InputDecoration(
          labelText: "Мл жидкости в день",
          hintText: "Например: 5",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
    ];
  }
}



class PlaceholderWidget extends StatelessWidget {
  final String title;

  const PlaceholderWidget({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title - в разработке',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}