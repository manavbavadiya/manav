import 'package:flutter/material.dart';

import '../../core/network/odoo_client.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

class _FeeRow {
  const _FeeRow({
    required this.name,
    required this.amount,
    required this.balance,
    required this.status,
  });
  final String name;
  final double amount;
  final double balance;
  final String status;
}

class _FeeData {
  const _FeeData({
    required this.rows,
    required this.totalAmount,
    required this.totalBalance,
  });
  final List<_FeeRow> rows;
  final double totalAmount;
  final double totalBalance;
}

/// Fees tab body — hero total-balance summary + per-invoice list. Portal
/// users see only their own rows (server-side ACL).
class FeesTab extends StatefulWidget {
  const FeesTab({super.key});

  @override
  State<FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<FeesTab> {
  late Future<_FeeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FeeData> _load() async {
    try {
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'edu.student.fee',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'fields': const ['name', 'amount', 'balance', 'payment_status'],
          'order': 'id desc',
          'limit': 100,
        },
      );
      final list = [
        for (final r in rows)
          if (r is Map)
            _FeeRow(
              name: r['name']?.toString() ?? 'Invoice',
              amount: (r['amount'] is num)
                  ? (r['amount'] as num).toDouble()
                  : 0,
              balance: (r['balance'] is num)
                  ? (r['balance'] as num).toDouble()
                  : 0,
              status: r['payment_status']?.toString() ?? '',
            ),
      ];
      final totalAmount = list.fold<double>(0, (s, r) => s + r.amount);
      final totalBalance = list.fold<double>(0, (s, r) => s + r.balance);
      return _FeeData(
        rows: list,
        totalAmount: totalAmount,
        totalBalance: totalBalance,
      );
    } catch (_) {
      return const _FeeData(rows: [], totalAmount: 0, totalBalance: 0);
    }
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_FeeData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data =
              snap.data ??
              const _FeeData(rows: [], totalAmount: 0, totalBalance: 0);
          return ListView(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Summary(
                totalAmount: data.totalAmount,
                totalBalance: data.totalBalance,
              ),
              const SizedBox(height: 14),
              if (data.rows.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE1E5EB)),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF17A67A),
                        size: 44,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No fees found',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16324F),
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'You have no pending or past fee records.',
                        style: TextStyle(
                          color: OdooEduColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final r in data.rows) _row(r),
            ],
          );
        },
      ),
    );
  }

  Widget _row(_FeeRow r) {
    final paid = r.status == 'paid';
    final overdue = r.status == 'overdue';
    final tint = paid
        ? const Color(0xFF17A67A)
        : (overdue ? OdooEduColors.danger : OdooEduColors.warning);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              paid ? Icons.check : Icons.receipt_long,
              color: tint,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF16324F),
                  ),
                ),
                Text(
                  r.status.isEmpty ? '—' : r.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: tint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${r.balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: paid
                      ? const Color(0xFF17A67A)
                      : const Color(0xFF16324F),
                ),
              ),
              Text(
                'of ₹${r.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: OdooEduColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.totalAmount, required this.totalBalance});
  final double totalAmount;
  final double totalBalance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF875A7B), Color(0xFF5E3F55)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outstanding Balance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${totalBalance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Total invoiced: ₹${totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
