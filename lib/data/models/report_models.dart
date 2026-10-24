import 'json_utils.dart';
import 'catalog_models.dart';

Map<String, double> _toDoubleMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((k, v) => MapEntry(k.toString(), toDouble(v)));
}

/// `TodaySummary` from `GET /reports/today`.
class TodaySummary {
  const TodaySummary({
    required this.date,
    required this.salesCount,
    required this.totalSales,
    required this.receivedByMethod,
  });

  final String date;
  final int salesCount;
  final double totalSales;
  final Map<String, double> receivedByMethod;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
        date: toStr(json['date']),
        salesCount: toInt(json['salesCount']),
        totalSales: toDouble(json['totalSales']),
        receivedByMethod: _toDoubleMap(json['receivedByMethod']),
      );
}

/// `DashboardResponse` from `GET /dashboard`.
class Dashboard {
  const Dashboard({
    required this.plan,
    required this.today,
    required this.lowStockCount,
    required this.lowStockItems,
    required this.zraPending,
    required this.zraFailed,
    required this.salesNeedingReview,
    required this.deviceQueuedTransactions,
    required this.reconciliationStatusToday,
  });

  final String plan;
  final TodaySummary today;
  final int lowStockCount;
  final List<Product> lowStockItems;
  final int zraPending;
  final int zraFailed;
  final int salesNeedingReview;
  final int deviceQueuedTransactions;
  final String reconciliationStatusToday;

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        plan: toStr(json['plan'], 'MICRO'),
        today: TodaySummary.fromJson(
            Map<String, dynamic>.from(json['today'] as Map? ?? const {})),
        lowStockCount: toInt(json['lowStockCount']),
        lowStockItems:
            toMapList(json['lowStockItems']).map(Product.fromJson).toList(),
        zraPending: toInt(json['zraPending']),
        zraFailed: toInt(json['zraFailed']),
        salesNeedingReview: toInt(json['salesNeedingReview']),
        deviceQueuedTransactions: toInt(json['deviceQueuedTransactions']),
        reconciliationStatusToday:
            toStr(json['reconciliationStatusToday'], 'NOT_RECONCILED'),
      );
}

/// `DailySalesReport` from `GET /reports/sales/daily`.
class DailySalesReport {
  const DailySalesReport({
    required this.date,
    required this.totalSales,
    required this.totalRevenue,
    required this.totalVat,
    required this.paymentMethodBreakdown,
    required this.topProducts,
  });

  final String date;
  final double totalSales;
  final double totalRevenue;
  final double totalVat;
  final Map<String, double> paymentMethodBreakdown;
  final List<ProductSummary> topProducts;

  factory DailySalesReport.fromJson(Map<String, dynamic> json) =>
      DailySalesReport(
        date: toStr(json['date']),
        totalSales: toDouble(json['totalSales']),
        totalRevenue: toDouble(json['totalRevenue']),
        totalVat: toDouble(json['totalVat']),
        paymentMethodBreakdown: _toDoubleMap(json['paymentMethodBreakdown']),
        topProducts:
            toMapList(json['topProducts']).map(ProductSummary.fromJson).toList(),
      );
}

/// `SalesSummaryReport` from `GET /reports/sales/summary`.
class SalesSummaryReport {
  const SalesSummaryReport({
    required this.from,
    required this.to,
    required this.totalSales,
    required this.totalRevenue,
    required this.totalVat,
    required this.averageOrderValue,
  });

  final String from;
  final String to;
  final double totalSales;
  final double totalRevenue;
  final double totalVat;
  final double averageOrderValue;

  factory SalesSummaryReport.fromJson(Map<String, dynamic> json) =>
      SalesSummaryReport(
        from: toStr(json['from']),
        to: toStr(json['to']),
        totalSales: toDouble(json['totalSales']),
        totalRevenue: toDouble(json['totalRevenue']),
        totalVat: toDouble(json['totalVat']),
        averageOrderValue: toDouble(json['averageOrderValue']),
      );
}

/// `ProductSummary` used by top-product reports.
class ProductSummary {
  const ProductSummary({
    required this.productName,
    required this.totalQuantity,
    required this.totalRevenue,
  });

  final String productName;
  final int totalQuantity;
  final double totalRevenue;

  factory ProductSummary.fromJson(Map<String, dynamic> json) => ProductSummary(
        productName: toStr(json['productName']),
        totalQuantity: toInt(json['totalQuantity']),
        totalRevenue: toDouble(json['totalRevenue']),
      );
}
