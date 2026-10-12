import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// App-wide theme state. Kept as a single instance so the Settings switch and
/// the root [MaterialApp] always agree on which palette is active.
///
/// The default mode is [ThemeMode.system] so a fresh install follows the
/// device setting. Once the user flips the switch the choice becomes explicit
/// and is persisted, so it survives an app restart.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _apply();
  }

  static const String _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  bool _platformDark = false;

  ThemeMode get mode => _mode;

  /// True while the app is still following the device setting.
  bool get followsSystem => _mode == ThemeMode.system;

  /// Resolved dark state: an explicit choice wins, otherwise the device
  /// brightness decides.
  bool get isDark =>
      _mode == ThemeMode.dark || (_mode == ThemeMode.system && _platformDark);

  /// Reports the current device brightness so [ThemeMode.system] can resolve to
  /// a concrete palette.
  void setPlatformDark(bool dark) {
    if (_platformDark == dark) {
      return;
    }
    _platformDark = dark;
    if (_mode == ThemeMode.system) {
      _apply();
      notifyListeners();
    }
  }

  void setMode(ThemeMode mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    _apply();
    notifyListeners();
    _persist();
  }

  void setDark(bool dark) => setMode(dark ? ThemeMode.dark : ThemeMode.light);

  /// Restores the last used mode. Safe to call before `runApp`.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _mode = switch (prefs.getString(_prefsKey)) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
      _apply();
      notifyListeners();
    } catch (_) {
      // No storage available (e.g. widget tests): keep the current mode.
    }
  }

  void _apply() => AppColors.apply(isDark ? AppPalette.dark : AppPalette.light);

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, switch (_mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      });
    } catch (_) {
      // Ignore: persistence is best-effort.
    }
  }
}

/// Single shared controller for the whole app.
final ThemeController themeController = ThemeController();

/// Exposes [themeController] to the widget tree and, crucially, lets screens
/// register a dependency on it. Because colours are read from the static
/// [AppColors] getters (not from `Theme`), a screen only repaints when it calls
/// [ThemeScope.watch] during `build`.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Marks the calling widget as depending on the active theme.
  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<ThemeScope>();
  }
}
