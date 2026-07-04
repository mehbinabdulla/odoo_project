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

  void show(String message, {AppNotificationType type = AppNotificationType.info}) {
    _current = AppNotification(message: message, type: type);
    notifyListeners();
    
    // Clear after duration
    Future.delayed(_current!.duration, () {
      if (_current?.message == message) {
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
