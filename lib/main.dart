import 'dart:core';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/services.dart' hide Size;
import 'backend.dart';
import 'dataModels.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmokeQuit());
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
  User? _currentUser;

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
        _showAuthDialog();
      }
    });
  }

  void _showAuthDialog() {
    AuthReg.show(context, onUserAuthenticated: (user) {
      setState(() {
        _currentUser = user;
      });

      if (!user.getOnboarded) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => OnBoardingWindow(user: user))
        );
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
  final Function(User)? onUserAuthenticated;

  const AuthReg({super.key, this.onUserAuthenticated});

  static void show(BuildContext context, {Function(User)? onUserAuthenticated}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => AuthReg(onUserAuthenticated: onUserAuthenticated),
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

    try {
      if (_isLogin) {
        final AuthService auth = await AuthService.createAuthService(email);
        User? user = auth.getUserInfo;

        if (user != null) {
          if (password == user.getPasswd) {
            Navigator.of(context).pop();
            if (user.getOnboarded) {
              final onboardingService = await OnBoardingService.createOnboardingService(user);
              await onboardingService.onboardingAuth();
            }

            if (widget.onUserAuthenticated != null) {
              widget.onUserAuthenticated!(user);
            }
          } else {
            _showErrorSnackBar("Неверный пароль");
          }
        } else {
          _showErrorSnackBar("Пользователя не существует");
        }
      } else {
        User? existingUser = await AuthService.searchUser(
            FirebaseDatabase.instance.refFromURL(
                'https://smokequit-b0f8f-default-rtdb.firebaseio.com/'), email);

        if (existingUser == null) {
          final RegService reg = await RegService.createRegService(email, password);
          final user = reg.user;

          if (widget.onUserAuthenticated != null) {
            widget.onUserAuthenticated!(user);
            Navigator.of(context).pop();
          }
        } else {
          _showErrorSnackBar("Пользователь существует");
        }
      }
    } catch (e) {
      _showErrorSnackBar("Произошла ошибка: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
            Text(
              _isLogin ? "Вход" : "Регистрация",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
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
                      : Text(_isLogin ? "Войти" : "Продолжить"),
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
  final User user;

  const OnBoardingWindow({super.key, required this.user});

  @override
  State<StatefulWidget> createState() => OnBoardingWindowState();
}

class OnBoardingWindowState extends State<OnBoardingWindow> {
  String? _selectedValue;
  final List<String> _types = ["Обычные сигареты", "Электронные сигареты"];
  String _cigType = "thin";
  final TextEditingController _dateController = TextEditingController();

  final TextEditingController _yearsController = TextEditingController();
  final TextEditingController _monthsController = TextEditingController();
  final TextEditingController _attemptsController = TextEditingController();
  final TextEditingController _cigPerDayController = TextEditingController();
  final TextEditingController _packPriceController = TextEditingController();
  final TextEditingController _powerController = TextEditingController();
  final TextEditingController _liquidPriceController = TextEditingController();
  final TextEditingController _liquidDaysController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Форма курящего", textAlign: TextAlign.center),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text("Стаж курения"),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearsController,
                      decoration: const InputDecoration(labelText: "Лет"),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите количество лет';
                        }
                        final years = int.tryParse(value);
                        if (years == null) return 'Только цифры';
                        if (years < 0) return 'Не может быть отрицательным';
                        if (years > 100) return 'Слишком большое значение';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _monthsController,
                      decoration: const InputDecoration(labelText: "Месяцев"),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите количество месяцев';
                        }
                        final months = int.tryParse(value);
                        if (months == null) return 'Только цифры';
                        if (months < 0) return 'Не может быть отрицательным';
                        if (months >= 12) return 'Должно быть меньше 12';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _attemptsController,
                decoration: const InputDecoration(
                    labelText: "Кол-во попыток бросания"
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите количество попыток';
                  }
                  final attempts = int.tryParse(value);
                  if (attempts == null) return 'Только цифры';
                  if (attempts < 0) return 'Не может быть отрицательным';
                  if (attempts > 100) return 'Слишком большое значение';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: "Дата последней попытки",
                  hintText: "дд.мм.гггг",
                  helperText: "Например: 15.05.2023",
                ),
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите дату';
                  }
                  final regex = RegExp(r'^\d{2}\.\d{2}\.\d{4}$');
                  if (!regex.hasMatch(value)) {
                    return 'Формат: дд.мм.гггг';
                  }
                  if (!_isValidDate(value)) {
                    return 'Введите корректную дату';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const Text(
                "Тип курения",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _smokingType(),
              const SizedBox(height: 16),
              ..._selectContent(),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: _validateAndSubmit,
                child: const Text('Сохранить данные'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _validateAndSubmit() async {
    FocusScope.of(context).unfocus();

    if (_selectedValue == null) {
      _showError('Пожалуйста, выберите тип курения');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _showError('Исправьте ошибки в форме');
      return;
    }

    if (!_validateSelectedTypeContent()) {
      return;
    }

    if (!_validateSmokingExperience()) {
      return;
    }

    await _processFormData();
  }

  bool _validateSelectedTypeContent() {
    if (_selectedValue == "Обычные сигареты") {
      final cigPerDay = _cigPerDayController.text;
      final packPrice = _packPriceController.text;

      if (cigPerDay.isEmpty) {
        _showError('Введите количество сигарет в день');
        return false;
      }
      if (packPrice.isEmpty) {
        _showError('Введите стоимость пачки');
        return false;
      }

      final cigPerDayInt = int.tryParse(cigPerDay);
      final packPriceInt = int.tryParse(packPrice);

      if (cigPerDayInt == null || cigPerDayInt <= 0) {
        _showError('Количество сигарет должно быть положительным числом');
        return false;
      }
      if (packPriceInt == null || packPriceInt <= 0) {
        _showError('Стоимость пачки должна быть положительным числом');
        return false;
      }

    } else if (_selectedValue == "Электронные сигареты") {
      final power = _powerController.text;
      final liquidPrice = _liquidPriceController.text;
      final liquidDays = _liquidDaysController.text;

      if (power.isEmpty) {
        _showError('Введите силу затяжки');
        return false;
      }
      if (liquidPrice.isEmpty) {
        _showError('Введите стоимость банки жидкости');
        return false;
      }
      if (liquidDays.isEmpty) {
        _showError('Введите количество дней на банку жидкости');
        return false;
      }

      final powerInt = int.tryParse(power);
      final liquidPriceInt = int.tryParse(liquidPrice);
      final liquidDaysInt = int.tryParse(liquidDays);

      if (powerInt == null || powerInt <= 0) {
        _showError('Сила затяжки должна быть положительным числом');
        return false;
      }
      if (liquidPriceInt == null || liquidPriceInt <= 0) {
        _showError('Стоимость жидкости должна быть положительным числом');
        return false;
      }
      if (liquidDaysInt == null || liquidDaysInt <= 0) {
        _showError('Количество дней должно быть положительным числом');
        return false;
      }
    }

    return true;
  }

  bool _validateSmokingExperience() {
    final years = int.tryParse(_yearsController.text) ?? 0;
    final months = int.tryParse(_monthsController.text) ?? 0;

    if (years == 0 && months == 0) {
      _showError('Стаж курения не может быть нулевым');
      return false;
    }

    if (years > 80) {
      _showError('Проверьте правильность введенного стажа');
      return false;
    }

    return true;
  }

  Future<void> _processFormData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final smokingYears = int.tryParse(_yearsController.text);
      final smokingMonth = int.parse(_monthsController.text);
      final attempts = int.parse(_attemptsController.text);

      // Парсим дату
      final dateParts = _dateController.text.split('.');
      final lastDate = DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
      );

      final isAlternative = _selectedValue == "Электронные сигареты";

      widget.user.isAlternative = isAlternative;

      SmokingStats stats;

      if (isAlternative) {
        stats = VapeStats(
          puffPower: int.parse(_powerController.text),
          bottlePrice: int.parse(_liquidPriceController.text),
          daysOnBottle: int.parse(_liquidDaysController.text),
          puffPerDay: 0, // Можно добавить поле для этого
        );
      } else {
        stats = CigStats(
          cigType: _cigType,
          cigPerDay: int.parse(_cigPerDayController.text),
          packPrice: int.parse(_packPriceController.text),
        );
      }

      final onboardingService = await OnBoardingService.createOnboardingService(widget.user);
      await onboardingService.onboardingRegistration(
        smokingYears: smokingYears,
        smokingMonth: smokingMonth,
        attempts: attempts,
        lastDate: lastDate,
        type: _selectedValue!,
        stats: stats,
      );

      _showSuccess('Данные успешно сохранены!');

      // Возвращаемся на главный экран
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showError('Ошибка сохранения данных: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isValidDate(String dateString) {
    try {
      final parts = dateString.split('.');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      if (year < 2000 || year > DateTime.now().year) return false;
      if (month < 1 || month > 12) return false;
      if (day < 1 || day > 31) return false;

      final date = DateTime(year, month, day);
      if (date.day != day || date.month != month) return false;

      if (date.isAfter(DateTime.now())) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _smokingType() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: _selectedValue,
        isExpanded: true,
        hint: const Text("Выберите тип"),
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
        underline: const SizedBox(),
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
      const SizedBox(height: 16),
      TextFormField(
        controller: _cigPerDayController,
        decoration: const InputDecoration(
          labelText: "Сигарет в день",
          hintText: "Например: 20",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _packPriceController,
        decoration: const InputDecoration(
          labelText: "Стоимость пачки",
          hintText: "Например: 200",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: 16),
      const Text(
        "Тип сигарет:",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: RadioListTile<String>(
              title: const Text("Тонкие"),
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
              title: const Text("Толстые"),
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
      const SizedBox(height: 16),
      TextFormField(
        controller: _powerController,
        decoration: const InputDecoration(
          labelText: "Сила затяжки в ваттах",
          hintText: "Например: 15",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _liquidPriceController,
        decoration: const InputDecoration(
          labelText: "Средняя стоимость банки жидкости",
          hintText: "Например: 400",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _liquidDaysController,
        decoration: const InputDecoration(
          labelText: "Кол-во дней на банку жидкости 30мл",
          hintText: "Например: 15",
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    ];
  }

  @override
  void dispose() {
    _yearsController.dispose();
    _monthsController.dispose();
    _attemptsController.dispose();
    _dateController.dispose();
    _cigPerDayController.dispose();
    _packPriceController.dispose();
    _powerController.dispose();
    _liquidPriceController.dispose();
    _liquidDaysController.dispose();
    super.dispose();
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