import 'package:flutter/material.dart';

import '../theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon/logo.png', width: 120),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: gullifyAmber),
          ],
        ),
      ),
    );
  }
}
