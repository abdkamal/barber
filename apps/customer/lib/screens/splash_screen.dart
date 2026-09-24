import 'package:flutter/material.dart';

/// شاشة البداية — علامة «صالوني» أثناء استعادة الجلسة.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('صالوني', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
