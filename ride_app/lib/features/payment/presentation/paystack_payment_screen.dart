import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaystackPaymentScreen extends StatefulWidget {
  const PaystackPaymentScreen({
    required this.rideId,
    required this.fareNaira,
    required this.email,
    super.key,
  });

  final String rideId;
  final int fareNaira;
  final String email;

  @override
  State<PaystackPaymentScreen> createState() => _PaystackPaymentScreenState();
}

class _PaystackPaymentScreenState extends State<PaystackPaymentScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _savingPayment = false;
  String? _error;
  bool _handledCallback = false;

  int get _amountKobo => widget.fareNaira * 100;

  String get _reference =>
      'AFTA-${widget.rideId}-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initializeCheckout();
  }

  Future<void> _initializeCheckout() async {
    final publicKey = dotenv.env['PAYSTACK_PUBLIC_KEY']?.trim() ?? '';
    if (!publicKey.startsWith('pk_test_')) {
      setState(() {
        _loading = false;
        _error = 'Add a Paystack test public key (pk_test_…) to ride_app/.env.';
      });
      return;
    }
    if (widget.email.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Add an email address to your rider account before paying.';
      });
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'AftaPaystack',
        onMessageReceived: (message) => _handlePaystackMessage(message.message),
      );
    _controller = controller;

    try {
      await controller.loadHtmlString(_checkoutHtml(publicKey));
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load Paystack checkout: $error';
        });
      }
    }
  }

  String _checkoutHtml(String publicKey) {
    final payload = jsonEncode({
      'key': publicKey,
      'email': widget.email.trim(),
      'amount': _amountKobo,
      'reference': _reference,
    });
    return '''<!doctype html>
<html lang="en">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f4f7f6; color: #172b27; font: 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    main { width: min(420px, calc(100% - 32px)); padding: 28px; border-radius: 20px; background: white; box-shadow: 0 12px 36px #102a2418; text-align: center; }
    .mark { width: 52px; height: 52px; margin: 0 auto 18px; display: grid; place-items: center; border-radius: 17px; color: white; background: #146b5a; font-size: 25px; font-weight: 800; }
    h1 { margin: 0 0 8px; font-size: 22px; }
    p { margin: 0 0 20px; color: #64716d; line-height: 1.5; }
    button { width: 100%; border: 0; border-radius: 12px; padding: 15px; background: #146b5a; color: white; font: inherit; font-weight: 700; }
    button:disabled { opacity: .6; }
    #message { margin-top: 14px; font-size: 14px; }
  </style>
  <script src="https://js.paystack.co/v1/inline.js"></script>
</head>
<body>
  <main>
    <div class="mark">A</div>
    <h1>Pay for your ride</h1>
    <p>Secure test payment of ₦${widget.fareNaira} ($_amountKobo kobo)</p>
    <button id="pay" onclick="startPayment()">Pay ₦${widget.fareNaira}</button>
    <div id="message"></div>
  </main>
  <script>
    const payment = $payload;
    function send(type, data) {
      AftaPaystack.postMessage(JSON.stringify({ type, ...data }));
    }
    function startPayment() {
      const button = document.getElementById('pay');
      button.disabled = true;
      document.getElementById('message').textContent = 'Opening secure checkout…';
      try {
        const handler = PaystackPop.setup({
          key: payment.key,
          email: payment.email,
          amount: payment.amount,
          ref: payment.reference,
          currency: 'NGN',
          callback: function(response) {
            send('success', { reference: response.reference || payment.reference });
          },
          onClose: function() {
            send('closed', {});
            button.disabled = false;
            document.getElementById('message').textContent = 'Checkout closed. You can try again.';
          }
        });
        handler.openIframe();
      } catch (error) {
        button.disabled = false;
        document.getElementById('message').textContent = 'Could not start checkout. Check your connection and try again.';
        send('error', { message: String(error) });
      }
    }
  </script>
</body>
</html>''';
  }

  Future<void> _handlePaystackMessage(String rawMessage) async {
    if (_handledCallback) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(rawMessage) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (message['type'] != 'success') return;

    final reference = message['reference'] as String?;
    if (reference == null || reference.isEmpty) {
      setState(
        () => _error = 'Paystack did not return a transaction reference.',
      );
      return;
    }

    _handledCallback = true;
    setState(() {
      _savingPayment = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .update({
            'paid': true,
            'paystackReference': reference,
            'paymentStatus': 'success',
            'paidAt': FieldValue.serverTimestamp(),
          });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _handledCallback = false;
      if (mounted) {
        setState(() {
          _savingPayment = false;
          _error = 'Payment succeeded but could not update the ride: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride payment')),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Back to ride'),
                    ),
                  ],
                ),
              ),
            )
          else if (_controller != null)
            WebViewWidget(controller: _controller!),
          if (_loading || _savingPayment)
            ColoredBox(
              color: Colors.white70,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _savingPayment
                          ? 'Updating ride payment…'
                          : 'Loading secure checkout…',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
