import 'package:flutter/material.dart';

/// A complete colour palette for a single brightness.
///
/// Widgets never read a palette directly: they go through [AppColors], whose
/// getters return the value of whichever palette is currently active. That is
/// what lets the whole app repaint when the user flips the dark-mode switch.
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.navy,
    required this.navyDeep,
    required this.orange,
    required this.amber,
    required this.green,
    required this.lavender,
    required this.iconBox,
    required this.track,
    required this.promoBg,
    required this.chipText,
    required this.textMuted,
    required this.textLabel,
    required this.textDark,
    required this.card,
    required this.border,
    required this.red,
    required this.redSoft,
    required this.greenSoft,
    required this.amberSoft,
    required this.orangeSoft,
    required this.categoryColors,
    required this.iconMuted,
    required this.mutedScale,
    required this.heroGradient,
    required this.viewfinderGradient,
    required this.panelGradient,
    required this.brandGradient,
    required this.brandSolid,
    required this.brandIcon,
    required this.heroTrack,
    required this.onNavy,
    required this.switchActive,
    required this.buttonBg,
    required this.onButton,
    this.spendBannerGradient,
    this.spendBanner,
    required this.onSpendBanner,
    required this.onSpendBannerMuted,
    required this.onSpendBannerSubtle,
    required this.spendBannerAccent,
    required this.spendBannerObjectBg,
  });

  final Color bg;
  final Color navy;
  final Color navyDeep;
  final Color orange;
  final Color amber;
  final Color green;
  final Color lavender;
  final Color iconBox;
  final Color track;
  final Color promoBg;
  final Color chipText;
  final Color textMuted;
  final Color textLabel;
  final Color textDark;
  final Color card;
  final Color border;
  final Color red;
  final Color redSoft;
  final Color greenSoft;
  final Color amberSoft;
  final Color orangeSoft;

  /// Accent colour per category, in the same order as `kCategories`.
  final List<Color> categoryColors;

  /// Neutral colour for icons drawn on [iconBox] or [card].
  final Color iconMuted;

  /// De-emphasised grey scale used by the analysis bars.
  final List<Color> mutedScale;

  /// Gradient behind the hero summary cards (total spend, prediction, header).
  final List<Color> heroGradient;

  /// Gradient behind image / receipt placeholders.
  final List<Color> viewfinderGradient;

  /// Gradient behind flat preview panels.
  final List<Color> panelGradient;

  /// Gradient behind the app logo tile.
  final List<Color> brandGradient;

  /// Solid fill for the app logo tile. When non-null it replaces
  /// [brandGradient].
  final Color? brandSolid;

  /// Colour of the glyph drawn on the app logo tile.
  final Color brandIcon;

  /// Colour of the non-highlighted bars drawn on top of [heroGradient].
  final Color heroTrack;

  /// Content colour drawn on top of a [navy] surface.
  final Color onNavy;

  /// Track colour of an enabled switch.
  final Color switchActive;

  /// Fill colour of primary/selected buttons and controls.
  final Color buttonBg;

  /// Content colour drawn on top of [buttonBg].
  final Color onButton;

  /// Background gradient of the "Pengeluaran Bulan Ini" banner. Null when the
  /// banner uses the flat [spendBanner] colour instead.
  final List<Color>? spendBannerGradient;

  /// Flat background colour of the spending banner.
  final Color? spendBanner;

  /// Primary text colour on the spending banner.
  final Color onSpendBanner;

  /// Secondary text colour on the spending banner.
  final Color onSpendBannerMuted;

  /// Text colour inside the badge on the spending banner.
  final Color onSpendBannerSubtle;

  /// Accent (dot / icon) colour on the spending banner.
  final Color spendBannerAccent;

  /// Background of the badge and icon tile that sit on the spending banner.
  final Color spendBannerObjectBg;

  /// Palette sampled from the original "01 - Home Dashboard" design.
  static const AppPalette light = AppPalette(
    bg: Color(0xFFF9F9FF),
    navy: Color(0xFF131A33),
    navyDeep: Color(0xFF151C27),
    orange: Color(0xFFFEA619),
    amber: Color(0xFF8C5D10),
    green: Color(0xFF009668),
    lavender: Color(0xFFE2E8F8),
    iconBox: Color(0xFFE7EEFE),
    track: Color(0xFFE7EEFE),
    promoBg: Color(0xFFE8EBF8),
    chipText: Color(0xFF6B7280),
    textMuted: Color(0xFF8A8D97),
    textLabel: Color(0xFF5B6472),
    textDark: Color(0xFF151C27),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFEDEFF7),
    red: Color(0xFFE5484D),
    redSoft: Color(0xFFFCE9EA),
    greenSoft: Color(0xFFE1F4EC),
    amberSoft: Color(0xFFFCEFD8),
    orangeSoft: Color(0xFFFDF0DC),
    categoryColors: <Color>[
      Color(0xFFFEA619),
      Color(0xFF4C8DF6),
      Color(0xFF8C5D10),
      Color(0xFFB45BCB),
      Color(0xFF009668),
      Color(0xFF3D445C),
      Color(0xFF5B6472),
      Color(0xFFDB6B8C),
      Color(0xFF8A8D97),
    ],
    iconMuted: Color(0xFF3A4152),
    mutedScale: <Color>[
      Color(0xFF3D445C),
      Color(0xFF686F84),
      Color(0xFF9299AD),
    ],
    heroGradient: <Color>[
      Color(0xFF141A34),
      Color(0xFF1B2036),
      Color(0xFF3B3730),
    ],
    viewfinderGradient: <Color>[
      Color(0xFF141A34),
      Color(0xFF1B2036),
      Color(0xFF2A2E3F),
    ],
    panelGradient: <Color>[
      Color(0xFF141A34),
      Color(0xFF232A46),
    ],
    brandGradient: <Color>[
      Color(0xFF141A34),
      Color(0xFF232A46),
    ],
    brandSolid: null,
    brandIcon: Color(0xFFFEA619),
    heroTrack: Color(0xFFDCE2F3),
    onNavy: Color(0xFFFEA619),
    switchActive: Color(0xFFFEA619),
    buttonBg: Color(0xFF131A33),
    onButton: Color(0xFFFFFFFF),
    spendBannerGradient: <Color>[
      Color(0xFF141A34),
      Color(0xFF1B2036),
      Color(0xFF3B3730),
    ],
    onSpendBanner: Color(0xFFFFFFFF),
    onSpendBannerMuted: Color(0xFF9BA3B5),
    onSpendBannerSubtle: Color(0xFFC7CBD6),
    spendBannerAccent: Color(0xFFFEA619),
    spendBannerObjectBg: Color(0x1AFFFFFF),
  );
  /// Dark palette modelled on Instagram's dark mode: pure-black canvas, near
  /// black surfaces, white text with grey secondaries, and the signature
  /// gradient reserved for the logo and hero cards.
  static const AppPalette dark = AppPalette(
    bg: Color(0xFF000000),
    navy: Color(0xFF0095F6),
    navyDeep: Color(0xFF000000),
    orange: Color(0xFFFA7E1E),
    amber: Color(0xFFFCAF45),
    green: Color(0xFF78DE45),
    lavender: Color(0xFF262626),
    iconBox: Color(0xFF262626),
    track: Color(0xFF363636),
    promoBg: Color(0xFF1C1C1C),
    chipText: Color(0xFFE0E0E0),
    textMuted: Color(0xFFA8A8A8),
    textLabel: Color(0xFFC7C7C7),
    textDark: Color(0xFFFFFFFF),
    card: Color(0xFF1C1C1C),
    border: Color(0xFF262626),
    red: Color(0xFFED4956),
    redSoft: Color(0xFF2A1416),
    greenSoft: Color(0xFF15260E),
    amberSoft: Color(0xFF2A2110),
    orangeSoft: Color(0xFF2A1B0E),
    categoryColors: <Color>[
      Color(0xFFFA7E1E),
      Color(0xFF0095F6),
      Color(0xFFFCAF45),
      Color(0xFF962FBF),
      Color(0xFF78DE45),
      Color(0xFF4F5BD5),
      Color(0xFFD62976),
      Color(0xFFED4956),
      Color(0xFFA8A8A8),
    ],
    iconMuted: Color(0xFFA8A8A8),
    mutedScale: <Color>[
      Color(0xFF4A4A4A),
      Color(0xFF6E6E6E),
      Color(0xFF9A9A9A),
    ],
    heroGradient: <Color>[
      Color(0xFF33204A),
      Color(0xFF43214F),
      Color(0xFF522343),
    ],
    viewfinderGradient: <Color>[
      Color(0xFF121212),
      Color(0xFF1C1C1C),
      Color(0xFF262626),
    ],
    panelGradient: <Color>[
      Color(0xFF1C1C1C),
      Color(0xFF262626),
    ],
    brandGradient: <Color>[
      Color(0xFFFEDA75),
      Color(0xFFFA7E1E),
      Color(0xFFD62976),
      Color(0xFF962FBF),
      Color(0xFF4F5BD5),
    ],
    brandSolid: Color(0xFFFEA619),
    brandIcon: Color(0xFF000000),
    heroTrack: Color(0x55FFFFFF),
    onNavy: Color(0xFFFFFFFF),
    switchActive: Color(0xFFFEA619),
    buttonBg: Color(0xFFFEA619),
    onButton: Color(0xFF2A1B00),
    spendBanner: Color(0xFFFEA619),
    onSpendBanner: Color(0xFF2A1B00),
    onSpendBannerMuted: Color(0xFF5C3D00),
    onSpendBannerSubtle: Color(0xFFFEA619),
    spendBannerAccent: Color(0xFFFEA619),
    spendBannerObjectBg: Color(0xFF2A1B00),
  );
}

/// Active colour access. Getter values change when the theme is toggled, so
/// widgets must not be `const` when they read from here.
class AppColors {
  AppColors._();

  static AppPalette _palette = AppPalette.dark;

  static AppPalette get palette => _palette;

  /// Swaps the active palette. Called by the theme controller.
  static void apply(AppPalette palette) => _palette = palette;

  static Color get bg => _palette.bg;
  static Color get navy => _palette.navy;
  static Color get navyDeep => _palette.navyDeep;
  static Color get orange => _palette.orange;
  static Color get amber => _palette.amber;
  static Color get green => _palette.green;
  static Color get lavender => _palette.lavender;
  static Color get iconBox => _palette.iconBox;
  static Color get track => _palette.track;
  static Color get promoBg => _palette.promoBg;
  static Color get chipText => _palette.chipText;
  static Color get textMuted => _palette.textMuted;
  static Color get textLabel => _palette.textLabel;
  static Color get textDark => _palette.textDark;
  static Color get card => _palette.card;
  static Color get border => _palette.border;
  static Color get red => _palette.red;
  static Color get redSoft => _palette.redSoft;
  static Color get greenSoft => _palette.greenSoft;
  static Color get amberSoft => _palette.amberSoft;
  static Color get orangeSoft => _palette.orangeSoft;
  static Color get iconMuted => _palette.iconMuted;
  static List<Color> get mutedScale => _palette.mutedScale;
  static List<Color> get heroGradient => _palette.heroGradient;
  static List<Color> get viewfinderGradient => _palette.viewfinderGradient;
  static List<Color> get panelGradient => _palette.panelGradient;
  static List<Color> get brandGradient => _palette.brandGradient;
  static Color? get brandSolid => _palette.brandSolid;
  static Color get brandIcon => _palette.brandIcon;
  static Color get heroTrack => _palette.heroTrack;
  static Color get onNavy => _palette.onNavy;
  static Color get switchActive => _palette.switchActive;
  static Color get buttonBg => _palette.buttonBg;
  static Color get onButton => _palette.onButton;
  static List<Color>? get spendBannerGradient => _palette.spendBannerGradient;
  static Color? get spendBanner => _palette.spendBanner;
  static Color get onSpendBanner => _palette.onSpendBanner;
  static Color get onSpendBannerMuted => _palette.onSpendBannerMuted;
  static Color get onSpendBannerSubtle => _palette.onSpendBannerSubtle;
  static Color get spendBannerAccent => _palette.spendBannerAccent;
  static Color get spendBannerObjectBg => _palette.spendBannerObjectBg;

  /// Fixed avatar colours (WhatsApp-style) that ignore the active theme.
  static const List<Color> avatarColors = <Color>[
    Color(0xFF1FA855),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
  ];

  /// Deterministic avatar colour for [seed], independent of the active palette
  /// so the avatar stays the same in light and dark mode.
  static Color avatarColor(String seed) {
    int hash = 0;
    for (final int unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return avatarColors[hash % avatarColors.length];
  }
}
