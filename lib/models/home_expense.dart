import 'package:flutter/foundation.dart';

/// A recorded maintenance or repair cost for a home item.
@immutable
class HomeExpense {
  const HomeExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
  });

  final String id;
  final String description;
  final double amount;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
    'date': date.toIso8601String(),
  };

  factory HomeExpense.fromJson(Map<String, dynamic> json) => HomeExpense(
    id: json['id'] as String,
    description: json['description'] as String,
    amount: (json['amount'] as num).toDouble(),
    date: DateTime.parse(json['date'] as String),
  );
}
