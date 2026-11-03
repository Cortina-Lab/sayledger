import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  await Api.instance.load();
  runApp(const SayLedgerApp());
}

class SayLedgerApp extends StatelessWidget {
  const SayLedgerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SayLedger',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: Api.instance.hasBook ? const HomeScreen() : const OnboardingScreen(),
      );
}
