import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../widgets/app_widgets.dart';
import '../services/correction_training_service.dart';
import '../theme/theme_controller.dart';

/// Screen 12 - Settings.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;

  /// Number of user category corrections collected on this device, i.e. new
  /// training data. Null while loading.
  int? _correctionCount;
  Map<String, int> _correctionsByCategory = <String, int>{};

  final CorrectionTrainingService _training = CorrectionTrainingService();

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
    _loadCorrectionStats();
  }

  /// Reads the real correction stats so the dataset/retrain tiles reflect what
  /// the user has actually generated instead of a static placeholder.
  Future<void> _loadCorrectionStats() async {
    try {
      final int count = await _training.correctionCount();
      final Map<String, int> byCategory =
          await _training.correctionsByCategory();
      if (!mounted) {
        return;
      }
      setState(() {
        _correctionCount = count;
        _correctionsByCategory = byCategory;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _correctionCount = 0);
    }
  }

  /// Explains what the collected corrections are and how many exist.
  void _showDatasetInfo() {
    final int total = _correctionCount ?? 0;
    final String breakdown = _correctionsByCategory.isEmpty
        ? 'Belum ada koreksi kategori yang tercatat.'
        : _correctionsByCategory.entries
            .map((MapEntry<String, int> e) => '• ${e.key}: ${e.value}')
            .join('\n');
    _showInfoSheet(
      title: 'Kelola Dataset',
      body: 'Koreksi kategori Anda tersimpan otomatis dan dipakai sebagai '
          'data training untuk melatih ulang model.\n\n'
          'Total koreksi: $total\n$breakdown',
    );
  }

  void _showRetrainInfo() {
    final int total = _correctionCount ?? 0;
    _showInfoSheet(
      title: 'Latih Ulang Model',
      body: total == 0
          ? 'Belum ada data koreksi. Perbaiki minimal satu kategori di layar '
              'Review agar model punya data baru untuk dilatih ulang.'
          : 'Tersedia $total koreksi sebagai data training. Proses pelatihan '
              'ulang model dijalankan di luar aplikasi (offline training), '
              'lalu hasilnya menggantikan assets/model_kategori_produk.json.',
    );
  }

  void _showInfoSheet({required String title, required String body}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: FloatingNavBody(
          nav: AppBottomNav(
            activeIndex: 4,
            onSelect: (int i) => navigateTab(context, i),
            onScan: () => openScan(context),
          ),
          child: Column(
          children: <Widget>[
            const AppStatusBar(),
            const AppTopBar(title: 'Pengaturan'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  22,
                  6,
                  22,
                  24 + AppBottomNav.clearance(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _ProfileCard(),
                    const SizedBox(height: 20),
                    _SettingsGroup(
                      title: 'Preferensi',
                      children: <Widget>[
                        _SwitchTile(
                          icon: Icons.dark_mode_outlined,
                          title: 'Mode Gelap',
                          value: themeController.isDark,
                          onChanged: themeController.setDark,
                        ),
                        const _Divider(),
                        _SwitchTile(
                          icon: Icons.notifications_none,
                          title: 'Notifikasi',
                          value: _notifications,
                          onChanged: (bool v) => setState(() => _notifications = v),
                        ),
                        const _Divider(),
                        const _LinkTile(
                          icon: Icons.payments_outlined,
                          title: 'Mata Uang',
                          trailingText: 'IDR (Rp)',
                        ),
                        const _Divider(),
                        const _LinkTile(
                          icon: Icons.language_outlined,
                          title: 'Bahasa',
                          trailingText: 'Indonesia',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsGroup(
                      title: 'Data & Machine Learning',
                      children: <Widget>[
                        const _LinkTile(
                          icon: Icons.label_outline,
                          title: 'Kategori & Label',
                        ),
                        const _Divider(),
                        _LinkTile(
                          icon: Icons.dataset_outlined,
                          title: 'Kelola Dataset',
                          trailingText: _correctionCount == null
                              ? null
                              : '$_correctionCount koreksi',
                          onTap: _showDatasetInfo,
                        ),
                        const _Divider(),
                        _LinkTile(
                          icon: Icons.memory,
                          title: 'Latih Ulang Model',
                          trailingText: _correctionCount == null
                              ? 'v1.0'
                              : 'v1.0 • $_correctionCount data',
                          onTap: _showRetrainInfo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsGroup(
                      title: 'Lainnya',
                      children: <Widget>[
                        const _LinkTile(
                          icon: Icons.info_outline,
                          title: 'Tentang Aplikasi',
                          trailingText: '1.0.0',
                        ),
                        const _Divider(),
                        const _LinkTile(
                          icon: Icons.help_outline,
                          title: 'Bantuan & Dukungan',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SettingsGroup(
                      children: <Widget>[
                        _LinkTile(
                          icon: Icons.logout,
                          title: 'Keluar',
                          danger: true,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.avatarColor('Rian Pratama'),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'R',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Rian Pratama',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'rian@student.polinema.ac.id',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 22, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 64),
      child: Divider(height: 1, color: AppColors.border),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    this.trailingText,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailingText;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = danger ? AppColors.red : AppColors.iconMuted;
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            IconBox(
              icon: icon,
              size: 36,
              iconSize: 18,
              background: danger ? AppColors.redSoft : AppColors.iconBox,
              color: tint,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: danger ? AppColors.red : AppColors.textDark,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: danger ? AppColors.red : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          IconBox(icon: icon, size: 36, iconSize: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.switchActive,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
