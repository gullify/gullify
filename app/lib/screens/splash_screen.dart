import 'package:flutter/material.dart';

import '../theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, size: 64, color: gullifyAmber),
            SizedBox(height: 24),
            CircularProgressIndicator(color: gullifyAmber),
          ],
        ),
      ),
    );
  }
}
