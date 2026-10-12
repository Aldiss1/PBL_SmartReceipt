import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Output of the Indonesian text preprocessing pipeline.
///
/// Keeping every stage visible makes the preprocessing auditable: the review
/// screen and the evaluation report can show exactly what the classifier saw.
class ProcessedText {
  const ProcessedText({
    required this.raw,
    required this.cleaned,
    required this.tokens,
    required this.normalizedTokens,
    required this.normalized,
  });

  /// The original input, untouched.
  final String raw;

  /// Lower-cased, unicode-normalized, punctuation/currency-stripped text.
  final String cleaned;

  /// Word tokens extracted from [cleaned], before abbreviation expansion.
  final List<String> tokens;

  /// Tokens after slang/abbreviation normalization, with stopwords removed.
  final List<String> normalizedTokens;

  /// [normalizedTokens] joined by single spaces; ready for vectorization.
  final String normalized;

  bool get isEmpty => normalizedTokens.isEmpty;
}

/// Indonesian text preprocessing for receipt item names and OCR lines.
///
/// Stages, in order:
///   1. **Cleaning** – unicode cleanup, drop receipt noise (amounts, barcodes,
///      percentages), lower-case, collapse symbols/whitespace.
///   2. **Tokenization** – split on non-alphanumerics, drop 1-char noise.
///   3. **Normalization** – expand Indonesian slang/abbreviations
///      (indomie → mie instan, aqua → air mineral, …), strip measurement
///      units and quantity multipliers, then drop stopwords.
///
/// The pipeline is deterministic and offline. Rule tables live in
/// `assets/text_normalization_id.json` so linguists can extend them without
/// touching Dart code; a built-in fallback keeps the app working when the asset
/// is unavailable (e.g. in pure unit tests).
class IndonesianTextPreprocessor {
  IndonesianTextPreprocessor();

  Map<String, String> _abbreviations = defaultAbbreviations;
  Set<String> _stopwords = defaultStopwords;
  Set<String> _units = defaultUnits;
  bool _loadedFromAsset = false;

  bool get isLoadedFromAsset => _loadedFromAsset;

  /// Loads the rule tables from `assets/`. Falls back to the built-in defaults
  /// on any failure so preprocessing never becomes a hard dependency.
  Future<void> loadFromAsset({
    String assetPath = 'assets/text_normalization_id.json',
  }) async {
    if (_loadedFromAsset) {
      return;
    }
    try {
      final String raw = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      loadFromMap(json);
      _loadedFromAsset = true;
    } catch (_) {
      // Keep built-in defaults; preprocessing stays functional.
    }
  }

  /// Applies rule tables from an already-decoded map. Testable without assets.
  void loadFromMap(Map<String, dynamic> json) {
    final Object? abbreviations = json['abbreviations'];
    if (abbreviations is Map && abbreviations.isNotEmpty) {
      _abbreviations = <String, String>{
        for (final MapEntry<Object?, Object?> e in abbreviations.entries)
          normalizeKey(e.key.toString()): e.value.toString(),
      };
    }
    final Object? stopwords = json['stopwords'];
    if (stopwords is List && stopwords.isNotEmpty) {
      _stopwords = stopwords.map((Object? e) => normalizeKey(e.toString())).toSet();
    }
    final Object? units = json['units'];
    if (units is List && units.isNotEmpty) {
      _units = units.map((Object? e) => normalizeKey(e.toString())).toSet();
    }
  }

  /// Runs the full pipeline over [input].
  ProcessedText process(String input) {
    final String cleaned = clean(input);
    final List<String> tokens = tokenize(cleaned);
    final List<String> normalizedTokens = normalizeTokens(tokens);
    return ProcessedText(
      raw: input,
      cleaned: cleaned,
      tokens: tokens,
      normalizedTokens: normalizedTokens,
      normalized: normalizedTokens.join(' '),
    );
  }

  /// Convenience one-shot: returns just the normalized string.
  String normalize(String input) => process(input).normalized;

  // ---------------------------------------------------------------------------
  // Stage 1 — cleaning
  // ---------------------------------------------------------------------------

  /// Receipt noise that carries no category signal.
  static final RegExp _currency = RegExp(
    r'(?:rp\.?\s*)?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?',
  );

  /// A number glued to a unit, e.g. "600ml", "250s", "5kg", "2x", "12pcs".
  ///
  /// OCR almost always writes sizes without a space, so this must run before
  /// the plain-number rule — otherwise "600" is stripped and the unit token
  /// ("ml") survives to pollute the features.
  static final RegExp _numberUnit = RegExp(
    r'\b\d+\s*(?:x|pcs|pc|pck|ctn|dus|box|botol|bks|bungkus|sachet|sct|'
    r'kg|gr|gram|ml|ltr|liter|ons|papan|rim|set|pack|pak|lusin|'
    r'mah|mah|gb|tb|watt|w|v|volt|s|l|gr|g|ma|mm|cm|m)\b',
  );
  static final RegExp _plainNumber = RegExp(r'\b\d+\b');
  static final RegExp _percent = RegExp(r'\d+\s*%');
  static final RegExp _unitNoise = RegExp(
    r'\b(?:x|qty|pcs|pc|pck|ctn|dus|box|botol|bks|bungkus|sachet|sct|'
    r'kg|gr|gram|ml|ltr|liter|ons|papan|rim|set|pack|pak|lusin)\b',
  );
  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]');
  static final RegExp _repeated = RegExp(r'(.)\1{2,}');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Lower-cases, strips currency/quantities/units and non-alphanumerics.
  String clean(String input) {
    String text = input.toLowerCase();

    // Normalize common unicode look-alikes that OCR likes to emit.
    text = text
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('×', 'x');

    // Drop money, sizes and percentages before anything else: they never carry
    // category signal.
    text = text.replaceAll(_percent, ' ');
    text = text.replaceAll(_currency, ' ');
    text = text.replaceAll(_numberUnit, ' ');
    text = text.replaceAll(_unitNoise, ' ');
    text = text.replaceAll(_plainNumber, ' ');

    // Collapse OCR stutter like "aquaaa" -> "aqua" (>2 repeats).
    text = text.replaceAllMapped(
      _repeated,
      (Match m) => '${m.group(1)}${m.group(1)}',
    );

    text = text.replaceAll(_nonAlnum, ' ');
    return text.replaceAll(_spaces, ' ').trim();
  }

  // ---------------------------------------------------------------------------
  // Stage 2 — tokenization
  // ---------------------------------------------------------------------------

  /// Splits [cleaned] text into word tokens, dropping 1-character fragments.
  List<String> tokenize(String cleaned) {
    if (cleaned.trim().isEmpty) {
      return const <String>[];
    }
    return cleaned
        .split(_spaces)
        .where((String t) => t.length >= 2)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Stage 3 — normalization
  // ---------------------------------------------------------------------------

  /// Expands abbreviations, applies multi-word rules, then removes stopwords.
  List<String> normalizeTokens(List<String> tokens) {
    if (tokens.isEmpty) {
      return const <String>[];
    }

    // Multi-word abbreviation keys (e.g. "mie instan") need the joined form.
    final String joined = tokens.join(' ');
    final String expanded = _applyMultiWordRules(joined);

    final List<String> result = <String>[];
    for (final String token in expanded.split(_spaces)) {
      if (token.length < 2) {
        continue;
      }
      if (_units.contains(token) || _stopwords.contains(token)) {
        continue;
      }
      final String mapped = _abbreviations[token] ?? token;
      result.addAll(
        mapped.split(_spaces).where((String t) => t.length >= 2),
      );
    }
    return result;
  }

  String _applyMultiWordRules(String text) {
    String out = text;
    for (final MapEntry<String, String> rule in _abbreviations.entries) {
      if (rule.key.contains(' ') && out.contains(rule.key)) {
        out = out.replaceAll(rule.key, rule.value);
      }
    }
    return out;
  }

  static String normalizeKey(String value) =>
      value.toLowerCase().replaceAll(_spaces, ' ').trim();

  // ---------------------------------------------------------------------------
  // Built-in defaults (used when the asset is missing)
  // ---------------------------------------------------------------------------

  /// Indonesian receipt slang / abbreviations → canonical form.
  ///
  /// Multi-word keys are matched against the joined token string first, so
  /// "mie instan" style phrases work too.
  static const Map<String, String> defaultAbbreviations =
      <String, String>{
    // groceries & staples
    'indomie': 'mie instan',
    'mie': 'mie instan',
    'mie instan': 'mie instan',
    'aqua': 'air mineral',
    'le mineral': 'air mineral',
    'aqua galon': 'air mineral',
    'sabun': 'sabun',
    'pasta gigi': 'pasta gigi',
    'pepsodent': 'pasta gigi',
    'odol': 'pasta gigi',
    'rinso': 'deterjen',
    'softergent': 'deterjen',
    'molto': 'pewangi',
    'sunlight': 'sabun cuci',
    'sunlight cair': 'sabun cuci',
    'tissue': 'tisu',
    'paseo': 'tisu',
    'paster': 'tisu',
    'minyak goreng': 'minyak goreng',
    'minyak': 'minyak goreng',
    'beras': 'beras',
    'tepung': 'tepung',
    'gulaku': 'gula',
    'gula': 'gula',
    'susu ultra': 'susu',
    'ultra': 'susu',
    'sosro': 'teh',
    'teh botol': 'teh',
    'teh': 'teh',
    'kopi': 'kopi',
    'kapal api': 'kopi',
    'mizone': 'minuman isotonik',
    'pocari': 'minuman isotonik',
    'yakult': 'yogurt',
    // household / beauty brands
    'lifebuoy': 'sabun',
    'shampoo': 'sampo',
    'pantene': 'sampo',
    'clear': 'sampo',
    'nivea': 'lotion',
    'garnier': 'lotion',
    'wardah': 'kosmetik',
    'pampers': 'popok',
    'mamy poko': 'popok',
    'soflin': 'pembalut',
    'charm': 'pembalut',
    // health
    'paracetamol': 'obat',
    'panadol': 'obat',
    'bodrex': 'obat',
    'tolak angin': 'obat',
    'betadine': 'obat',
    'hansaplast': 'plester',
    'hansaplas': 'plester',
    'vitamin': 'vitamin',
    'suplemen': 'vitamin',
    // transport / utilities
    'pertalite': 'bensin',
    'pertamax': 'bensin',
    'pertamina': 'bensin',
    'solar': 'bensin',
    'bbm': 'bensin',
    'gojek': 'transportasi online',
    'grab': 'transportasi online',
    'ojol': 'transportasi online',
    'ekstra': 'extra',
    'pln': 'listrik',
    'token listrik': 'listrik',
    'indihome': 'internet',
    'telkom': 'internet',
    'pulsa': 'pulsa',
    'kuota': 'internet',
    // electronics / fashion
    'powerbank': 'power bank',
    'flashdisk': 'flash disk',
    'earphone': 'earphone',
    'headset': 'earphone',
    'kaos': 'baju',
    'kemeja': 'baju',
    'kaus': 'baju',
    'jeans': 'celana',
    'sandal': 'sandal',
    'sepatu': 'sepatu',
  };

  /// Words that carry no category signal inside a receipt line.
  static const Set<String> defaultStopwords = <String>{
    'dan', 'atau', 'dengan', 'untuk', 'dari', 'ke', 'di', 'pada', 'yang',
    'isi', 'per', 'buah', 'jenis', 'kemasan', 'merk', 'merek', 'ukuran',
    'warna', 'model', 'tipe', 'type', 'varian', 'rasa', 'seri',
    'plus', 'bonus', 'gratis', 'free', 'new', 'baru', 'promo', 'diskon',
    'item', 'total', 'subtotal', 'jumlah', 'harga', 'qty', 'struk', 'nota',
    'kasir', 'toko', 'terima', 'kasih',
  };

  /// Measurement / packaging tokens removed during normalization.
  static const Set<String> defaultUnits = <String>{
    'kg', 'gr', 'gram', 'ons', 'ml', 'ltr', 'liter', 'cc',
    'pcs', 'pc', 'pck', 'pack', 'pak', 'ctn', 'dus', 'box',
    'botol', 'bks', 'bungkus', 'sachet', 'sct', 'lusin', 'rim', 'set',
  };
}
