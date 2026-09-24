// The privacy policy shown inside the app.
//
// The same text is published on KAI's website, whose URL is registered with
// both stores. It is bundled here as well, rather than loaded from the web,
// for two reasons:
//   * App Review Guideline 5.1.1(i) requires the policy to be reachable from
//     inside the app. A bundled copy stays reachable if the website is down
//     or being redesigned.
//   * A web view could be navigated onward from the policy to the rest of
//     the site, including any page that sells codes. Both stores forbid the
//     app from leading users to an outside purchase.
//
// Rules for editing, pinned by test/store_release_test.dart:
//   * No URLs. Nothing here may be a way out of the app.
//   * No names of mobile platforms or their stores. The same text ships on
//     iOS and Android, and Guideline 2.3.10 forbids an iOS app from naming
//     other platforms.
//   * The app and the developer must both be named. Google requires one of
//     the two to appear in the policy.

class PolicySection {
  final String heading;
  final String body;
  const PolicySection(this.heading, this.body);
}

const String kPrivacyPolicyTitle = 'プライバシーポリシー';

const String kPrivacyPolicyIntro =
    '一般社団法人KAI（以下「当法人」）は、英単語学習アプリ'
    '「快単パーフェクト［2級〜準1級］」（以下「本アプリ」）における'
    '利用者の情報の取り扱いについて、以下のとおり定めます。';

const List<PolicySection> kPrivacyPolicySections = [
  PolicySection(
    '1. 取得する情報',
    '本アプリは、氏名、メールアドレス、電話番号、位置情報など、'
        '利用者個人を特定できる情報を取得しません。\n'
        'アカウント登録の仕組みはなく、広告、利用状況の分析ツール、'
        'エラー情報の自動送信機能も搭載していません。',
  ),
  PolicySection(
    '2. 端末内に保存される情報',
    '学習の進捗（学習した単語、回答の結果、周回数など）およびロック解除の'
        '状態は、ご利用の端末内にのみ保存され、当法人を含む外部へ送信される'
        'ことはありません。\n'
        'これらの情報は、端末のバックアップ（クラウドへの自動バックアップ等）の'
        '対象外としています。そのため、機種変更やアプリの再インストールを'
        '行った場合、学習の進捗は引き継がれません。',
  ),
  PolicySection(
    '3. アンロックコードについて',
    'アンロックコードの確認は端末内で行われ、入力されたコードが外部へ'
        '送信されることはありません。',
  ),
  PolicySection(
    '4. アプリ内課金について',
    'アプリ内課金による購入は、ご利用のアプリストアの運営事業者が提供する'
        '仕組みを通じて処理されます。お支払いに関する情報を当法人が取得する'
        'ことはありません。',
  ),
  PolicySection(
    '5. 動画の視聴について',
    '「ビデオ解説」では、動画配信サービス Vimeo（Vimeo, Inc.）の動画を'
        '再生します。再生時には Vimeo のサーバーとの通信が行われ、同社の'
        '定める方針に基づき、Cookie 等の情報が利用される場合があります。'
        '詳しくは Vimeo のプライバシーポリシーをご確認ください。\n'
        'また、動画を再生できる状態かどうかを判断するため、端末の通信状態'
        '（インターネットに接続しているかどうか）を確認します。この情報が'
        '外部へ送信されることはありません。',
  ),
  PolicySection(
    '6. 音声の再生について',
    '単語の読み上げには、本アプリに収録した音声、または端末に搭載された'
        '音声読み上げ機能を使用します。',
  ),
  PolicySection(
    '7. 第三者への提供',
    '当法人は、本アプリを通じて利用者の個人情報を取得しないため、'
        '第三者に提供することはありません。',
  ),
  PolicySection(
    '8. 本ポリシーの変更',
    '当法人は、必要に応じて本ポリシーを変更することがあります。'
        '変更後の内容は、当法人のホームページに掲載します。',
  ),
  PolicySection(
    '9. お問い合わせ',
    '一般社団法人KAI\n'
        '〒271-0092 千葉県松戸市松戸1847 日暮ビル501\n'
        '電話：047-701-5800（平日 14:00〜17:00）',
  ),
];

const String kPrivacyPolicyEnacted = '2026年9月24日 制定';
