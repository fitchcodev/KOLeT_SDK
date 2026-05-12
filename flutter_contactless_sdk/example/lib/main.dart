import 'package:flutter/material.dart';
import 'package:flutter_contactless_sdk/contactless_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isNfcAvailable = false;
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    _checkNfcStatus();
  }

  Future<void> _checkNfcStatus() async {
    final available = await ContactlessSDK.isNfcAvailable();
    setState(() {
      _isNfcAvailable = available;
    });
  }

  Future<void> _startPayment() async {
    setState(() {
      _status = 'Starting Payment Session...';
    });

    final result = await ContactlessSDK.startPayment(PaymentRequest(
      amount: 45.0,
      currency: 'USD',
      merchantId: 'M_LOCAL_TEST',
      terminalId: 'T_LOCAL_001',
    ));

    setState(() {
      if (result.success) {
        _status = 'Success: ${result.transactionId}\nAuth: ${result.authCode}';
      } else {
        _status = 'Failed: ${result.errorMessage}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Contactless SDK Test'),
          backgroundColor: Colors.indigo,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isNfcAvailable ? Icons.nfc : Icons.nfc_outlined,
                size: 80,
                color: _isNfcAvailable ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 20),
              Text(
                _isNfcAvailable ? 'NFC Hardware Ready' : 'NFC Hardware Disabled',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Status: $_status',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isNfcAvailable ? _startPayment : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: const Text('Start Payment Session'),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: _isNfcAvailable ? _scanCard : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: const Text('Read EMV Card Directly'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanCard() async {
    setState(() {
      _status = 'Initializing Scanner...';
    });

    final card = await ContactlessSDK.readCardDetails(
      onStatusUpdate: (String update) {
        setState(() {
          _status = update;
        });
      },
    );

    if (card != null) {
      setState(() {
        _status = 'Success!\nPAN: ${card.pan}\nExp: ${card.expiryDate}\nName: ${card.cardholderName}\nApp: ${card.applicationLabel}';
      });
    }
  }
}
