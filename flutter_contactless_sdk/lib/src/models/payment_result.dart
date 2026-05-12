class PaymentResult {
  final bool success;
  final String? transactionId;
  final String? authCode;
  final String? maskedPan;
  final String? errorMessage;
  final String? errorCode;

  PaymentResult({
    required this.success,
    this.transactionId,
    this.authCode,
    this.maskedPan,
    this.errorMessage,
    this.errorCode,
  });

  factory PaymentResult.success({
    required String transactionId,
    String? authCode,
    String? maskedPan,
  }) => PaymentResult(
    success: true,
    transactionId: transactionId,
    authCode: authCode,
    maskedPan: maskedPan,
  );

  factory PaymentResult.failure({
    required String errorMessage,
    String? errorCode,
  }) => PaymentResult(
    success: false,
    errorMessage: errorMessage,
    errorCode: errorCode,
  );

  Map<String, dynamic> toJson() => {
    'success': success,
    'transactionId': transactionId,
    'authCode': authCode,
    'maskedPan': maskedPan,
    'errorMessage': errorMessage,
    'errorCode': errorCode,
  };
}
