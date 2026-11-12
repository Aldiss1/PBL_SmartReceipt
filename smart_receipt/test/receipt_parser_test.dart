import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/ocr_raw_text.dart';
import 'package:smart_receipt/ocr/ocr_text_corrector.dart';
import 'package:smart_receipt/ocr/receipt_parser.dart';

/// Builds an [OcrRawResult] from plain lines, the way ML Kit hands them over.
OcrRawResult _raw(List<String> lines) => OcrRawResult(
      lines: <OcrLine>[
        for (int i = 0; i < lines.length; i++)
          OcrLine(
            text: lines[i],
            left: 0,
            top: i * 20.0,
            right: 100,
            bottom: i * 20.0 + 18,
          ),
      ],
      fullText: lines.join('\n'),
    );

/// Builds an [OcrRawResult] the way ML Kit returns a table: every cell is its
/// own `TextLine`, with a bounding box that reflects its column.
OcrRawResult _rawTable(List<List<String>> rows) {
  const double nameLeft = 20;
  const double nameRight = 280;
  const double qtyLeft = 300;
  const double qtyRight = 325;
  const double unitLeft = 340;
  const double unitRight = 405;
  const double totalLeft = 430;
  const double totalRight = 505;

  final List<OcrLine> lines = <OcrLine>[];
  final StringBuffer text = StringBuffer();
  double top = 0;

  void add(String value, double left, double right) {
    if (value.isEmpty) {
      return;
    }
    lines.add(OcrLine(
      text: value,
      left: left,
      top: top,
      right: right,
      bottom: top + 18,
    ));
    text.writeln(value);
  }

  for (final List<String> row in rows) {
    if (row.length == 1) {
      add(row[0], nameLeft, nameRight);
    } else if (row.length == 2) {
      // label + amount, e.g. "TOTAL :" + "33,900"
      add(row[0], nameLeft, nameRight);
      add(row[1], totalLeft, totalRight);
    } else {
      // name, qty, unit, total
      add(row[0], nameLeft, nameRight);
      add(row[1], qtyLeft, qtyRight);
      add(row[2], unitLeft, unitRight);
      add(row[3], totalLeft, totalRight);
    }
    top += 24;
  }

  return OcrRawResult(lines: lines, fullText: text.toString());
}

/// A real Indomaret receipt: dotted date, column layout without `x`, a
/// supplier header above the shop, and summary lines such as `HARGA JUAL`.
const List<String> _indomaretRows = <String>[
  'PT.INDING FOOD',
  'JL.LETJEN S.PARMAN-SUMEDANG',
  'KM.20 - JABAR SUM',
  'NPWP:22.131.107.6-446.001',
  'JATINANGOR KM.20-SUMEDA',
  '14.09.16- 06:46',
  '2.0. 31 914115/ALIA MU/01',
  'S/ROTI KRIM KEJU 72G 4 4500 18,000',
  'CIMORY MIX BERRY 22S 1 8500 8,500',
  'CAFELA ESPRESSO 200ML 1 3500 3,500',
  'FF LOW FAT VAN 225 1 5200 5,200',
  'PLASTIK SDG 1 1 1',
  'DISKON : (1)',
  'HARGA JUAL : 35,200',
  'DISKON FRISIAN FLAG : (1,300)',
  'TOTAL : 33,900',
  'TUNAI : 40,000',
  'KEMBALI : 6,100',
  'ANDA HEMAT : 1,300',
  'TERIMA KASIH. SELAMAT BELANJA KEMBALI',
  '======= LAYANAN KONSUMEN INDOMARET =======',
  'CALL 1500580 SMS : 0816 500 580',
  'EMAIL : KONTAK@INDOMARET.CO.ID',
  'WWW.INDOMARET.CO.ID/PROMO',
];

/// The same receipt when ML Kit splits every table cell onto its own line.
const List<String> _indomaretColumns = <String>[
  'PT.INDING FOOD',
  'JL.LETJEN S.PARMAN-SUMEDANG',
  'JATINANGOR KM.20-SUMEDA',
  '14.09.16- 06:46',
  '2.0. 31 914115/ALIA MU/01',
  '18,000',
  '4 4500',
  'S/ROTI KRIM KEJU 72G',
  '8,500',
  '1 8500',
  'CIMORY MIX BERRY 22S',
  '3,500',
  '1 3500',
  'CAFELA ESPRESSO 200ML',
  '5,200',
  '1 5200',
  'FF LOW FAT VAN 225',
  '1',
  '1 1',
  'PLASTIK SDG',
  'HARGA JUAL : 35,200',
  'TOTAL : 33,900',
  'TUNAI : 40,000',
  'KEMBALI : 6,100',
  '======= LAYANAN KONSUMEN INDOMARET =======',
];

const List<String> _expectedNames = <String>[
  'S/ROTI KRIM KEJU 72G',
  'CIMORY MIX BERRY 22S',
  'CAFELA ESPRESSO 200ML',
  'FF LOW FAT VAN 225',
  'PLASTIK SDG',
];

const List<int> _expectedQty = <int>[4, 1, 1, 1, 1];
const List<int> _expectedPrice = <int>[4500, 8500, 3500, 5200, 1];

void main() {
  group('ReceiptParser on a real Indomaret receipt', () {
    final ReceiptParser parser = ReceiptParser();

    for (final (String label, List<String> lines) in <(String, List<String>)>[
      ('single-line rows', _indomaretRows),
      ('column-split rows', _indomaretColumns),
    ]) {
      test('$label: extracts every item with its quantity and price', () {
        final ParsedReceipt p = parser.parse(_raw(lines));

        expect(p.items.map((ParsedItem i) => i.name).toList(), _expectedNames);
        expect(p.items.map((ParsedItem i) => i.qty).toList(), _expectedQty);
        expect(p.items.map((ParsedItem i) => i.price).toList(), _expectedPrice);
      });

      test('$label: uses the printed total, not the sum of columns', () {
        final ParsedReceipt p = parser.parse(_raw(lines));
        expect(p.total, 33900);
      });

      test('$label: reads the dotted date and colon time', () {
        final ParsedReceipt p = parser.parse(_raw(lines));
        expect(p.date, DateTime(2016, 9, 14, 6, 46));
      });
    }

    test('prefers the merchant name printed in the footer over the supplier',
        () {
      final ParsedReceipt p = parser.parse(_raw(_indomaretRows));
      expect(p.store, 'Indomaret');
    });

    test('does not turn summary or metadata lines into items', () {
      final ParsedReceipt p = parser.parse(_raw(_indomaretRows));
      final List<String> names =
          p.items.map((ParsedItem i) => i.name.toUpperCase()).toList();

      // Register/cashier metadata ("2.0. 31 914115/ALIA MU/01").
      expect(names.any((String n) => n.contains('914115')), isFalse);
      // Summary lines that used to be parsed as a 35,200 item.
      expect(names.any((String n) => n.contains('HARGA JUAL')), isFalse);
      expect(names.any((String n) => n.contains('DISKON')), isFalse);
      expect(names.any((String n) => n.contains('TOTAL')), isFalse);
    });
  });

  group('ReceiptParser with ML Kit table geometry', () {
    final ReceiptParser parser = ReceiptParser();

    /// The same Indomaret receipt as `_indomaretRows`, but every table cell is
    /// its own OCR line with a bounding box — which is what ML Kit really
    /// emits for this layout.
    final List<List<String>> tableRows = <List<String>>[
      <String>['PT.INDING FOOD'],
      <String>['JL.LETJEN S.PARMAN-SUMEDANG'],
      <String>['KM.20 - JABAR SUM'],
      <String>['NPWP:22.131.107.6-446.001'],
      <String>['JATINANGOR KM.20-SUMEDA'],
      <String>['14.09.16- 06:46'],
      <String>['2.0. 31 914115/ALIA MU/01'],
      <String>['S/ROTI KRIM KEJU 72G', '4', '4500', '18,000'],
      <String>['CIMORY MIX BERRY 22S', '1', '8500', '8,500'],
      <String>['CAFELA ESPRESSO 200ML', '1', '3500', '3,500'],
      <String>['FF LOW FAT VAN 225', '1', '5200', '5,200'],
      <String>['PLASTIK SDG', '1', '1', '1'],
      <String>['DISKON :', '(1)'],
      <String>['HARGA JUAL :', '35,200'],
      <String>['DISKON FRISIAN FLAG :', '(1,300)'],
      <String>['TOTAL :', '33,900'],
      <String>['TUNAI :', '40,000'],
      <String>['KEMBALI :', '6,100'],
      <String>['ANDA HEMAT :', '1,300'],
      <String>['TERIMA KASIH. SELAMAT BELANJA KEMBALI'],
      <String>['======= LAYANAN KONSUMEN INDOMARET ======='],
      <String>['CALL 1500580 SMS : 0816 500 580'],
      <String>['EMAIL : KONTAK@INDOMARET.CO.ID'],
      <String>['WWW.INDOMARET.CO.ID/PROMO'],
    ];

    test('assigns each price to the right item', () {
      final ParsedReceipt p = parser.parse(_rawTable(tableRows));

      expect(p.items.map((ParsedItem i) => i.name).toList(), _expectedNames);
      expect(p.items.map((ParsedItem i) => i.qty).toList(), _expectedQty);
      expect(p.items.map((ParsedItem i) => i.price).toList(), _expectedPrice);
      expect(
        p.items.map((ParsedItem i) => i.subtotal).toList(),
        <int>[18000, 8500, 3500, 5200, 1],
      );
    });

    test('reads the printed total, not the sum of the items', () {
      final ParsedReceipt p = parser.parse(_rawTable(tableRows));
      expect(p.total, 33900);
      expect(p.paymentMethod, 'Tunai');
    });

    test('reconciles item sum with the printed total through discounts', () {
      final ParsedReceipt p = parser.parse(_rawTable(tableRows));
      // 18,000 + 8,500 + 3,500 + 5,200 + 1 = 35,201
      expect(p.itemsTotal, 35201);
      // DISKON (1) + DISKON FRISIAN FLAG (1,300) = 1,301
      expect(p.discountTotal, 1301);
      expect(p.total + p.discountTotal, p.itemsTotal);
      expect(p.difference, -1301);
      expect(p.totalFromReceipt, isTrue);
      // The receipt adds up, so nothing should be flagged for the user.
      expect(p.warnings, isEmpty);
    });

    test('label and amount on separate lines still resolve', () {
      // Same receipt, but OCR put the total's value on its own line.
      final List<List<String>> split = <List<String>>[
        for (final List<String> row in tableRows)
          if (row.length == 2 && row[0].startsWith('TOTAL'))
            ...<List<String>>[
              <String>['TOTAL :'],
              <String>[row[1]],
            ]
          else
            row,
      ];
      final ParsedReceipt p = parser.parse(_rawTable(split));
      expect(p.total, 33900);
    });

    test('geometry that carries no layout falls back to text parsing', () {
      // Every line shares one box: no columns to group by.
      final ParsedReceipt p = parser.parse(_raw(_indomaretRows));
      expect(p.items.map((ParsedItem i) => i.name).toList(), _expectedNames);
      expect(p.total, 33900);
    });
  });

  group('ReceiptParser repairs OCR damage', () {
    final ReceiptParser parser = ReceiptParser();

    ParsedReceipt parseWith(List<String> lines) => parser.parse(_raw(lines));

    test('joins amounts split at the thousands separator', () {
      final ParsedReceipt p = parseWith(<String>[
        'INDOMARET',
        'S/ROTI KRIM KEJU 72G 4 4500 18, 000',
        'CIMORY MIX BERRY 22S 1 8500 8, 500',
        'PLASTIK SDG 1 1 1',
        'TOTAL : 27, 501',
      ]);

      expect(p.items.map((ParsedItem i) => i.name).toList(), <String>[
        'S/ROTI KRIM KEJU 72G',
        'CIMORY MIX BERRY 22S',
        'PLASTIK SDG',
      ]);
      expect(p.items.map((ParsedItem i) => i.subtotal).toList(),
          <int>[18000, 8500, 1]);
      expect(p.total, 27501);
    });

    test('joins a line total split across two OCR tokens', () {
      final ParsedReceipt p = parseWith(<String>[
        'INDOMARET',
        'CIMORY MIX BERRY 22S 1 8500 8, 500',
        'TOTAL : 8, 500',
      ]);

      expect(p.items.single.subtotal, 8500);
      expect(p.items.single.price, 8500);
      expect(p.total, 8500);
    });

    test('recognises a merchant name mangled by OCR', () {
      final ParsedReceipt p = parseWith(<String>[
        'Sndon Oomane',
        'JATINANGOR KM. 20-SUMEDA',
        'PLASTIK SDG 1 1 1',
        'CALL 1500580 SUMEN INDOMAREMBALI',
      ]);

      expect(p.store, 'Indomaret');
    });
  });

  group('ReceiptParser with column-block OCR order', () {
    final ReceiptParser parser = ReceiptParser();

    /// The exact failure mode seen on a real device: ML Kit returns the receipt
    /// **block by block**, so every product name arrives before any number.
    /// Only the bounding boxes connect `S/ROTI...` to `4`, `4500`, `18,000`.
    test('pairs names and numbers from geometry, not text order', () {
      const List<String> names = <String>[
        'S/ROTI KRIM KEJU 72G',
        'CIMORY MIX BERRY 225',
        'CAFELA EXPRESO 200ML',
        'FF LOW FAT VAN 225',
        'PLASTIK SDG',
      ];
      const List<String> qty = <String>['4', '1', '1', '1', '1'];
      const List<String> unit = <String>['4500', '8500', '3500', '5200', '1'];
      const List<String> total = <String>[
        '18, 000',
        '8,',
        '3, 500',
        '5, 200',
        '1',
      ];

      final List<OcrLine> lines = <OcrLine>[];
      void add(String text, double left, double right, int row) {
        lines.add(OcrLine(
          text: text,
          left: left,
          top: 100 + row * 30.0,
          right: right,
          bottom: 100 + row * 30.0 + 20,
        ));
      }

      // Header, then the name column, then each numeric column — the order ML
      // Kit actually emits on device.
      add('Sndon Oomane', 40, 400, -2);
      add('JATINANGOR KM. 20-SUMEDA', 40, 400, -1);
      for (int i = 0; i < names.length; i++) {
        add(names[i], 40, 400, i);
      }
      for (int i = 0; i < qty.length; i++) {
        add(qty[i], 420, 460, i);
      }
      for (int i = 0; i < unit.length; i++) {
        add(unit[i], 470, 560, i);
      }
      for (int i = 0; i < total.length; i++) {
        // "8," and "500" land on separate lines but the same row.
        if (total[i] == '8,') {
          add('8,', 570, 600, i);
          add('500', 605, 680, i);
        } else {
          add(total[i], 570, 680, i);
        }
      }
      add('DISKON :', 40, 300, names.length);
      add('TOTAL :', 40, 300, names.length + 1);
      add('33, 900', 570, 680, names.length + 1);
      add('TUNAI :', 40, 300, names.length + 2);
      add('40', 570, 680, names.length + 2);

      final ParsedReceipt p =
          parser.parse(OcrRawResult(lines: lines, fullText: ''));

      expect(p.items.map((ParsedItem i) => i.name).toList(), <String>[
        'S/ROTI KRIM KEJU 72G',
        'CIMORY MIX BERRY 225',
        'CAFELA EXPRESO 200ML',
        'FF LOW FAT VAN 225',
        'PLASTIK SDG',
      ]);
      expect(p.items.map((ParsedItem i) => i.qty).toList(),
          <int>[4, 1, 1, 1, 1]);
      expect(p.items.map((ParsedItem i) => i.price).toList(),
          <int>[4500, 8500, 3500, 5200, 1]);
      expect(p.items.map((ParsedItem i) => i.subtotal).toList(),
          <int>[18000, 8500, 3500, 5200, 1]);
    });
  });

  group('ReceiptParser on ragged ML Kit columns', () {
    final ReceiptParser parser = ReceiptParser();

    /// Reproduces the device output that broke the old parser: text blocks are
    /// emitted column by column, the quantity column has fewer lines than the
    /// names (ML Kit merged cells), and `8,500` is split across two boxes.
    test('attaches numbers by vertical proximity, not line count', () {
      final List<OcrLine> lines = <OcrLine>[];
      void add(String text, double left, double right, double top) {
        lines.add(OcrLine(
          text: text,
          left: left,
          top: top,
          right: right,
          bottom: top + 20,
        ));
      }

      const List<String> names = <String>[
        'S/ROTI KRIM KEJU 72G',
        'CIMORY MIX BERRY 225',
        'CAFELA EXPRESO 200ML',
        'FF LOW FAT VAN 225',
        'PLASTIK SDG',
      ];
      const List<String> units = <String>['4500', '8500', '3500', '5200', '1'];

      add('Sndon Omane', 40, 400, 40);
      add('JATINANGOR KM. 20-SUMEDA', 40, 400, 70);
      add('14. 09. 16- 06:46', 40, 400, 100);
      add('2.0. 31 914115/ALIA MU/01', 40, 400, 130);
      for (int i = 0; i < names.length; i++) {
        add(names[i], 40, 400, 160 + i * 30);
      }
      // Only two quantity cells survived.
      add('4', 420, 460, 160);
      add('1', 420, 460, 190);
      for (int i = 0; i < units.length; i++) {
        add(units[i], 470, 560, 160 + i * 30);
      }
      // Line totals; the second is split and slightly offset.
      add('18, 000', 570, 680, 160);
      add('8,', 570, 600, 190);
      add('500', 605, 680, 194);
      add('3, 500', 570, 680, 220);
      add('5, 200', 570, 680, 250);
      add('1', 570, 600, 280);
      // Summary block.
      add('DISKON :', 40, 300, 310);
      add('(1)', 570, 620, 310);
      add('HARGA JUAL :', 40, 300, 340);
      add('35, 200', 570, 680, 340);
      add('DISKON FRISIAN FLAG :', 40, 300, 370);
      add('(1, 300)', 570, 680, 370);
      add('TOTAL :', 40, 300, 400);
      add('33, 900', 570, 680, 400);
      add('TUNAI :', 40, 300, 430);
      add('40', 570, 600, 430);
      add('000', 605, 680, 434);
      add('KEMBALI :', 40, 300, 460);
      add('6, 100', 570, 680, 460);
      add('CALL 1500580 SUMEN INDOMAREMBALI', 40, 400, 490);

      final ParsedReceipt p =
          parser.parse(OcrRawResult(lines: lines, fullText: ''));

      expect(p.items.map((ParsedItem i) => i.name).toList(), names);
      expect(p.items.map((ParsedItem i) => i.qty).toList(),
          <int>[4, 1, 1, 1, 1]);
      expect(p.items.map((ParsedItem i) => i.price).toList(),
          <int>[4500, 8500, 3500, 5200, 1]);
      expect(p.items.map((ParsedItem i) => i.subtotal).toList(),
          <int>[18000, 8500, 3500, 5200, 1]);
      expect(p.total, 33900);
      expect(p.store, 'Indomaret');
    });
  });

  group('ReceiptParser date formats', () {
    final ReceiptParser parser = ReceiptParser();

    ParsedReceipt parseWithDate(String line) => parser.parse(_raw(<String>[
          'TOKO MAJU',
          line,
          'INDOMIE GORENG 7,000',
          'TOTAL 7,000',
        ]));

    test('accepts dd.mm.yy', () {
      expect(parseWithDate('14.09.16 - 06:46').date,
          DateTime(2016, 9, 14, 6, 46));
    });

    test('accepts dd/mm/yyyy', () {
      expect(parseWithDate('14/09/2026 19:14').date,
          DateTime(2026, 9, 14, 19, 14));
    });

    test('does not read a dotted amount as a date', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'TOKO MAJU',
        'INDOMIE GORENG 7.000',
        'TOTAL 7.000',
      ]));
      expect(p.date, isNull);
    });
  });

  group('ReceiptParser survives OCR gluing a pack size onto the price', () {
    final ReceiptParser parser = ReceiptParser();

    /// `KOPI KAPAL API 65G` came back from ML Kit as `KOPI KAPAL API 656`, so
    /// the row held two numbers: the bogus pack size and the real price. No
    /// reading fitted, and the whole line was dropped from the receipt.
    ParsedReceipt parseCoffee(int total) => parser.parse(_raw(<String>[
          'TOKO SUMBER REJEKI',
          'Jl. Malioboro 88, Yogyakarta',
          'SUSU UHT INDOMILK 1L',
          '24.500',
          'KOPI KAPAL API  656',
          '9.500',
          'TOTAL',
          '$total',
        ]));

    test('keeps the line as a single unit at the printed price', () {
      final ParsedReceipt p = parseCoffee(34000);

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['SUSU UHT INDOMILK 1L', 'KOPI KAPAL API']);
      expect(p.items.map((ParsedItem i) => i.qty).toList(), <int>[1, 1]);
      expect(p.items.map((ParsedItem i) => i.subtotal).toList(),
          <int>[24500, 9500]);
      expect(p.itemsTotal, 34000);
      expect(p.difference, 0);
      expect(p.warnings, isEmpty);
    });

    test('does not let the city in the address become the merchant', () {
      // "Yogyakarta" contains the merchant name "Yogya"; matching it as a
      // substring replaced the store name printed on the first line.
      expect(parseCoffee(34000).store, 'Toko Sumber Rejeki');
    });
  });

  group('ReceiptParser treats tax as tax, not a missing item', () {
    final ReceiptParser parser = ReceiptParser();

    ParsedReceipt parseTaxed() => parser.parse(_raw(<String>[
          'INDOMARET',
          'Jl. Kaliurang KM 5, Sleman',
          'BERAS PREMIUM 5KG',
          '72.000',
          'SUSU UHT INDOMILK 1L',
          '24.500',
          'SUBTOTAL',
          '96.500',
          'PPN 11%',
          '10.615',
          'TOTAL',
          '107.115',
        ]));

    test('sets the tax aside instead of warning about it', () {
      final ParsedReceipt p = parseTaxed();

      expect(p.taxTotal, 10615);
      expect(p.itemsTotal, 96500);
      expect(p.total, 107115);
      // The items plus the tax are the total: nothing is missing.
      expect(p.warnings, isEmpty);
    });

    test('does not count the tax line as a purchased item', () {
      expect(parseTaxed().items.map((ParsedItem i) => i.name).toList(),
          <String>['BERAS PREMIUM 5KG', 'SUSU UHT INDOMILK 1L']);
    });

    test('still reports a real discrepancy on a taxed receipt', () {
      // Same receipt, but the printed total no longer matches items + tax.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMARET',
        'BERAS PREMIUM 5KG',
        '72.000',
        'SUSU UHT INDOMILK 1L',
        '24.500',
        'PPN 11%',
        '10.615',
        'TOTAL',
        '120.000',
      ]));

      expect(p.taxTotal, 10615);
      expect(p.warnings, isNotEmpty);
    });
  });

  group('shifted columns from noisy photos', () {
    final ReceiptParser parser = ReceiptParser();
    // Exact text ML Kit produced for a photo of a receipt lying on a wooden
    // table: every price landed one row below its product, and the whole
    // summary was emitted as a block of labels followed by a block of amounts.
    ParsedReceipt parseShifted() => parser.parse(_raw(<String>[
          'INDOMARET',
          'Jl. Kaliurang KM 5, Sleman',
          'Telp. 0274-885522',
          '27/10/2026 21:15 KASIR: DEWI',
          'BERAS PREMIUM 5KG',
          'MINYAK GORENG 2L',
          '  72.000',
          'GULA PASIR 1 KG',
          '  36.000',
          'TELUR AYAM 1KG',
          '  16.000',
          'MIE INSTAN INDOMI E xS',
          '  32.000',
          'SABUN MANDI LIFEBUOY',
          '  15.000',
          'PASTA GIGI PEPSODENT',
          '  12.900',
          'SHAMPO CLEAR 170ML',
          '  18.500',
          'SUSU UHT INDOMI LK 1L',
          '  27.500',
          'KOPI KAPAL API  656',
          '  24.500',
          '  9.500',
          'SUB TOTAL',
          'PPN 11%',
          '  263.900',
          'TOTAL',
          '  29.029',
          '  292.929',
        ]));

    test('keeps every product when the price column is one row low', () {
      final ParsedReceipt p = parseShifted();

      expect(p.items.length, 10);
      expect(p.items.first.name, 'BERAS PREMIUM 5KG');
      expect(p.items.first.price, 72000);
      expect(p.items.last.name, 'KOPI KAPAL API');
      expect(p.items.last.price, 9500);
    });

    test('pairs each summary label with its own amount', () {
      final ParsedReceipt p = parseShifted();

      expect(p.itemsTotal, 263900);
      expect(p.taxTotal, 29029);
      expect(p.total, 292929);
      expect(p.totalFromReceipt, isTrue);
      expect(p.warnings, isEmpty);
    });
  });

  group('a faded thermal receipt photographed on a table', () {
    final ReceiptParser parser = ReceiptParser();

    test('reads the quantity through a pack size glued to the name', () {
      // `85G` came back as `856`, and the line total was lost entirely, leaving
      // only `2 * 3.500`. The pack size must not become the quantity.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMRET',
        'INDOMIE MI GORENG  856',
        '  2 * 3.500',
        'AQUA AIR MINERAL 60OML',
        '  7.000',
      ]));

      final ParsedItem mie = p.items.first;
      expect(mie.name, 'INDOMIE MI GORENG');
      expect(mie.qty, 2);
      expect(mie.price, 3500);
      expect(mie.lineTotal, 7000);
    });

    test('recovers a merchant whose letters were dropped', () {
      // `INDOMARET` printed on faded thermal paper reads as `INDOMRET`.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMRET',
        'JL KALIURANG KM 5 NO 12',
        'SLEMAN YOGYAKARTA',
        'KOPI KAPAL API 65G',
        '  9.500',
      ]));

      expect(p.store, 'Indomaret');
    });

    test('does not turn a discount line into a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMARET',
        'KOPI KAPAL API 65G',
        '  9.500',
        'SUBTOTAL',
        '  9.500',
        'DISC MEMBER 5%',
        '  -475',
        'TOTAL',
        '  9.025',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['KOPI KAPAL API 65G']);
      expect(p.discountTotal, 475);
      expect(p.total, 9025);
    });

    test('still finds TOTAL when OCR drops a letter from it', () {
      // Faded thermal print reads `TOTAL` as `TMAL`.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMARET',
        'KOPI KAPAL API 65G',
        '  9.500',
        'SUBTOTAL',
        '  9.500',
        'TMAL',
        '  9.500',
      ]));

      expect(p.total, 9500);
      expect(p.totalFromReceipt, isTrue);
      expect(p.warnings, isEmpty);
    });
  });

  group('a receipt photographed at an angle', () {
    final ReceiptParser parser = ReceiptParser();

    /// Exact boxes ML Kit returned for a photo of an Indomaret receipt lying on
    /// a wooden table, taken the way a user actually holds the phone: the sheet
    /// is tilted, so every box on the right-hand side sits about one line lower
    /// than the text it belongs to.
    ParsedReceipt parseAngled() {
      const List<List<Object>> boxes = <List<Object>>[
        <Object>[176, 339, 455, 'INDOMARET'],
        <Object>[201, 336, 637, 'JL KALIURANG KM 5 NO 12'],
        <Object>[229, 337, 558, 'SLEMAN YOGYAKARTA'],
        <Object>[259, 332, 662, 'NPWP 01.234.567.8-901.000'],
        <Object>[314, 329, 437, 'NO.027/1'],
        <Object>[341, 329, 529, 'KASIR 03 DEWI S'],
        <Object>[337, 543, 785, 'TGL 27/10/26 19:42'],
        <Object>[399, 328, 610, 'INDOMIE MI GORENG 85G'],
        <Object>[429, 353, 471, '2 x 3.500'],
        <Object>[456, 323, 623, 'AQUA AIR MINERAL 600ML'],
        <Object>[452, 800, 867, '7.000'],
        <Object>[485, 323, 595, 'SARI ROTI TAWAR 400G'],
        <Object>[512, 320, 611, 'TETUR AYAM NF.GERT 1KG'],
        <Object>[509, 802, 869, '3.500'],
        <Object>[543, 319, 567, 'SABUN LIFEBUOY 85G'],
        <Object>[538, 789, 870, '15.500'],
        <Object>[573, 318, 665, 'PASTA GIGI PEPSODENT 190G'],
        <Object>[567, 791, 871, '32.000'],
        <Object>[603, 316, 553, 'SUSU UHT ULTRA 1L'],
        <Object>[600, 805, 872, '4.900'],
        <Object>[632, 313, 566, 'KOPI KAPAL API 65C'],
        <Object>[629, 792, 872, '12.900'],
        <Object>[663, 312, 508, 'ROTI KRIM KEJU'],
        <Object>[658, 793, 874, '19.900'],
        <Object>[693, 310, 639, 'TISSUE PASEO 250 LEMBAR'],
        <Object>[690, 808, 874, '9.500'],
        <Object>[721, 808, 877, '3.500'],
        <Object>[750, 796, 880, '17.500'],
        <Object>[759, 307, 436, 'TOTAL QTY'],
        <Object>[792, 307, 422, 'SUBTOTAL'],
        <Object>[823, 303, 495, 'DISC MEMBER 5'],
        <Object>[826, 852, 881, '11'],
        <Object>[849, 784, 882, '126.200'],
        <Object>[857, 302, 392, 'PPN 11'],
        <Object>[883, 797, 883, '-6.310'],
        <Object>[892, 300, 375, 'TOTAL'],
        <Object>[920, 297, 373, 'TUNNI'],
        <Object>[917, 798, 884, '13.188'],
        <Object>[951, 799, 886, '33.07IR'],
        <Object>[960, 298, 431, 'KEMBNIAN'],
        <Object>[981, 785, 888, '150.000'],
        <Object>[1019, 801, 890, '16.922'],
        <Object>[1032, 295, 532, 'ANDA HEMAT 6.310'],
        <Object>[1070, 297, 474, 'LERIMA KASIH'],
        <Object>[1101, 300, 684, 'SELAMAT BERBELANJA KEMBALI'],
        <Object>[1135, 289, 655, 'RARANG YANG SuDAH DTRRIT'],
        <Object>[1177, 292, 576, 'TIDAK DAPAT DITUKAR'],
      ];
      return parser.parse(OcrRawResult(
        lines: <OcrLine>[
          for (final List<Object> b in boxes)
            OcrLine(
              text: b[3] as String,
              left: (b[1] as int).toDouble(),
              top: (b[0] as int).toDouble(),
              right: (b[2] as int).toDouble(),
              bottom: (b[0] as int).toDouble() + 18,
            ),
        ],
        fullText: boxes.map((List<Object> b) => b[3] as String).join('\n'),
      ));
    }

    test('pairs every product with the price printed on its own line', () {
      final ParsedReceipt p = parseAngled();

      expect(
        p.items.map((ParsedItem i) => i.name).toList(),
        <String>[
          'INDOMIE MI GORENG 85G',
          'AQUA AIR MINERAL 600ML',
          'SARI ROTI TAWAR 400G',
          'TETUR AYAM NF.GERT 1KG',
          'SABUN LIFEBUOY 85G',
          'PASTA GIGI PEPSODENT 190G',
          'SUSU UHT ULTRA 1L',
          'KOPI KAPAL API 65C',
          'ROTI KRIM KEJU',
          'TISSUE PASEO 250 LEMBAR',
        ],
      );
      expect(
        p.items.map((ParsedItem i) => i.lineTotal).toList(),
        <int>[7000, 3500, 15500, 32000, 4900, 12900, 19900, 9500, 3500, 17500],
      );
      // The `2 x 3.500` line stays with the product above it.
      expect(p.items.first.qty, 2);
      expect(p.items.first.price, 3500);
    });

    test('reads the summary block even though it drifted down too', () {
      final ParsedReceipt p = parseAngled();

      expect(p.itemsTotal, 126200);
      expect(p.discountTotal, 6310);
      expect(p.taxTotal, 13188);
    });

    test('rebuilds a total OCR destroyed, once the parts agree', () {
      // `133.078` came back as `33.07IR`, so the TOTAL line has no readable
      // amount. The items add up to the printed subtotal, and
      // 126.200 - 6.310 + 13.188 equals TUNAI 150.000 - KEMBALIAN 16.922, so the
      // total can be rebuilt instead of falling back to the item sum.
      final ParsedReceipt p = parseAngled();

      expect(p.total, 133078);
      expect(p.warnings, isEmpty);
    });
  });

  group('a receipt with qty, harga and jumlah columns', () {
    /// Exact boxes ML Kit returned for an Alfamart receipt photographed on a
    /// dark table. The paper leans away from the camera on the right, so the
    /// further right a column sits the lower its boxes land: the product names
    /// are ~31 px above their quantity, ~38 px above their unit price and
    /// ~50 px above their line total.
    ParsedReceipt parseThreeColumns() {
      const List<List<Object>> boxes = <List<Object>>[
        <Object>[267, 235, 388, 'ALFAMART'],
        <Object>[304, 236, 571, 'JL. GAJAH MADA NO. 88'],
        <Object>[329, 234, 489, 'YOGYAKARTA 55223'],
        <Object>[354, 233, 634, 'NPWP 02.345.678.9-902.000'],
        <Object>[411, 231, 422, 'NO : Al-0042'],
        <Object>[439, 230, 438, 'KASIR : ANDRI'],
        <Object>[443, 632, 854, '28/10/26 08:12'],
        <Object>[497, 231, 294, 'ITEM'],
        <Object>[524, 228, 523, 'SABUN LIFEBUOY 85G'],
        <Object>[527, 612, 659, 'QTY'],
        <Object>[534, 729, 810, 'HARGA'],
        <Object>[545, 876, 972, 'JUMLAH'],
        <Object>[552, 227, 522, 'SHAMPO CLEAR 17 OML'],
        <Object>[555, 626, 639, '2'],
        <Object>[561, 725, 803, '4.900'],
        <Object>[573, 870, 948, '9.800'],
        <Object>[582, 227, 454, 'INDOMIE GORENG'],
        <Object>[584, 628, 638, '1'],
        <Object>[591, 726, 820, '18.500'],
        <Object>[601, 871, 964, '18.50o'],
        <Object>[610, 223, 388, 'AQUA 600ML'],
        <Object>[613, 627, 639, '3'],
        <Object>[619, 725, 804, '3.200'],
        <Object>[630, 873, 950, '9.600'],
        <Object>[640, 223, 452, 'BATERAI ABC AA'],
        <Object>[642, 626, 639, '2'],
        <Object>[648, 727, 804, '3.800'],
        <Object>[659, 872, 951, '7.600'],
        <Object>[668, 222, 503, 'TISSUE PASEO 250S'],
        <Object>[677, 727, 822, '15.000'],
        <Object>[689, 874, 968, '15.000'],
        <Object>[697, 228, 504, 'SUSU UHT ULTRA 1L'],
        <Object>[702, 629, 637, '1'],
        <Object>[707, 726, 822, '17.500'],
        <Object>[718, 874, 970, '17.500'],
        <Object>[728, 220, 521, 'KOPI KAPAL API 65G'],
        <Object>[736, 726, 823, '19.900'],
        <Object>[746, 876, 971, '39.800'],
        <Object>[758, 220, 552, 'PASTA GIGI PEPSODENT'],
        <Object>[761, 629, 635, '1'],
        <Object>[765, 727, 806, '9.500'],
        <Object>[777, 876, 956, '9.500'],
        <Object>[786, 217, 452, 'ROTI KRIM KEJU'],
        <Object>[790, 629, 638, '1'],
        <Object>[796, 727, 824, '12.900'],
        <Object>[807, 876, 973, '12.900'],
        <Object>[819, 628, 640, '2'],
        <Object>[826, 728, 807, '3.500'],
        <Object>[837, 876, 958, '7.000'],
        <Object>[850, 214, 384, 'TOTAL ITEM'],
        <Object>[882, 214, 349, 'SUBTOTAL'],
        <Object>[913, 213, 313, 'DISKON'],
        <Object>[907, 928, 957, '16'],
        <Object>[929, 842, 956, '147.200'],
        <Object>[944, 212, 329, 'PB1 10%'],
        <Object>[962, 859, 958, '-7.200'],
        <Object>[976, 209, 410, 'TOTAL BAYAR'],
        <Object>[991, 861, 958, '14.000'],
        <Object>[1006, 209, 392, 'BAYAR TUNAI'],
        <Object>[1023, 835, 960, '154.000'],
        <Object>[1036, 209, 352, 'KEMBALI'],
        <Object>[1055, 861, 958, '200.000'],
        <Object>[1082, 860, 957, '46.000'],
        <Object>[1106, 212, 404, 'ANDA HEMAT 7.200'],
        <Object>[1136, 213, 652, 'TERIMA KASIH ATAS KUNJUNGAN ANDA'],
        <Object>[1166, 213, 572, 'BARANG YANG SUDAH DIBELI'],
        <Object>[1196, 213, 514, 'TIDAK DAPAT DITUKAR'],
      ];
      return ReceiptParser().parse(OcrRawResult(
        lines: <OcrLine>[
          for (final List<Object> b in boxes)
            OcrLine(
              text: b[3] as String,
              left: (b[1] as int).toDouble(),
              top: (b[0] as int).toDouble(),
              right: (b[2] as int).toDouble(),
              bottom: (b[0] as int).toDouble() + 20,
            ),
        ],
        fullText: boxes.map((List<Object> b) => b[3] as String).join('\n'),
      ));
    }

    test('gives every product its own quantity, unit price and line total', () {
      final ParsedReceipt p = parseThreeColumns();

      expect(
        p.items.map((ParsedItem i) => i.name).toList(),
        <String>[
          'SABUN LIFEBUOY 85G',
          'SHAMPO CLEAR 17 OML',
          'INDOMIE GORENG',
          'AQUA 600ML',
          'BATERAI ABC AA',
          'TISSUE PASEO 250S',
          'SUSU UHT ULTRA 1L',
          'KOPI KAPAL API 65G',
          'PASTA GIGI PEPSODENT',
          'ROTI KRIM KEJU',
        ],
      );
      expect(
        p.items.map((ParsedItem i) => i.qty).toList(),
        <int>[2, 1, 3, 2, 1, 1, 2, 1, 1, 2],
      );
      expect(
        p.items.map((ParsedItem i) => i.price).toList(),
        <int>[
          4900, 18500, 3200, 3800, 15000, 17500, 19900, 9500, 12900, 3500,
        ],
      );
      expect(
        p.items.map((ParsedItem i) => i.lineTotal).toList(),
        <int>[
          9800, 18500, 9600, 7600, 15000, 17500, 39800, 9500, 12900, 7000,
        ],
      );
    });

    test('keeps the shop header and the table heading out of the items', () {
      final ParsedReceipt p = parseThreeColumns();

      // `YOGYAKARTA 55223` has a postcode that looks like a price, and the
      // `ITEM QTY HARGA JUMLAH` heading sits on the same lines as the products.
      expect(
        p.items.where((ParsedItem i) => i.name.contains('YOGYAKARTA')),
        isEmpty,
      );
      expect(p.items.where((ParsedItem i) => i.name.contains('QTY')), isEmpty);
      expect(p.items.length, 10);
      // Keeping the header rows is what makes the shop name readable.
      expect(p.store, 'Alfamart');
    });

    test('reads the totals even though the whole block drifted down', () {
      final ParsedReceipt p = parseThreeColumns();

      expect(p.itemsTotal, 147200);
      expect(p.discountTotal, 7200);
      expect(p.taxTotal, 14000);
      expect(p.total, 154000);
      expect(p.totalFromReceipt, isTrue);
      expect(p.warnings, isEmpty);
    });
  });

  group('a product name that contains a summary word', () {
    final ReceiptParser parser = ReceiptParser();

    /// ML Kit emits the name column first and the numbers on their own lines,
    /// which is the layout that used to make the parser lose products.
    const List<String> lines = <String>[
      'INDOMARET',
      'JL. RAYA BOGOR NO 22',
      '06.10.26 14:30',
      'SABUN LIFEBUOY TOTAL CARE',
      '1',
      '4500',
      '4,500',
      'SUSU ULTRA 1L',
      '1',
      '18000',
      '18,000',
      'MIE INDOMIE',
      '1',
      '3500',
      '3,500',
      'TOTAL : 26,000',
      'TUNAI : 30,000',
      'KEMBALI : 4,000',
    ];

    test('keeps the product instead of reading TOTAL as a summary line', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(
        p.items.map((ParsedItem i) => i.name).toList(),
        <String>['SABUN LIFEBUOY TOTAL CARE', 'SUSU ULTRA 1L', 'MIE INDOMIE'],
      );
    });

    test('pairs qty, unit and line total printed on separate rows', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(p.items.map((ParsedItem i) => i.qty).toList(), <int>[1, 1, 1]);
      expect(
        p.items.map((ParsedItem i) => i.price).toList(),
        <int>[4500, 18000, 3500],
      );
    });

    test('reconciles the items with the printed total', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(p.itemsTotal, 26000);
      expect(p.total, 26000);
      expect(p.warnings, isEmpty);
    });
  });

  group('a shop header that carries a branch number', () {
    final ReceiptParser parser = ReceiptParser();

    const List<String> lines = <String>[
      'INDOMARET 12345',
      'JL. RAYA BOGOR NO 22',
      '06.10.26 14:30',
      'MIE INDOMIE',
      '1',
      '3500',
      '3,500',
      'TOTAL : 3,500',
      'TUNAI : 5,000',
      'KEMBALI : 1,500',
    ];

    test('does not turn the shop name into a product', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['MIE INDOMIE']);
      expect(p.items.single.price, 3500);
    });
  });

  group('a pack size OCR read as a four-digit amount', () {
    final ReceiptParser parser = ReceiptParser();

    /// Rows exactly as ML Kit returned them for a Superindo receipt, where the
    /// pack size `250S` came back as `2505`. That reads as a valid amount, so it
    /// joined the numeric block and the item was dropped altogether.
    const List<String> lines = <String>[
      'SUPERINDO',
      'JL. KALIURANG KM 7 NO 21',
      '28/10/26 17:04',
      'SBN LIFBUY 85G 2 5.100 10.200',
      'TISU PASEO 2505 17.900 17.900',
      'SU UHT ULTRA 1L 2 20.500 41.000',
      'TOTAL ITEM 3',
      'SUB TOTAL 69.100',
      'TOTAL BAYAR 69.100',
    ];

    test('keeps the product instead of discarding the whole row', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(
        p.items.map((ParsedItem i) => i.name).toList(),
        <String>['SBN LIFBUY 85G', 'TISU PASEO 2505', 'SU UHT ULTRA 1L'],
      );
    });

    test('reads the single unit at the printed price', () {
      final ParsedReceipt p = parser.parse(_raw(lines));
      final ParsedItem tisue =
          p.items.firstWhere((ParsedItem i) => i.name.contains('TISU'));

      expect(tisue.qty, 1);
      expect(tisue.price, 17900);
    });

    test('makes the items add up to the printed total', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(p.itemsTotal, 69100);
      expect(p.total, 69100);
    });
  });

  group('summary lines that carry a count or a service charge', () {
    final ReceiptParser parser = ReceiptParser();

    test('a total label with a parenthesised count is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'TOKO BAGUS',
        'JL. MERDEKA 10',
        'BLUS WANITA',
        '120.000',
        'TOTAL (2 iten)',
        '120.000',
        'CC.Visa',
        '120.000',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['BLUS WANITA']);
    });

    test('service charge, PB1 and coupon lines are not products', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'KAFE SENJA',
        'JL. SUDIRMAN 5',
        '1 Chicken Baked Rice 55.000',
        '1 Fish n Chips 65.000',
        'SUB TOTAL 120.000',
        'Service 12.000',
        'PBI 1.200',
        'TOTAL 133.200',
        'Coupon (10.000)',
        'CASH 200.000',
        'Change 76.800',
      ]));

      final List<String> names =
          p.items.map((ParsedItem i) => i.name.toLowerCase()).toList();

      expect(names, hasLength(2),
          reason: 'service, PB1 and coupon are summary lines, not products');
      expect(names[0], contains('chicken baked rice'));
      expect(names[1], contains('fish n chips'));
    });

    test('a card payment line is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'BUTIK ANGGUN',
        'JL. BRAWIJAYA 8',
        'BLUS WANITA 120.000',
        'TOTAL (2 iten) 120.000',
        'CC.Visa.BCA 120.000',
      ]));

      expect(p.items.map((ParsedItem i) => i.name.toLowerCase()).toList(),
          <String>['blus wanita']);
    });

    test('a product that merely starts with a brand word survives', () {
      // `TOTAL CARE` is a real product line, so the rule must key on the line
      // *starting* with a summary word, not on the word appearing at all.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'INDOMARET',
        'JL. RAYA BOGOR 22',
        'SABUN LIFEBUOY TOTAL CARE 1 4500 4,500',
        'TOTAL 4,500',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['SABUN LIFEBUOY TOTAL CARE']);
    });
  });

  group('a shop whose name is not recognised', () {
    final ReceiptParser parser = ReceiptParser();

    /// CORD cafe receipts carry no known merchant, so the store name falls back
    /// to the first line with letters — which is the first product. The header
    /// filter must not treat that product as the shop's own name.
    const List<String> lines = <String>[
      '1 Redvelvet Cheese Slc 38.000',
      '1 Iced Tea 20.000',
      'SUB TOTAL 58.000',
      'TOTAL 58.000',
    ];

    test('keeps the first product instead of using it as the store name', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(
        p.items.map((ParsedItem i) => i.name.toLowerCase()).toList(),
        <String>['redvelvet cheese slc', 'iced tea'],
        reason: 'the leading quantity column is stripped from the name',
      );
    });

    test('still reconciles with the printed total', () {
      final ParsedReceipt p = parser.parse(_raw(lines));

      expect(p.itemsTotal, 58000);
      expect(p.total, 58000);
    });
  });

  group('restaurant receipts seen in the held-out set', () {
    final ReceiptParser parser = ReceiptParser();

    test('a "Pajak Resto" line with OCR damage is not a product', () {
      // Real ML Kit output: `Pajak Resto 10%` came back as `Paiak RESTO 10%`.
      // `paiak` already fuzzy-matches `pajak`; `resto` was the missing word.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'SOTO MEDAN',
        'JL. GAJAH MADA 3',
        '1 SOTO MEDAN+NASI 59.500',
        '1 GADO-GADO 34.500',
        'SUB TOTAL 94.000',
        'Service harge 5 4.700',
        'Paiak RESTO 10% 9.870',
        'TOTAL 108.570',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['SOTO MEDAN+NASI', 'GADO-GADO']);
      // Service charge and restaurant tax are both added on top of the items,
      // so both count as the tax component: 94.000 + 4.700 + 9.870 = 108.570.
      expect(p.taxTotal, 14570);
      expect(p.total, 108570);
      expect(p.itemsTotal + p.taxTotal - p.discountTotal, p.total);
    });

    test('the abbreviated "P.Rest" tax line is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'KFC',
        'JL. SUDIRMAN 9',
        '2 KFC Winger HC 40.000',
        '1 Ori Bento 13.636',
        'SUB TOTAL 60.454',
        'P.Rest 10 % 6.046',
        'TOTAL 66.500',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['KFC Winger HC', 'Ori Bento']);
    });

    test('a card payment line is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'TOKO ROTI',
        'JL. KEMANG 12',
        '1 POTATO SAUSAGE BREAD 58.000',
        '1 WHITE CHOCO BANANA SPREAD 58.000',
        '1 OREO GREEN TEA SPREAD 58.000',
        'TOTAL 174.000',
        'CARD 174.000',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>[
            'POTATO SAUSAGE BREAD',
            'WHITE CHOCO BANANA SPREAD',
            'OREO GREEN TEA SPREAD',
          ]);
    });

    test('a subtotal whose last letter OCR split off is still a subtotal', () {
      // `SUB TOTAL` came back as `Sub Tota l`. The corrector rejoins it before
      // the parser runs (see `ocr_text_corrector_test.dart`); this asserts the
      // parser is tolerant even if a caller feeds it raw text.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'KFC',
        'JL. SUDIRMAN 9',
        '2 KFC Winger HC 40.000',
        '1 Ori Bento 13.636',
        'Sub Tota l 53.636',
        'TOTAL 53.636',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['KFC Winger HC', 'Ori Bento']);
    });
  });

  group('payment and tax vocabulary seen on held-out receipts', () {
    final ReceiptParser parser = ReceiptParser();

    test('PB1 split into "PB 1" is still the tax line', () {
      // Real ML Kit output: `PB1 10%` came back as `PB  1 10`. The corrector
      // rejoins the token before the parser splits name from amounts, which is
      // the same order the scan screen uses.
      final ParsedReceipt p = parser.parse(correctOcrText(_raw(<String>[
        'WARUNG PADANG',
        'JL. MERDEKA 4',
        "1 Rendang 20.000",
        "1 Ayam Pop 35.000",
        'SUB TOTAL 55.000',
        'PB  1 10 5.500',
        'TOTAL 60.500',
      ])));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Rendang', 'Ayam Pop']);
      expect(p.taxTotal, 5500);
      expect(p.total, 60500);
    });

    test('an Indonesian "Kartu" payment line is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'BAKMI AHONG',
        'JL. KARTINI 7',
        '1 Bakmi Ayam 30.000',
        'TOTAL 30.000',
        'Kartu 30.000',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Bakmi Ayam']);
    });

    test('a total label that lost its last letter is still a total', () {
      // `TOTAL` came back as `TOTA.` — the trailing L was read as a period, so
      // the token the parser sees is `tota`.
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'WARTEG BAHARI',
        'JL. PANGERAN 2',
        '1 Nasi Uduk 15.000',
        '1 Tempe Orek 5.000',
        'SUB TOTAL 20.000',
        'TOTA. 20.000',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Nasi Uduk', 'Tempe Orek']);
      expect(p.total, 20000);
      expect(p.totalFromReceipt, isTrue);
    });
    test('English payment and terminal lines are not products', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'WARUNG SEDERHANA',
        'JL. KARTINI 7',
        '1 Ayam Bakar 25.000',
        'SUB TOTAL 25.000',
        'TOTAL 27.500',
        'Tendered 50.000',
        'EDC 27.500',
        'KEMBALI 22.500',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Ayam Bakar']);
    });

    test('a bank name on its own line is not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'BAKSO PAK KUMIS',
        'JL. AHMAD YANI 3',
        '1 Bakso Campur 28.600',
        '1 Es Teh 5.000',
        'SUB TOTAL 33.600',
        'TOTAL 33.600',
        'BCA 33.600',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Bakso Campur', 'Es Teh']);
    });

    test('"SUC CHG" is a service charge, not a product', () {
      final ParsedReceipt p = parser.parse(_raw(<String>[
        'RESTO ITALIA',
        'JL. SENOPATI 9',
        '1 Carbonara 120.000',
        '1 Truffle Cream 90.000',
        'SUB TOTAL 210.000',
        'SUC CHG 6% 12.600',
        'TOTAL 222.600',
      ]));

      expect(p.items.map((ParsedItem i) => i.name).toList(),
          <String>['Carbonara', 'Truffle Cream']);
      expect(p.taxTotal, 12600);
      expect(p.total, 222600);
    });
  });

  group('the weak-parse check used to trigger OCR retries', () {
    test('a taxed receipt that adds up is not weak', () {
      final ParsedReceipt p = ParsedReceipt(
        store: 'Indomaret',
        date: null,
        items: <ParsedItem>[
          ParsedItem(name: 'KOPI', qty: 1, price: 10000, lineTotal: 10000),
        ],
        total: 11100,
        paymentMethod: 'Tunai',
        taxTotal: 1100,
        totalFromReceipt: true,
      );

      expect(ReceiptParser.reconciles(p), isTrue);
    });

    test('a receipt whose items miss 5000 rupiah is weak', () {
      final ParsedReceipt p = ParsedReceipt(
        store: 'Indomaret',
        date: null,
        items: <ParsedItem>[
          ParsedItem(name: 'KOPI', qty: 1, price: 10000, lineTotal: 10000),
        ],
        total: 15000,
        paymentMethod: 'Tunai',
        totalFromReceipt: true,
      );

      expect(ReceiptParser.reconciles(p), isFalse);
    });
  });

  group('a receipt leaning the other way', () {
    /// Exact boxes ML Kit returned for a Superindo receipt photographed with the
    /// sheet leaning away from the camera on the *left*. That mirrors the
    /// Indomaret photo above: here every amount sits ~35 px *above* its product
    /// name instead of below it, so a skew correction that only looks downwards
    /// pairs each amount with the product on the previous line.
    ///
    /// The names are also written the way cashiers abbreviate them — `SBN LI
    /// FBUY 85G` — which is what a real thermal receipt looks like.
    ParsedReceipt parseLeaningLeft() {
      const List<List<Object>> boxes = <List<Object>>[
        <Object>[323, 213, 386, 'SUPERINDO'],
        <Object>[345, 227, 598, 'JL. KALIURANG KM7 NO 21'],
        <Object>[386, 213, 403, 'SLEMAN 55581'],
        <Object>[398, 213, 621, 'NPWP 01.987.654 .3-901.000'],
        <Object>[445, 619, 843, '28/10/26 17:04'],
        <Object>[476, 216, 406, 'NO : S1-0917'],
        <Object>[504, 218, 428, 'KASIR: RATNA'],
        <Object>[524, 867, 962, 'JUMLAH'],
        <Object>[535, 721, 800, 'HARGA'],
        <Object>[550, 603, 650, 'QTY'],
        <Object>[554, 864, 957, '10.200'],
        <Object>[566, 716, 794, '5.100'],
        <Object>[576, 222, 284, 'ITEM'],
        <Object>[580, 618, 631, '2'],
        <Object>[583, 865, 957, '18.900'],
        <Object>[590, 221, 447, 'SBN LI FBUY 85G'],
        <Object>[594, 718, 811, '18.900'],
        <Object>[618, 221, 481, 'SHMP CLEAR 170ML'],
        <Object>[615, 866, 944, '9.900'],
        <Object>[624, 719, 796, '3.300'],
        <Object>[645, 221, 514, 'MIE GRG INDOME 85G'],
        <Object>[639, 621, 633, '3'],
        <Object>[645, 867, 944, '8.200'],
        <Object>[654, 720, 797, '4.100'],
        <Object>[675, 221, 514, 'AIR MNRAL AQUA 600'],
        <Object>[669, 622, 633, '2'],
        <Object>[674, 869, 963, '15.500'],
        <Object>[683, 722, 814, '15.500'],
        <Object>[699, 625, 634, '1'],
        <Object>[702, 870, 964, '17.900'],
        <Object>[709, 224, 466, 'BTR ABC AA 2PCS'],
        <Object>[713, 723, 816, '17.900'],
        <Object>[737, 224, 467, 'TISU PASEO 250S'],
        <Object>[732, 871, 965, '41.000'],
        <Object>[743, 722, 817, '20.500'],
        <Object>[759, 625, 638, '2'],
        <Object>[768, 225, 469, 'SU UHT ULTRA 1L'],
        <Object>[763, 873, 950, '9.900'],
        <Object>[775, 725, 803, '9.900'],
        <Object>[789, 627, 637, '1'],
        <Object>[791, 874, 968, '13.500'],
        <Object>[803, 226, 418, 'KOPI KPL API'],
        <Object>[798, 441, 486, '65G'],
        <Object>[803, 727, 819, '13.500'],
        <Object>[819, 628, 638, '1'],
        <Object>[828, 227, 472, 'PST GIGI PEPSDN'],
        <Object>[822, 875, 953, '7.400'],
        <Object>[836, 728, 807, '3.700'],
        <Object>[848, 629, 641, '2'],
        <Object>[861, 227, 438, 'RTI KRIM KEJU'],
        <Object>[891, 926, 955, '16'],
        <Object>[919, 843, 955, '152.400'],
        <Object>[928, 229, 393, 'TOTAL ITEM'],
        <Object>[949, 861, 956, '-2.400'],
        <Object>[961, 229, 359, 'SUBTOTAL'],
        <Object>[980, 863, 957, '16.500'],
        <Object>[995, 231, 328, 'DISKON'],
        <Object>[1011, 839, 958, '166.500'],
        <Object>[1023, 232, 343, 'PPN 11%'],
        <Object>[1041, 848, 960, '200.000'],
        <Object>[1050, 231, 425, 'TOTAL BAYAR'],
        <Object>[1071, 866, 961, '33.500'],
        <Object>[1086, 233, 311, 'TUNAI'],
        <Object>[1113, 233, 345, 'KEMBALI'],
      ];
      return ReceiptParser().parse(OcrRawResult(
        lines: <OcrLine>[
          for (final List<Object> b in boxes)
            OcrLine(
              text: b[3] as String,
              left: (b[1] as int).toDouble(),
              top: (b[0] as int).toDouble(),
              right: (b[2] as int).toDouble(),
              bottom: (b[0] as int).toDouble() + 18,
            ),
        ],
        fullText: boxes.map((List<Object> b) => b[3] as String).join('\n'),
      ));
    }

    test('pairs every amount with the product above it', () {
      final ParsedReceipt p = parseLeaningLeft();

      expect(p.items.length, 10);
      expect(
        p.items.map((ParsedItem i) => i.name).toList(),
        <String>[
          'SBN LI FBUY 85G',
          'SHMP CLEAR 170ML',
          'MIE GRG INDOME 85G',
          'AIR MNRAL AQUA 600',
          'BTR ABC AA 2PCS',
          'TISU PASEO 250S',
          'SU UHT ULTRA 1L',
          'KOPI KPL API',
          'PST GIGI PEPSDN',
          'RTI KRIM KEJU',
        ],
      );
      expect(
        p.items.map((ParsedItem i) => i.qty).toList(),
        <int>[2, 1, 3, 2, 1, 1, 2, 1, 1, 2],
      );
      expect(
        p.items.map((ParsedItem i) => i.lineTotal).toList(),
        <int>[
          10200, 18900, 9900, 8200, 15500, 17900, 41000, 9900, 13500, 7400,
        ],
      );
    });

    test('reads the shop name and the totals', () {
      final ParsedReceipt p = parseLeaningLeft();

      expect(p.store, 'Superindo');
      expect(p.itemsTotal, 152400);
      expect(p.discountTotal, 2400);
      expect(p.taxTotal, 16500);
      expect(p.total, 166500);
      expect(p.totalFromReceipt, isTrue);
      expect(p.warnings, isEmpty);
    });
  });
}
