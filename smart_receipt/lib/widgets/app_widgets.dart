import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../models/models.dart';

/// iOS-style status bar used across every screen for visual consistency.
class AppStatusBar extends StatelessWidget {
  const AppStatusBar({super.key, this.time = ''});

  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
    );
  }
}

/// Screen title bar with optional back button and trailing actions.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            CircleIconButton(icon: Icons.arrow_back, onTap: onBack!),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Small circular icon button (used for back / header actions).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? AppColors.card,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.textDark),
        ),
      ),
    );
  }
}

/// White section header: accent bar + title + optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.showAccent = true,
  });

  final String title;
  final Widget? trailing;
  final bool showAccent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (showAccent) ...<Widget>[
          Container(
            width: 6,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Filled navy call-to-action button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.color,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final Color fg = foreground ?? AppColors.onButton;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 19, color: fg),
            const SizedBox(width: 9),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: onPressed == null
          ? (color ?? AppColors.buttonBg).withValues(alpha: 0.4)
          : (color ?? AppColors.buttonBg),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: expanded ? SizedBox(width: double.infinity, child: content) : content,
      ),
    );
  }
}

/// Outlined button used for secondary actions.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: AppColors.buttonBg),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.buttonBg,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.4),
            borderRadius: BorderRadius.circular(15),
          ),
          child: expanded ? SizedBox(width: double.infinity, child: content) : content,
        ),
      ),
    );
  }
}

/// Colored category pill.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, this.dense = false});

  final String category;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(category);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(c.icon, size: dense ? 11 : 13, color: c.color),
          const SizedBox(width: 5),
          Text(
            category,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: c.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded light-blue box that holds a leading icon.
class IconBox extends StatelessWidget {
  const IconBox({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 22,
    this.background,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.iconBox,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, size: iconSize, color: color ?? AppColors.iconMuted),
    );
  }
}

/// The floating bottom navigation shared by the main tabs.
///
/// [activeIndex] maps: 0 Beranda, 1 Riwayat, 3 Analisis, 4 Pengaturan.
/// Index 2 is the central Scan button handled by [onScan].
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.activeIndex,
    required this.onSelect,
    required this.onScan,
  });

  final int activeIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;

  static const double _padTop = 10;
  static const double _bodyHeight = 84;
  static const double _padBottom = 14;

  /// Total vertical space the nav occupies, excluding the device safe area.
  static const double height = _padTop + _bodyHeight + _padBottom;

  /// Bottom padding a scroll view needs so its content can pass behind the
  /// floating nav without being cut off.
  static double clearance(BuildContext context) =>
      height + MediaQuery.of(context).padding.bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        _padTop,
        18,
        _padBottom + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        height: _bodyHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 66,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(33),
                  border: Border.all(color: AppColors.border, width: 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _NavItem(
                        icon: Icons.home_outlined,
                        label: 'Beranda',
                        active: activeIndex == 0,
                        onTap: () => onSelect(0),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.receipt_long_outlined,
                        label: 'Riwayat',
                        active: activeIndex == 1,
                        onTap: () => onSelect(1),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(label: 'Scan', onTap: onScan),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.bar_chart,
                        label: 'Analisis',
                        active: activeIndex == 3,
                        onTap: () => onSelect(3),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.settings_outlined,
                        label: 'Pengaturan',
                        active: activeIndex == 4,
                        onTap: () => onSelect(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(top: 0, child: _ScanButton(onTap: onScan)),
          ],
        ),
      ),
    );
  }
}

/// Lays [child] full-bleed with the floating [nav] overlaid at the bottom, so
/// scrollable content can pass behind the nav instead of being clipped above
/// it. Pair it with [AppBottomNav.clearance] as bottom padding.
class FloatingNavBody extends StatelessWidget {
  const FloatingNavBody({super.key, required this.nav, required this.child});

  final Widget nav;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        Positioned(left: 0, right: 0, bottom: 0, child: nav),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    this.icon,
    this.active = false,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 24,
            width: 24,
            child: icon == null
                ? null
                : Icon(
                    icon,
                    size: 22,
                    color: active ? AppColors.textDark : AppColors.iconMuted,
                  ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.textDark : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.buttonBg.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.buttonBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.photo_camera_outlined,
              size: 24,
              color: AppColors.onButton,
            ),
          ),
        ),
      ),
    );
  }
}
