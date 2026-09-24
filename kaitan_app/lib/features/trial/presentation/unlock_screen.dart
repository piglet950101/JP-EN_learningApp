// Unlock screen — enters a purchase code and (on success) records the unlock
// timestamp in `app_state`.
//
// The input field auto-inserts dashes every 4 chars for a stable
// XXXX-XXXX-XXXX-XXXX layout. The verifier returns a coarse-grained reason
// on failure; the UI shows a single "コードを確認してください" message so
// leaking why (bad length? bad MAC?) doesn't help an attacker.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/providers.dart';
import '../../../data/trial/code_series.dart';
import '../../../data/trial/purchase_service.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _controller = TextEditingController();
  String? _errorMsg;
  bool _busy = false;
  bool _success = false;

  // In-app purchase (iOS only — see showIapProvider).
  ProductDetails? _product;
  bool _productChecked = false;
  StreamSubscription<PurchaseUpdate>? _purchaseSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPurchases());
  }

  Future<void> _initPurchases() async {
    if (!ref.read(showIapProvider)) return;
    final svc = ref.read(purchaseServiceProvider);
    svc.start();
    _purchaseSub = svc.updates.listen(_onPurchaseUpdate);
    final p = await svc.loadProduct();
    if (mounted) {
      setState(() {
        _product = p;
        _productChecked = true;
      });
    }
  }

  Future<void> _onPurchaseUpdate(PurchaseUpdate u) async {
    switch (u.outcome) {
      case PurchaseOutcome.unlocked:
        // Already saved by the purchase service, before the transaction was
        // finished. This screen only shows the result.
        if (!mounted) return;
        setState(() {
          _busy = false;
          _success = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted) context.go('/');
        break;
      case PurchaseOutcome.pending:
        if (mounted) {
          setState(() {
            _busy = true;
            _errorMsg = null;
          });
        }
        break;
      case PurchaseOutcome.cancelled:
        if (mounted) setState(() => _busy = false);
        break;
      case PurchaseOutcome.failed:
        if (mounted) {
          setState(() {
            _busy = false;
            _errorMsg = '購入を完了できませんでした。時間をおいてお試しください。';
          });
        }
        break;
    }
  }

  Future<void> _buy() async {
    final p = _product;
    if (p == null || _busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(purchaseServiceProvider).buy(p);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMsg = '購入を開始できませんでした。';
        });
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    try {
      await ref.read(purchaseServiceProvider).restore();
    } catch (_) {
      // A restore with nothing to restore is not an error worth surfacing.
    }
    // No purchase arrives when there is nothing to restore, so the spinner
    // has to be released here rather than only on the stream.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && !_success) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMsg = null;
    });
    final decision =
        ref.read(unlockVerifierProvider).verify(_controller.text);
    final rejection = unlockRejection(decision,
        standaloneAccepted: ref.read(standaloneCodesAcceptedProvider));
    if (rejection != null) {
      setState(() {
        _busy = false;
        _errorMsg = rejection;
      });
      return;
    }
    await ref
        .read(progressRepoProvider)
        .recordUnlock(codeHash: decision.codeHash!);
    ref.invalidate(unlockedProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _success = true;
    });
    // Small delay so the user sees the confirmation.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(ref.watch(showIapProvider) ? '全機能の解放' : 'アンロックコード入力'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2b6cb0),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _success ? const _SuccessView() : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          // A build that takes only set codes says so: the physical set is
          // what its code field rests on (Guideline 3.1.4).
          ref.watch(standaloneCodesAcceptedProvider)
              ? 'ご購入時にお渡ししたアンロックコードを入力してください。'
              : '教材セットに付属のアンロックコードを入力してください。',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 19, // 16 chars + 3 dashes
          style: const TextStyle(
              fontSize: 20, fontFamily: 'monospace', letterSpacing: 2),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'XXXX-XXXX-XXXX-XXXX',
            hintStyle: const TextStyle(color: Colors.black26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            counterText: '',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
            _DashFormatter(),
          ],
        ),
        if (_errorMsg != null) ...[
          const SizedBox(height: 12),
          Text(_errorMsg!,
              style: const TextStyle(color: Color(0xFFC53030), fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2b6cb0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('アンロック',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        if (ref.watch(showIapProvider)) ...[
          const SizedBox(height: 28),
          Row(children: const [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('または',
                  style: TextStyle(fontSize: 12, color: Colors.black45)),
            ),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),
          // Guideline 3.1.4: the code above is permitted only because this
          // purchase exists. The price comes from StoreKit, already
          // localised and tax-inclusive; never hardcode it.
          if (_product != null)
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _busy ? null : _buy,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2b6cb0), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'アプリ内で購入して全機能を解放　${_product!.price}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2b6cb0)),
                ),
              ),
            )
          else if (_productChecked)
            const Text(
              'ただいま購入の準備ができません。通信状況をご確認のうえ、'
              'しばらくしてから再度お試しください。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 4),
          // Required for non-consumables, and shown even when the product
          // could not be loaded: restoring does not depend on it.
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('以前に購入された方はこちら（購入の復元）',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ],
        const Spacer(),
        Text(
          ref.watch(showIapProvider)
              ? '（購入やコード入力をしなくても、体験版として各ステージのブロック1〜2をご利用いただけます。）'
              : '（コードをお持ちでない場合は、体験版として各ステージのブロック1〜2をご利用いただけます。）',
          style: const TextStyle(fontSize: 11, color: Colors.black45),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.check_circle_rounded,
            color: Color(0xFF38A169), size: 84),
        SizedBox(height: 20),
        Text('全機能がアンロックされました',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF38A169))),
        SizedBox(height: 8),
        Text('スタート画面に戻ります…',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    );
  }
}

/// Insert a dash after every 4 non-dash characters. Upper-case as we go.
class _DashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final plain = newValue.text
        .replaceAll('-', '')
        .toUpperCase();
    final buf = StringBuffer();
    for (var i = 0; i < plain.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(plain[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
