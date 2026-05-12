class PaymentRequest {
  final double amount;
  final String currency;
  final String merchantId;
  final String terminalId;
  final Map<String, dynamic>? metadata;

  PaymentRequest({
    required this.amount,
    required this.currency,
    required this.merchantId,
    required this.terminalId,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'currency': currency,
    'merchantId': merchantId,
    'terminalId': terminalId,
    'metadata': metadata,
  };
}
