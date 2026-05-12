class CardData {
  final String pan;
  final String expiryDate;
  final String cardholderName;
  final String applicationLabel;
  final String cryptogram;
  final List<int>? cdol1Bytes;

  CardData({
    required this.pan,
    required this.expiryDate,
    required this.cardholderName,
    required this.applicationLabel,
    required this.cryptogram,
    this.cdol1Bytes,
  });

  /// Factory to handle dynamic map initialization
  factory CardData.fromMap(Map<String, dynamic> map) {
    return CardData(
      pan: map['pan'] ?? 'Unknown',
      expiryDate: map['expiryDate'] ?? 'Unknown',
      cardholderName: map['cardholderName'] ?? 'Unknown',
      applicationLabel: map['applicationLabel'] ?? 'Unknown',
      cryptogram: map['cryptogram'] ?? 'Unknown',
      cdol1Bytes: map['cdol1_bytes'] as List<int>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pan': pan,
      'expiryDate': expiryDate,
      'cardholderName': cardholderName,
      'applicationLabel': applicationLabel,
      'cryptogram': cryptogram,
      if (cdol1Bytes != null) 'cdol1_bytes': cdol1Bytes,
    };
  }

  @override
  String toString() {
    return 'CardData(pan: $pan, expiryDate: $expiryDate, '
        'cardholderName: $cardholderName, label: $applicationLabel, '
        'cryptogram: $cryptogram)';
  }
}
