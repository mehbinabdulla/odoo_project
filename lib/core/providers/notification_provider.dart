import 'package:flutter/material.dart';

enum AppNotificationType { info, success, warning, error }

class AppNotification {
  final String message;
  final AppNotificationType type;
  final Duration duration;

  AppNotification({
    required this.message,
    this.type = AppNotificationType.info,
    this.duration = const Duration(seconds: 4),
  });
}

class NotificationProvider with ChangeNotifier {
  AppNotification? _current;
  AppNotification? get current => _current;

  /// Monotonic generation so rapid show() calls can't race the delayed
  /// clear: only the latest notification's timer may clear the state.
  int _generation = 0;

  void show(String message, {AppNotificationType type = AppNotificationType.info}) {
    final gen = ++_generation;
    _current = AppNotification(message: message, type: type);
    notifyListeners();

    // Clear after duration
    Future.delayed(_current!.duration, () {
      if (gen == _generation) {
        _current = null;
        notifyListeners();
      }
    });
  }

  void hide() {
    _current = null;
    notifyListeners();
  }
}
