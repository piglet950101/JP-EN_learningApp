// Privacy policy, bundled rather than loaded from the web.
// See privacy_policy_text.dart for why, and for the rules its text follows.

import 'package:flutter/material.dart';

import 'privacy_policy_text.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _ink = Color(0xFF1a202c);
  static const _accent = Color(0xFF2b6cb0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(kPrivacyPolicyTitle),
        backgroundColor: Colors.white,
        foregroundColor: _accent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              kPrivacyPolicyIntro,
              style: TextStyle(fontSize: 14, height: 1.7, color: _ink),
            ),
            for (final s in kPrivacyPolicySections) ...[
              const SizedBox(height: 20),
              Text(
                s.heading,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.body,
                style: const TextStyle(fontSize: 14, height: 1.7, color: _ink),
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              kPrivacyPolicyEnacted,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
            ),
          ],
        ),
      ),
    );
  }
}
