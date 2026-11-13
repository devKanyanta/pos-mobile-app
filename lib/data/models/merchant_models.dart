import 'json_utils.dart';

/// `MerchantProfileResponse` from `GET /merchant`.
class MerchantProfile {
  const MerchantProfile({
    required this.accountId,
    required this.businessName,
    required this.tpin,
    required this.phone,
    required this.email,
    required this.address,
    required this.receiptFooter,
    required this.plan,
    required this.features,
  });

  final String accountId;
  final String businessName;
  final String tpin;
  final String phone;
  final String email;
  final String address;
  final String receiptFooter;
  final String plan;
  final Map<String, bool> features;

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'businessName': businessName,
    'tpin': tpin,
    'phone': phone,
    'email': email,
    'address': address,
    'receiptFooter': receiptFooter,
    'plan': plan,
    'features': features,
  };

  bool hasFeature(String name) => features[name] ?? false;

  factory MerchantProfile.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final features = <String, bool>{};
    if (rawFeatures is Map) {
      rawFeatures.forEach((k, v) => features[k.toString()] = toBool(v));
    }
    return MerchantProfile(
      accountId: toStr(json['accountId']),
      businessName: toStr(json['businessName']),
      tpin: toStr(json['tpin']),
      phone: toStr(json['phone']),
      email: toStr(json['email']),
      address: toStr(json['address']),
      receiptFooter: toStr(json['receiptFooter']),
      plan: toStr(json['plan'], 'MICRO'),
      features: features,
    );
  }
}
