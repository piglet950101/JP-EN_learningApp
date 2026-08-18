// Unlock screen — enters a purchase code and (on success) records the unlock
// timestamp in `app_state`.
//
// The input field auto-inserts dashes every 4 chars for a stable
// XXXX-XXXX-XXXX-XXXX layout. The verifier returns a coarse-grained reason
// on failure; the UI shows a single "コードを確認してください" message so
// leaking why (bad length? bad MAC?) doesn't help an attacker.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';

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

  @override
  void dispose() {
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
    if (!decision.ok) {
      setState(() {
        _busy = false;
        _errorMsg = 'コードを確認してください。';
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
        title: const Text('アンロックコード入力'),
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
        const Text(
          'ご購入時にお渡ししたアンロックコードを入力してください。',
          style: TextStyle(fontSize: 14, color: Colors.black87),
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
        const Spacer(),
        const Text(
          '（コードをお持ちでない場合は、体験版として各ステージのブロック1〜2をご利用いただけます。）',
          style: TextStyle(fontSize: 11, color: Colors.black45),
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
