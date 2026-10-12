class TextParserService {
  // Extract total amount dari OCR text
  double extractTotal(String text) {
    final patterns = [
      RegExp(r'(TOTAL|AMOUNT|JUMLAH|AMT|BAYAR)\s*:?\s*Rp\.?\s*([\d,\.]+)', caseSensitive: false),
      RegExp(r'Rp\.?\s*([\d,\.]+)\s*(TOTAL|AMOUNT)', caseSensitive: false),
      RegExp(r'TOTAL\s*Rp\.?\s*([\d,\.]+)', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        String amount = match.group(2) ?? match.group(1) ?? '0';
        amount = amount.replaceAll('.', '').replaceAll(',', '.');
        return double.tryParse(amount) ?? 0.0;
      }
    }

    // Fallback: cari angka terbesar di text
    final allNumbers = RegExp(r'[\d,\.]+').allMatches(text);
    double maxNumber = 0.0;
    for (var match in allNumbers) {
      String numStr = match.group(0)!.replaceAll('.', '').replaceAll(',', '.');
      double num = double.tryParse(numStr) ?? 0.0;
      if (num > maxNumber && num < 10000000) { // Max 10 juta untuk filter noise
        maxNumber = num;
      }
    }
    return maxNumber;
  }

  // Extract store name (biasanya baris pertama)
  String extractStoreName(String text) {
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 'Unknown Store';
    
    // Ambil baris pertama yang bukan angka
    for (var line in lines.take(3)) {
      if (!RegExp(r'^\d+$').hasMatch(line.trim())) {
        return line.trim();
      }
    }
    return lines.first.trim();
  }

  // Extract tanggal transaksi
  DateTime extractDate(String text) {
    final patterns = [
      RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})'),
      RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})'),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          int day = int.parse(match.group(1)!);
          int month = int.parse(match.group(2)!);
          int year = int.parse(match.group(3)!);
          
          // Handle 2-digit year
          if (year < 100) {
            year += 2000;
          }
          
          return DateTime(year, month, day);
        } catch (e) {
          continue;
        }
      }
    }
    
    return DateTime.now(); // Default: hari ini
  }

  // Extract tax amount
  double extractTax(String text) {
    final patterns = [
      RegExp(r'(TAX|PPN|PAJAK)\s*:?\s*Rp\.?\s*([\d,\.]+)', caseSensitive: false),
      RegExp(r'PB1\s*:?\s*Rp\.?\s*([\d,\.]+)', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        String amount = match.group(2) ?? match.group(1) ?? '0';
        amount = amount.replaceAll('.', '').replaceAll(',', '.');
        return double.tryParse(amount) ?? 0.0;
      }
    }
    
    return 0.0;
  }

  // Extract payment method
  String? extractPaymentMethod(String text) {
    final lowerText = text.toLowerCase();
    
    if (lowerText.contains('cash') || lowerText.contains('tunai')) {
      return 'Cash';
    } else if (lowerText.contains('debit')) {
      return 'Debit Card';
    } else if (lowerText.contains('credit') || lowerText.contains('kartu kredit')) {
      return 'Credit Card';
    } else if (lowerText.contains('qris') || lowerText.contains('gopay') || lowerText.contains('ovo') || lowerText.contains('dana')) {
      return 'E-Wallet';
    }
    
    return null;
  }

  // Extract line items (nama barang + harga)
  List<Map<String, dynamic>> extractItems(String text) {
    final items = <Map<String, dynamic>>[];
    final lines = text.split('\n');
    
    for (var line in lines) {
      // Pattern: Nama Barang ... Rp 10.000
      final match = RegExp(r'(.+?)\s+(?:Rp\.?\s*)?([\d,\.]+)$').firstMatch(line.trim());
      if (match != null) {
        String itemName = match.group(1)?.trim() ?? '';
        String priceStr = match.group(2)?.replaceAll('.', '').replaceAll(',', '.') ?? '0';
        double price = double.tryParse(priceStr) ?? 0.0;
        
        // Filter: skip baris TOTAL, TAX, dll
        if (itemName.toUpperCase().contains('TOTAL') || 
            itemName.toUpperCase().contains('TAX') ||
            itemName.toUpperCase().contains('PAJAK') ||
            itemName.isEmpty) {
          continue;
        }
        
        if (price > 0 && price < 1000000) { // Max 1 juta per item
          items.add({
            'name': itemName,
            'price': price,
            'quantity': 1,
          });
        }
      }
    }
    
    return items;
  }
}
