// Shared scoring for the on-device OCR harnesses.
//
// The receipt photos are **not** bundled into the APK: a release build should
// not carry ~70 MB of test images. `tool/ocr_assets.sh` starts a small HTTP
// server over `test_assets/struk/` on the host and this harness downloads the
// set it needs into the app's cache directory before scanning.
//
//   bash tool/ocr_assets.sh list
//   bash tool/ocr_assets.sh run dev
//
// Pushing the files to the device instead does not work: `flutter test`
// reinstalls the APK, which wipes the app's external storage directory.
//
// Each harness feeds real ML Kit output through `OcrService.process()` — the
// same code path as the scan screen — and scores the parsed item names against
// a ground truth file with `lib/ocr/ocr_accuracy.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:smart_receipt/ocr/ocr_accuracy.dart';
import 'package:smart_receipt/ocr/ocr_raw_text.dart';
import 'package:smart_receipt/ocr/ocr_service.dart';
import 'package:smart_receipt/ocr/receipt_parser.dart';

/// Where the host serves `test_assets/struk/`. `10.0.2.2` is the host loopback
/// as seen from the Android emulator.
const String _baseUrl = String.fromEnvironment(
  'OCR_HARNESS_URL',
  defaultValue: 'http://10.0.2.2:8765',
);

/// Letters and digits only, so `85G` and `856` compare on equal footing.
String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// How many expected items the parser found, matching by fuzzy containment.
///
/// OCR mangles characters (`250S` -> `2505`), so an exact compare would report
/// a failure for every item. An expected name counts as found when its
/// normalised form is a substring of a parsed name, or the other way round for
/// heavily abbreviated receipts.
int _matched(List<String> expected, List<String> parsed) {
  final List<String> haystack = parsed.map(_normalize).toList();
  int hits = 0;
  for (final String want in expected) {
    final String needle = _normalize(want);
    if (needle.isEmpty) {
      continue;
    }
    if (haystack.any(
        (String p) => p.contains(needle) || needle.contains(p) && p.length >= 4)) {
      hits++;
    }
  }
  return hits;
}

/// Downloads [name] from the host into [dir], or fails with a message that says
/// how to start the server.
Future<File> _download(Directory dir, String name) async {
  final File target = File('${dir.path}/${name.split('/').last}');
  if (target.existsSync() && target.lengthSync() > 0) {
    return target;
  }

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final HttpClientRequest request =
        await client.getUrl(Uri.parse('$_baseUrl/$name'));
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      fail('GET $_baseUrl/$name returned ${response.statusCode}.\n'
          'Is the receipt set named correctly? Run: bash tool/ocr_assets.sh list');
    }
    final IOSink sink = target.openWrite();
    await response.pipe(sink);
  } on SocketException catch (e) {
    fail('Cannot reach the receipt server at $_baseUrl ($e).\n'
        'Start it with: bash tool/ocr_assets.sh run <set>');
  } finally {
    client.close();
  }
  return target;
}

/// Runs every receipt in [setName] and prints a per-receipt report followed by
/// an aggregate summary.
///
/// [label] appears in the summary so several runs stay distinguishable.
Future<void> runReceiptSet(
  WidgetTester tester, {
  required String label,
  required String setName,
}) async {
  final Directory cache =
      Directory('${(await getTemporaryDirectory()).path}/ocr_harness/$setName');
  await cache.create(recursive: true);

  final File truthFile = await _download(cache, '$setName/ground_truth.json');
  final Map<String, dynamic> truth =
      jsonDecode(await truthFile.readAsString()) as Map<String, dynamic>;
  final List<dynamic> receipts = truth['receipts'] as List<dynamic>;

  final OcrService service = OcrService();
  addTearDown(service.dispose);

  final List<String> report = <String>[];
  int itemsFound = 0;
  int itemsExpected = 0;
  int countExact = 0;
  int totalExact = 0;

  // Error rates are aggregated by summing edits and reference units, not by
  // averaging percentages: a three-item receipt must not weigh the same as a
  // ten-item one.
  int cerEdits = 0;
  int cerUnits = 0;
  int werEdits = 0;
  int werUnits = 0;

  for (final dynamic entry in receipts) {
    final Map<String, dynamic> want = entry as Map<String, dynamic>;
    final String name = want['file'] as String;
    final File file = await _download(cache, '$setName/$name');

    final OcrScanResult scan = await service.process(file.path);
    final ParsedReceipt p = scan.parsed;

    final List<String> expected =
        (want['items'] as List<dynamic>).cast<String>();
    final List<String> got = p.items.map((ParsedItem i) => i.name).toList();
    final int hit = _matched(expected, got);
    final int wantCount = want['itemCount'] as int;
    final int wantTotal = want['total'] as int;

    final ItemNameErrorRates rates = itemNameErrorRates(expected, got);

    itemsFound += hit;
    itemsExpected += expected.length;
    cerEdits += rates.characters.edits;
    cerUnits += rates.characters.units;
    werEdits += rates.words.edits;
    werUnits += rates.words.units;

    final bool countOk = got.length == wantCount;
    final bool totalOk = p.total == wantTotal;
    if (countOk) countExact++;
    if (totalOk) totalExact++;

    final String photo = '${scan.quality.width}x${scan.quality.height}'
        '  brightness ${scan.quality.brightness.toStringAsFixed(0)}'
        '  blur ${scan.quality.blurScore.toStringAsFixed(0)}'
        '  rotated ${scan.quality.rotationDegrees}°';

    report.add('''
--- $name  (${want['source']})
  item count : ${got.length} / $wantCount ${countOk ? 'OK' : 'MISMATCH'}
  item names : $hit / ${expected.length} found
  CER / WER  : ${rates.characters.percent.toStringAsFixed(1)}% / ${rates.words.percent.toStringAsFixed(1)}%
  total      : ${p.total} / $wantTotal ${totalOk ? 'OK' : 'MISMATCH'}'
  subtotal   : ${p.itemsTotal}  discount ${p.discountTotal}  tax ${p.taxTotal}
  source     : ${p.source}   raw lines ${scan.raw.lineCount}
  photo      : $photo
  parsed     : ${got.map((String n) => '"$n"').join(', ')}
  missing    : ${expected.where((String e) => !got.any((String g) => _normalize(g).contains(_normalize(e)))).toList()}
  warnings   : ${p.warnings}${countOk && totalOk ? '' : '\n  raw OCR    : ${scan.raw.lines.map((OcrLine l) => l.text).join(' | ')}\n  rows       : ${p.rowDump}'}''');
  }

  final double cer = cerUnits == 0 ? 0 : cerEdits * 100 / cerUnits;
  final double wer = werUnits == 0 ? 0 : werEdits * 100 / werUnits;

  // ignore: avoid_print
  print('''
================ OCR ACCURACY — $label ================
${report.join('\n')}

================ SUMMARY — $label ================
item name recall : $itemsFound / $itemsExpected  (${(itemsFound * 100 / itemsExpected).toStringAsFixed(1)}%)
item count exact : $countExact / ${receipts.length}
total exact      : $totalExact / ${receipts.length}
CER              : ${cer.toStringAsFixed(1)}%  ($cerEdits edits / $cerUnits chars)
WER              : ${wer.toStringAsFixed(1)}%  ($werEdits edits / $werUnits words)
item name acc    : ${(100 - cer).clamp(0, 100).toStringAsFixed(1)}% by character
''');
}
