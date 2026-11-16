import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../models/receipt_filter.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

/// Opens the advanced filter sheet for the transaction history screen.
///
/// Returns the new [ReceiptFilter], or null when the user backs out without
/// applying. [current] supplies the search text and category chip, which are
/// copied through untouched: they belong to the screen, not to this sheet.
Future<ReceiptFilter?> showTransactionFilterSheet(
  BuildContext context, {
  required ReceiptFilter current,
  required List<String> stores,
}) {
  return showModalBottomSheet<ReceiptFilter>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FilterSheet(current: current, stores: stores),
    ),
  );
}

/// "1 Nov 2026 – 16 Nov 2026", or a single date when both ends are the same day.
String _rangeLabel(DateTimeRange range) {
  final String from = formatDate(dayOnly(range.start));
  if (sameDay(range.start, range.end)) {
    return from;
  }
  return '$from – ${formatDate(dayOnly(range.end))}';
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.stores});

  final ReceiptFilter current;
  final List<String> stores;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateTimeRange? _range;
  late String? _store;
  late final TextEditingController _min;
  late final TextEditingController _max;
  String? _error;

  @override
  void initState() {
    super.initState();
    _range = widget.current.range;
    _store = widget.current.store;
    _min = TextEditingController(text: _text(widget.current.minAmount));
    _max = TextEditingController(text: _text(widget.current.maxAmount));
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  static String _text(int? value) => value?.toString() ?? '';

  int? _amount(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  /// Quick ranges, relative to today.
  ///
  /// Covers the cases people actually filter by; the calendar is there for
  /// everything else. `DateTime(year, month - 2, 1)` rolls into the previous year
  /// on its own when the current month is January or February.
  List<({String label, DateTimeRange range})> get _presets {
    final DateTime today = dayOnly(DateTime.now());
    return <({String label, DateTimeRange range})>[
      (
        label: 'Bulan Ini',
        range: DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        ),
      ),
      (
        label: '3 Bulan',
        range: DateTimeRange(
          start: DateTime(today.year, today.month - 2, 1),
          end: today,
        ),
      ),
      (
        label: 'Tahun Ini',
        range: DateTimeRange(start: DateTime(today.year, 1, 1), end: today),
      ),
    ];
  }

  bool _isPreset(DateTimeRange preset) {
    final DateTimeRange? range = _range;
    return range != null &&
        sameDay(range.start, preset.start) &&
        sameDay(range.end, preset.end);
  }

  bool get _dirty =>
      _range != null ||
      _store != null ||
      _min.text.isNotEmpty ||
      _max.text.isNotEmpty;

  void _reset() {
    setState(() {
      _range = null;
      _store = null;
      _error = null;
      _min.clear();
      _max.clear();
    });
  }

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => _DateRangeSheet(initial: _range),
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  void _apply() {
    final int? min = _amount(_min);
    final int? max = _amount(_max);
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Nominal minimum tidak boleh melebihi maksimum');
      return;
    }
    Navigator.pop(
      context,
      ReceiptFilter(
        query: widget.current.query,
        category: widget.current.category,
        range: _range,
        minAmount: min,
        maxAmount: max,
        store: _store,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Filter Lanjutan',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  if (_dirty)
                    TextButton(
                      onPressed: _reset,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Atur Ulang',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Persempit daftar transaksi tanpa mengubah isi struk.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              const SheetLabel('Rentang Tanggal'),
              const SizedBox(height: 8),
              _dateField(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final ({String label, DateTimeRange range}) preset
                      in _presets)
                    FilterPill(
                      label: preset.label,
                      active: _isPreset(preset.range),
                      onTap: () => setState(() => _range = preset.range),
                      height: 32,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const SheetLabel('Nominal Transaksi (Rp)'),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MoneyField(
                      controller: _min,
                      hint: 'Minimal',
                      onChanged: _clearError,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MoneyField(
                      controller: _max,
                      hint: 'Maksimal',
                      onChanged: _clearError,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const SheetLabel('Toko'),
              const SizedBox(height: 8),
              if (widget.stores.isEmpty)
                Text(
                  'Belum ada toko tersimpan.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilterPill(
                      label: 'Semua Toko',
                      active: _store == null,
                      onTap: () => setState(() => _store = null),
                      height: 32,
                    ),
                    for (final String store in widget.stores)
                      FilterPill(
                        label: store,
                        active: _store == store,
                        onTap: () => setState(() => _store = store),
                        height: 32,
                      ),
                  ],
                ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Terapkan Filter',
                icon: Icons.check_circle_outline,
                onPressed: _apply,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearError(String _) {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Widget _dateField() {
    final DateTimeRange? range = _range;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _pickRange,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.event_outlined,
                size: 18,
                color: AppColors.iconMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  range == null ? 'Semua tanggal' : _rangeLabel(range),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: range == null ? FontWeight.w400 : FontWeight.w600,
                    color: range == null
                        ? AppColors.textMuted
                        : AppColors.textDark,
                  ),
                ),
              ),
              if (range != null)
                GestureDetector(
                  onTap: () => setState(() => _range = null),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textMuted,
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

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        // Whole rupiah only: the app never stores cents, and a stray "." would
        // silently turn the bound into an unparsable string.
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// Month calendar for picking an inclusive day range.
///
/// Built in-house instead of using `showDateRangePicker` because that dialog is
/// only available in English here: the app ships no `flutter_localizations`, and
/// adding it would force a different `intl` version than the SDK pins.
class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({required this.initial});

  final DateTimeRange? initial;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  /// Grid columns follow the Indonesian week, which starts on Monday.
  static const List<String> _weekdays = <String>[
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];

  late DateTime _month;
  DateTime? _start;
  DateTime? _end;

  /// True while the range has only a start, so the next tap closes it.
  bool _awaitingEnd = false;

  @override
  void initState() {
    super.initState();
    final DateTimeRange? initial = widget.initial;
    _start = initial == null ? null : dayOnly(initial.start);
    _end = initial == null ? null : dayOnly(initial.end);
    _awaitingEnd = initial == null;
    final DateTime anchor = _start ?? DateTime.now();
    _month = DateTime(anchor.year, anchor.month, 1);
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  int get _leadingBlanks => _month.weekday - 1;

  int get _cellCount => ((_leadingBlanks + _daysInMonth) / 7).ceil() * 7;

  void _tap(DateTime day) {
    setState(() {
      if (_start == null || !_awaitingEnd) {
        _start = day;
        _end = null;
        _awaitingEnd = true;
      } else if (day.isBefore(_start!)) {
        // Tapping before the current start moves the start back instead of
        // producing an inverted range.
        _start = day;
      } else {
        _end = day;
        _awaitingEnd = false;
      }
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  void _submit() {
    final DateTime? start = _start;
    if (start == null) {
      return;
    }
    Navigator.pop(
      context,
      DateTimeRange(start: start, end: _end ?? start),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pilih Rentang Tanggal',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ketuk tanggal awal, lalu tanggal akhir.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  _MonthArrow(
                    icon: Icons.chevron_left,
                    onTap: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Text(
                      formatMonth(_month),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  _MonthArrow(
                    icon: Icons.chevron_right,
                    onTap: () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  for (final String name in _weekdays)
                    Expanded(
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.1,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: _cellCount,
                itemBuilder: (BuildContext context, int index) =>
                    _cell(index),
              ),
              const SizedBox(height: 12),
              Text(
                _selectionLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLabel,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Terapkan',
                icon: Icons.check_circle_outline,
                onPressed: _start == null ? null : _submit,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectionLabel {
    final DateTime? start = _start;
    if (start == null) {
      return 'Belum ada tanggal dipilih';
    }
    final DateTime? end = _end;
    if (end == null) {
      return 'Mulai ${formatDate(start)}';
    }
    return _rangeLabel(DateTimeRange(start: start, end: end));
  }

  Widget _cell(int index) {
    final int dayNumber = index - _leadingBlanks + 1;
    if (dayNumber < 1 || dayNumber > _daysInMonth) {
      return const SizedBox.shrink();
    }

    final DateTime day = DateTime(_month.year, _month.month, dayNumber);
    final DateTime? start = _start;
    final DateTime? end = _end;
    final bool isStart = start != null && sameDay(day, start);
    final bool isEnd = end != null && sameDay(day, end);
    final bool endpoint = isStart || isEnd;
    final bool between = start != null &&
        end != null &&
        day.isAfter(start) &&
        day.isBefore(end);
    final bool isToday = sameDay(day, DateTime.now());

    final BoxDecoration decoration;
    if (endpoint) {
      decoration = BoxDecoration(
        color: AppColors.buttonBg,
        shape: BoxShape.circle,
      );
    } else if (between) {
      decoration = BoxDecoration(
        color: AppColors.buttonBg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      );
    } else if (isToday) {
      decoration = BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.2),
        shape: BoxShape.circle,
      );
    } else {
      decoration = const BoxDecoration();
    }

    return InkWell(
      onTap: () => _tap(day),
      customBorder: const CircleBorder(),
      child: Container(
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: decoration,
        child: Text(
          '$dayNumber',
          style: TextStyle(
            fontSize: 13,
            fontWeight: endpoint || isToday ? FontWeight.w700 : FontWeight.w500,
            color: endpoint ? AppColors.onButton : AppColors.textDark,
          ),
        ),
      ),
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 20, color: AppColors.textDark),
        ),
      ),
    );
  }
}
