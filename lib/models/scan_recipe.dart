// Kelmo Scan - document scanner
// Copyright (C) 2026 Kelmo
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import '../services/image_processing_service.dart';

enum ScanKind { document, receipt, idCard, book, whiteboard, invoice, notes, passport, businessCard }

/// "Smart Scan Recipe": one tap sets the right capture mode + default filter for a kind of paper.
class ScanRecipe {
  const ScanRecipe(this.kind, this.label, this.hint, this.icon, this.filter,
      {this.twoSided = false, this.multiPage = false});

  final ScanKind kind;
  final String label, hint;
  final IconData icon;
  final FilterMode filter;
  final bool twoSided;   // front + back on ONE A4 page (ID / business card)
  final bool multiPage;  // keep collecting pages (passport visas, book)

  static const all = [
    ScanRecipe(ScanKind.document, 'Document', 'Everyday paperwork', Icons.description_outlined, FilterMode.auto),
    ScanRecipe(ScanKind.passport, 'Passport', 'Data page & visas', Icons.menu_book_outlined, FilterMode.auto, multiPage: true),
    ScanRecipe(ScanKind.idCard, 'ID Card', 'Front & back on one page', Icons.badge_outlined, FilterMode.auto, twoSided: true),
    ScanRecipe(ScanKind.receipt, 'Receipt', 'Bills & tickets', Icons.receipt_long_outlined, FilterMode.bw),
    ScanRecipe(ScanKind.invoice, 'Invoice', 'Capture details clearly', Icons.request_quote_outlined, FilterMode.auto),
    ScanRecipe(ScanKind.book, 'Book', 'Flatten pages, remove shadows', Icons.auto_stories_outlined, FilterMode.magicColor, multiPage: true),
    ScanRecipe(ScanKind.whiteboard, 'Whiteboard', 'Boost contrast', Icons.draw_outlined, FilterMode.magicColor),
    ScanRecipe(ScanKind.notes, 'Handwritten', 'Enhance writing', Icons.edit_note_outlined, FilterMode.magicColor),
    ScanRecipe(ScanKind.businessCard, 'Business Card', 'Front & back', Icons.contact_page_outlined, FilterMode.auto, twoSided: true),
  ];

  static ScanRecipe byName(String? n) => all.firstWhere((r) => r.kind.name == n, orElse: () => all.first);
}

/// Gallery "smart collections": kinds grouped under one chip.
class ScanCollection {
  const ScanCollection(this.label, this.kinds);
  final String label;
  final List<String> kinds;

  static const all = [
    ScanCollection('IDs & Passports', ['idCard', 'passport', 'businessCard']),
    ScanCollection('Receipts & Invoices', ['receipt', 'invoice']),
    ScanCollection('Notes', ['notes', 'whiteboard']),
    ScanCollection('Documents', ['document', 'book']),
  ];
}
