/// Expands common minimarket receipt abbreviations to improve classifier accuracy.
///
/// Indonesian minimarket receipts abbreviate product names aggressively to fit
/// within the narrow thermal-print column. Combined with OCR errors (dropped
/// letters, misreads), the item text often bears little resemblance to the
/// full product name the TF-IDF model was trained on.
///
/// This expander bridges the gap by restoring the most frequent abbreviations
/// *before* the text reaches the classifier. Because the model uses char
/// n-grams, even a partial restoration (e.g. `GRG` → `GORENG`) provides enough
/// signal for correct classification.
///
/// The table is ordered so longer patterns are checked first (a prefix should
/// never shadow a longer match).
class OcrAbbreviationExpander {
  OcrAbbreviationExpander();

  // -------------------------------------------------------------------------
  // Brand abbreviations → full brand name
  // -------------------------------------------------------------------------

  /// Whole-token brand abbreviations. Matched case-insensitively as exact words.
  static const Map<String, String> _brandAbbreviations = <String, String>{
    // Makanan
    'GG': 'GUDANG GARAM',
    'FF': 'FRISIAN FLAG',
    'ABC': 'ABC',
    'SGM': 'SGM',
    'SLI': 'SARIMI',
    'INDM': 'INDOMIE',
    'SDAP': 'SEDAAP',
    'MIE SDH': 'MINYAK SEDERHANA',
    'S/ROTI': 'SARI ROTI',       // Indomaret uses S/ prefix for Sari Roti
    'SROTI': 'SARI ROTI',
    'S/MIE': 'SUPERMI',
    'S/MKN': 'SNACK MAKANAN',
    'CHIKI': 'CHIKI',
    'QTLA': 'QTELA',
    // Minuman
    'LE MIN': 'LE MINERAL',
    'AQ': 'AQUA',
    'ADES': 'ADES',
    'TCH': 'TEH CELUP',
    'ULTRMLK': 'ULTRA MILK',
    'SSRO': 'SOSRO',
    // Perawatan
    'LFB': 'LIFEBUOY',
    'PPSD': 'PEPSODENT',
    'SNSLK': 'SUNSILK',
    'DVSL': 'DOVE SILK',
    'DVE': 'DOVE',
    'PNTNE': 'PANTENE',
    // Rumah Tangga
    'RNSO': 'RINSO',
    'RDSO': 'RINSO',
    'SNLGT': 'SUNLIGHT',
    'SUNLGT': 'SUNLIGHT',
    'MLTO': 'MOLTO',
    'PSO': 'PASEO',
    // Rokok
    'SMPERNA': 'SAMPOERNA',
    'DJRM': 'DJARUM',
    'DJSR': 'DJARUM SUPER',
    'LA': 'LA LIGHTS',
    'MLD': 'MILD',
    'FLT': 'FILTER',
    'SKT': 'SIGARET KRETEK TANGAN',
    'SPR': 'SUPER',
    // Transportasi
    'PRTALITE': 'PERTALITE',
    'PRTMAX': 'PERTAMAX',
    // Elektronik
    'BT': 'BLUETOOTH',
    'HP': 'HANDPHONE',
  };


  // -------------------------------------------------------------------------
  // Generic word abbreviations → full word
  // -------------------------------------------------------------------------

  /// Common word-level abbreviations seen on thermal receipts.
  static const Map<String, String> _wordAbbreviations = <String, String>{
    'GRG': 'GORENG',
    'SPL': 'SPECIAL',
    'SPCL': 'SPECIAL',
    'BTL': 'BOTOL',
    'SCH': 'SACHET',
    'SCHT': 'SACHET',
    'PCK': 'PACK',
    'PCS': 'PCS',
    'SOS': 'SOSIS',
    'BKR': 'BESAR',
    'KCL': 'KECIL',
    'SDG': 'SEDANG',
    'IST': 'INSTANT',
    'INST': 'INSTANT',
    'KRM': 'KRIM',
    'KSRY': 'KASURI',
    'VAN': 'VANILLA',
    'CHOC': 'CHOCOLATE',
    'CHCLT': 'CHOCOLATE',
    'STRWB': 'STRAWBERRY',
    'STRW': 'STRAWBERRY',
    'ORI': 'ORIGINAL',
    'ORGNL': 'ORIGINAL',
    'COR': 'CAIR',
    'NDA': 'NODA',
    'PWR': 'POWDER',
    'BW': 'BODY WASH',
    'LQ': 'LIQUID',
    'SHM': 'SHAMPOO',
    'SHMP': 'SHAMPOO',
    'SMPO': 'SAMPO',
    'DTRGN': 'DETERJEN',
    'RFLF': 'REFILL',
    'RFL': 'REFILL',
    'TP': 'TERPASANG',
    'BRG': 'BARANG',
    'MNK': 'MAKAN',
    'MKN': 'MAKANAN',
    'MNMN': 'MINUMAN',
    'KPI': 'KOPI',
    'KPL': 'KAPAL',
    'TELOR': 'TELUR',
    'AYM': 'AYAM',
    'MDN': 'MEDAN',
    'BWG': 'BAWANG',
    'GRM': 'GRAM',
    'LTR': 'LITER',
  };

  /// Known prefixes used by Indomaret. `S/` means the brand name follows, but
  /// OCR often merges the prefix with the next word: `S/ROTI KRIM` = Sari Roti
  /// Krim. When the combined token isn't in [_brandAbbreviations] we strip the
  /// prefix so the remaining text can still be classified.
  static final RegExp _slashPrefix = RegExp(r'^[A-Za-z]/');

  /// Expands abbreviations in [ocrText] and returns the expanded form.
  ///
  /// The original text is preserved as-is when no abbreviation is found.
  /// Expansion is case-insensitive; the result is returned in upper case to
  /// match the thermal-print convention.
  String expand(String ocrText) {
    if (ocrText.trim().isEmpty) {
      return ocrText;
    }

    List<String> tokens = ocrText.split(RegExp(r'\s+'));
    final List<String> result = <String>[];

    for (int i = 0; i < tokens.length; i++) {
      final String token = tokens[i].toUpperCase();

      // Try two-word brand match first, e.g. "LE MIN" → "LE MINERAL".
      if (i + 1 < tokens.length) {
        final String twoWord =
            '$token ${tokens[i + 1].toUpperCase()}';
        final String? brandMatch = _brandAbbreviations[twoWord];
        if (brandMatch != null) {
          result.add(brandMatch);
          i++; // skip next token
          continue;
        }
      }

      // Single-token brand match.
      final String? brand = _brandAbbreviations[token];
      if (brand != null) {
        result.add(brand);
        continue;
      }

      // Handle Indomaret `S/XXX` prefix: strip the letter+slash and look up
      // both the full token (e.g. `S/ROTI` → `SARI ROTI`) and the tail (e.g.
      // `ROTI`). If neither matches, keep the tail so the classifier at least
      // sees the product word without the opaque prefix.
      if (_slashPrefix.hasMatch(token) && token.length > 2) {
        final String withSlash = token; // e.g. S/ROTI
        final String? slashBrand = _brandAbbreviations[withSlash];
        if (slashBrand != null) {
          result.add(slashBrand);
          continue;
        }
        // Strip the prefix and keep the meaningful part.
        result.add(token.substring(2)); // ROTI
        continue;
      }

      // Generic word abbreviation.
      final String? word = _wordAbbreviations[token];
      if (word != null) {
        result.add(word);
        continue;
      }

      // No match — keep original.
      result.add(tokens[i]);
    }

    return result.join(' ');
  }
}
