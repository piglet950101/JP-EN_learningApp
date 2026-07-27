# 快単アプリ Phase 2 実装計画 v1.0

**対象範囲**: Second Stage / 体験版 / Vimeoビデオ連携
**期間目安**: 2026-07-07 〜 2026-08-30（約8週間）
**リリース目標**: 2026年9月 高校生2学期開始
**作成日**: 2026-07-06
**作成者**: AKAME

---

## 0. エグゼクティブサマリー

Phase 2 は Phase 1 で完成した「快単」の基盤の上に、3つの独立した機能を追加する。

| # | Deliverable | 契約金額 | クリティカルパス依存 |
|---|---|---|---|
| 1 | Second Stage（派生語・類義語・活用ドリル） | ¥250,000 | 落合様のSSデータ提供（7月中旬以降） |
| 2 | 体験版（アンロックコード方式） | ¥100,000 | なし。即着手可能 |
| 3 | Vimeoビデオ連携 | ¥50,000 | クライアントによるVimeoアップロード＋URLリスト提供 |
| **計** | | **¥400,000 (税抜)** | |

**並行実行戦略**: 3つのDeliverableは互いにデータレイヤ・UI画面が独立しているため、SSデータ待ち期間中に体験版とVimeo枠組みを先行実装できる。落合様データ着次第、SSデータ取り込みと最終調整のみで動作確認版が仕上がる状態を目指す。

**Phase 1 資産の再利用**: `MantenhoEngine`（満点法状態機械）、`ProgressDb`（drift/SQLite）、`SessionScreen` の UI パーツ、`TtsService` はすべて Phase 2 でも共有利用する。ゼロからの再設計は行わない。

---

## 1. 前提と制約

### 1.1 継承する Phase 1 制約（実物確認済み）
- Flutter 3.44 / Dart SDK ^3.12.0（`pubspec.yaml` env sdk 確認）
- **Riverpod v3.3.1**（`flutter_riverpod: ^3.3.1`、v2ではない — 契約書上はv2表記だが実装はv3）
- drift 2.33.0 + SQLite（content.db 読取専用 + progress.db 書込可能の2DB分離）
- go_router 17.2.3 ナビゲーション（`main.dart` は `MaterialApp.router` + `routerProvider`）
- flutter_tts 4.2.5
- **完全オフライン / on-device / 通信なし / テレメトリなし**
- 現行 `applicationId = "jp.or.kai.kaitan"`（Android/iOS共通で流用予定）

### 1.2 Phase 2 で新規追加する外部依存（`pubspec.yaml` 未追加、全て新規）
- `webview_flutter` ^4.x（Vimeo埋込用。**現行 pubspec には未追加、新規追加が必要**）
- `crypto` ^3.x（体験版コード検証、HMAC-SHA256。**新規追加**）
- `connectivity_plus` ^6.x（Vimeoオフライン判定、**新規追加**）
- 上記3つ以外は追加しない方針。依存を最小限に抑える。

### 1.3 データソース
- **Second Stage**: `Second stage基本データ検討表.xlsx`（落合様が今後拡充、7月中旬〜）
- **体験版**: アンロックコードは AKAME 側のオフラインCLIツールで発行
- **Vimeo**: クライアントがVimeoにアップロード、URL一覧を提供

### 1.4 プラットフォーム制約
- 初期リリースは Android のみ（iOS はビルド環境未整備、Phase 2 終了後）
- WebView は Vimeo 埋込プレイヤー経由（動画ダウンロード・オフライン再生は非対応）
- iOS 対応時は ATS（App Transport Security）設定で vimeo.com を許可する

---

## 2. Deliverable 1 — Second Stage（¥250,000）

### 2.1 客户のSSデータ仕様（Excelから読み解いた内容）

`Second stage基本データ検討表.xlsx`（第3ブロック分のパイロット・r2 の client 記述凡例含む）の分析により、Second Stage は以下の構造を持つ **リレーショナル・ドリル** である。

**基本構造**: Phase 1 の2,201語（見出し語）1つに対して、**0..N 個の Second Stage エントリ**を紐付ける。エントリはすべて「見出し語との関係」を持つ。客户記述：「この数はブロックごとに変わる」。

**関係タイプ（問題列、r2 凡例より15種を再確認）**:

| コード | 意味 | 例 | 出現想定 |
|---|---|---|---|
| `類` | 類義語 | diversity → variety | 高頻度 |
| `反` | 反意語 | loose → tight | 中頻度 |
| `前` | セットになる前置詞 | abstain → abstain from | 中頻度 |
| `熟` | 熟語 | indifferent → be indifferent to | 中頻度 |
| `活` | 動詞活用 | lay > laid > laid | lay/lie類 |
| `品` | 品詞（他動詞/自動詞など） | lay → 他動詞 | 少数 |
| `法` | 語法 | 個別ケース | 少数 |
| `複` | 複数形 | 個別ケース | 少数 |
| `同音` | 同音異義語 | 個別ケース | 少数 |
| `セ` | セットフレーズ | 個別ケース | 少数 |
| `意味(N)` | N番目の意味を問う（N=2,3,4...） | defer → 従う | 少数（parametric） |
| `名` | 名詞派生形 | maintain → maintenance | 高頻度 |
| `形` | 形容詞派生形 | diversity → diverse | 高頻度 |
| `副` | 副詞派生形 | (少数) | 低頻度 |
| `動` | 動詞派生形 | (少数) | 低頻度 |
| 関連語＋関係 | 見出し語の関連語に対する問題 | fertile → `fertilizer の意` | 少数 |

**注意事項**:
- 「意味(2)」「意味(3)」の (N) は動的数値。ハードコードではなく数値パースが必要。
- 「関連語＋関係」パターンは `問題` 列に `fertilizer の意` のように「関連語 + 関係コード」複合表記で入る場合がある。パーサで正規化する。
- 「意味の (2)」と「品詞 (2)」は混同注意（前者は Phase 2 の SS 出題種別、後者は Phase 1 words.json の meaning_mode=either_ok マーカー）。

**各エントリの構造**（Excel 列 B-I）:
- 見出し語番号（Phase 1 word の id と1:1対応）
- 英単語（Phase 1 の word と重複、参照用）
- 品詞（Phase 1 と重複）
- 意味（Phase 1 と重複、または関係先の意味）
- 問題（関係タイプ）
- 解答（関係先の語句、または品詞マーカー、または活用形）
- 意味（関係先の意味 — 「解答」の日本語訳）
- 音声（TTS 読上げ可否フラグ、TRUE/FALSE）

**特殊ケース**:
- 「活」（活用）は `lay > laid > laid` のような3語連続表記
- 「品」（品詞マーカー）は問題自体が「他動詞」「自動詞」というテキスト
- 「意２」は同一見出し語の第2の意味を答えさせる形式
- 個別ノート（`fertilizer の意`, `名（前）`）はケースバイケース

### 2.2 データモデル設計

**採用方針**: Phase 1 の `words.json` を拡張するのではなく、**独立した `second_stage.json` として分離バンドル**する。理由：
1. Phase 1 の words.json は既に安定しており、SS追加による再検証コストを避ける
2. SSデータは客户が今後も継続的に更新するため、独立管理が保守しやすい
3. 体験版で SS を無効化する場合の切り分けが容易になる

**スキーマ (`assets/content/second_stage.json`)**:

```json
{
  "schema_version": 1,
  "sources": ["Second stage基本データ検討表.xlsx (2026-XX-XX)"],
  "count": 1234,
  "stats": {
    "by_relation": {"類": 220, "反": 45, "前": 180, "名": 260, "形": 240, "副": 15, "熟": 90, "品": 24, "活": 24, "意２": 8, "その他": 12},
    "by_block": {"1": 26, "2": 31, ...},
    "with_tts_enabled": 987,
    "with_meaning": 890
  },
  "entries": [
    {
      "id": 1,
      "word_id": 97,
      "vol": 1,
      "block": 3,
      "relation": "類",
      "prompt": null,
      "answer": "variety",
      "answer_meaning": null,
      "tts_enabled": true,
      "notes": null
    },
    {
      "id": 2,
      "word_id": 97,
      "vol": 1,
      "block": 3,
      "relation": "形",
      "prompt": null,
      "answer": "diverse",
      "answer_meaning": "様々な",
      "tts_enabled": true,
      "notes": null
    },
    // 活用の例
    {
      "id": 300,
      "word_id": 133,
      "vol": 1,
      "block": 3,
      "relation": "活",
      "prompt": "他動詞",
      "answer": "lay > laid > laid",
      "answer_meaning": null,
      "tts_enabled": false,
      "notes": "conjugation triple"
    }
  ]
}
```

**Dart 側モデル (`lib/data/second_stage.dart`)**:

```dart
enum SecondStageRelation {
  synonym('類'),          // 類義語
  antonym('反'),          // 反意語
  preposition('前'),      // 前置詞
  idiom('熟'),            // 熟語
  conjugation('活'),      // 動詞活用
  posMarker('品'),        // 品詞
  usage('法'),            // 語法
  plural('複'),           // 複数形
  homophone('同音'),      // 同音異義語
  setPhrase('セ'),        // セットフレーズ
  meaningN('意味'),       // 意味(N) — n を別フィールドで保持
  nounForm('名'),         // 名詞派生
  adjForm('形'),          // 形容詞派生
  advForm('副'),          // 副詞派生
  verbForm('動'),         // 動詞派生
  relatedWord('関連');    // 関連語＋関係 (e.g., fertilizer の意)
  final String code;
  const SecondStageRelation(this.code);
}

class SecondStageEntry {
  final int id;
  final int wordId;         // Phase 1 word.id への外部キー
  final int vol;
  final int block;
  final SecondStageRelation relation;
  final int? meaningIndex;  // 意味(N) の N。relation=meaningN 以外は null
  final String? relatedWord; // 関連語ケースの語（例: "fertilizer"）
  final String? prompt;      // 品/法などのマーカー文字列
  final String answer;
  final String? answerMeaning;
  final bool ttsEnabled;
  final String? notes;
}

class SecondStageRepository {
  int get count;
  List<int> allBlocks();
  List<SecondStageEntry> byBlock(int block);
  List<SecondStageEntry> byWordId(int wordId);
}
```

### 2.3 Second Stage 出題ロジック（エンジン設計）

**重要な発見**: 既存の `MantenhoEngine`（`lib/features/session/domain/engine.dart`）は **既に完全に ID ベース**で実装されている。`SessionState.queue` と `rechecks` はいずれも `List<int>`、`answer()` と `advance()` も `int` ID を返すのみ。`Word` オブジェクトへの依存はゼロ。

**結論**: **エンジンの改修は不要**。ジェネリック化も `Questionable` インタフェースも不要。SS の エントリ ID（`entry.id`）をそのまま `MantenhoEngine.start()` に渡すだけで動く。

**唯一の設計判断**: Word の id 空間（1..2201）と SS の entry.id 空間が衝突するため、UI 側での ID → 表示オブジェクト解決は `stage` 判定で分岐する:

```dart
// UIレンダリング側で:
final displayable = switch (currentStage) {
  kStageFirst  => wordRepo.byId(currentId),
  kStageSecond => ssRepo.byId(currentId),
  _ => null,
};
```

**progress.db の状態**（実物確認済み）:
- 現行 `schemaVersion = 1`
- 3 テーブル: `word_progress`, `block_state`, `stage_progress`
- **既に `stage` TextColumn を全テーブルに保持** — Phase 1 設計時点で Stage 分離を先読み済み
- Second Stage の永続化は `stage = 'second'` の新値を書くだけで対応可
- **スキーマ変更は不要**（体験版の `app_state` テーブル追加のみ、後述 §5.3）

**追加が必要な定数** (`lib/data/progress/progress_repository.dart`):
```dart
const String kStageFirst = 'first';
const String kStageSecond = 'second';   // 新規追加
```

### 2.4 出題フォーマット（UI）

SSの出題は Phase 1 の1問1画面フラッシュカード方式ではなく、**関連リストのタテ並び表示**（客户仕様「複数問題タテ並び」）。

**画面 ⑥' (Second Stage 問題画面)**:

```
┌────────────────────────────────┐
│  1巡目  ●  リタイヤ            │  ← 上帯（Phase 1流用）
├────────────────────────────────┤
│  № 0097                        │
│  diversity  🔊                 │  ← 見出し語（大）
│  名  多種多様                  │
├────────────────────────────────┤
│ 【類】 [ 意味・答え ]           │  ← 関連問題1
│ 【形】 [ 意味・答え ]           │  ← 関連問題2
│ 【 動詞活用など複数あれば全て】│
├────────────────────────────────┤
│           [ 意味・答え ]        │  ← 大ボタン
└────────────────────────────────┘
```

**画面 ⑦' (Second Stage 解答画面)**:

```
┌────────────────────────────────┐
│  № 0097                        │
├────────────────────────────────┤
│  diversity                     │
│  名  多種多様                  │
├────────────────────────────────┤
│ 【類】variety                  │
│ 【形】diverse  様々な          │  ← 意味併記
├────────────────────────────────┤
│  [   OK   ]  [ 再チェック ]     │  ← 判定は見出し語単位
└────────────────────────────────┘
```

**判定単位**: 1画面 = 1見出し語 = 1エントリ群。OK/再チェックの判定は見出し語単位で行い、周回状態は Phase 1 と同じ満点法で管理する。

**未確定事項（客户確認要）**:
- 見出し語にSSエントリが1つも紐付かない場合の扱い → Second Stage の出題対象から除外する（デフォルト）
- 見出し語間の順序 → 見出し語 id 昇順（Phase 1 と同順）
- TTS 音声フラグ `False` のエントリで解答画面のスピーカーを押した場合 → ボタン自体を非表示

### 2.5 範囲指定画面（⑤')

**実物確認**: 既存の `RangeScreen`（`lib/features/range_select/range_screen.dart`）は現状 `kStageFirst` をハードコード（`_selected` の永続化・進捗表示すべて）。

**変更内容**:
1. `RangeScreen(stage: kStageFirst | kStageSecond)` にコンストラクタ引数を追加
2. `progressRepoProvider` の呼び出しを渡された stage で行うようリファクタ
3. Second Stage 時は「SS エントリを持たないブロックをグレーアウト（`ssRepo.allBlocks()` を参照）
4. `PendingSessionArgs.stage` に渡された stage を書き込む（既に stage フィールド存在、値だけ切替え）

**⑤(Stage選択) 画面の変更**:

**実物確認**: 既存の `start_screen.dart` に Second Stage の「準備中」カードは **既に実装済み**（line 143 に `SnackBar('Second Stage は準備中です')`、line 255 に `Text('準備中')` ボタン）。

**変更内容**: 既存の「準備中」カードを **アクティブ化**するのみ。
1. 「準備中」ラベルを削除
2. カードタップ時に `context.push('/range?stage=second')` へ遷移（または `PendingSessionArgs.stage = kStageSecond` セット後 `/range` へ）
3. Second Stage の累計 lap カウント表示を追加（既存の `lapCountProvider(kStageFirst)` パターンを踏襲）

### 2.6 特殊ケース対応

**「活」（動詞活用）**:
出題形式は「lay の他動詞形の活用は？」→ 解答 `lay > laid > laid` の表示。
- TTS: 3語を「原形 過去形 過去分詞形」の順に読み上げ（`>` は無音区切り）
- 表示: 単色モノスペース風フォントで `lay > laid > laid`

**「品」（品詞マーカー）**:
lay/lie/underlie/rise/raise/arise/arouse の混同セットに対して「これは他動詞？自動詞？」の判別問題。
- prompt 列に `他動詞` または `自動詞` が入る
- 出題時は見出し語のみ表示 → 解答時に「他動詞」ラベルを表示

**「意２」**:
同一見出し語の第2の意味を答えさせる。単独の出題ではなく、他のSSエントリと合わせて「見出し語 diversity の関連問題群」として表示される。

### 2.7 発音（TTS）取り扱い

- Phase 1 の `TtsService` をそのまま利用
- SS の各エントリの `tts_enabled` フラグを尊重（False の場合はスピーカーボタン非表示）
- Phase 1 で実装済みのカタカナ発音ヒント（14語）は見出し語再生時に自動的に適用される（相互作用なし）

### 2.8 Excel インポーターの拡張

`tool/import_excel.py` の兄弟スクリプトとして `tool/import_second_stage.py` を新規作成。

**責務**:
1. `Second stage基本データ検討表.xlsx` を読取
2. 各行を SecondStageEntry に変換（B列の見出し語番号を親キーとして紐付け）
3. 関係タイプの正規化（`類`, `反`, `前`, `名`, `形`, `副`, `熟`, `品`, `活`, `意２`, その他）
4. `answer` フィールドの前後空白除去、全角スペース処理
5. `tts_enabled` フラグの正規化（True/False/空欄 → bool）
6. `assets/content/second_stage.json` を出力
7. 統計サマリを stdout に出力（by_relation, by_block, missing_word_id 参照など）

**バリデーション**:
- `word_id` が Phase 1 words.json に存在しない → error
- 空欄の `answer` → warning（除外）
- 未知の関係タイプ → warning（`その他` として取込）

### 2.9 Second Stage のテスト戦略

**単体テスト**:
- `SecondStageRepository.byBlock()` の正しさ
- 関係タイプの列挙型変換
- word_id 外部キー整合性チェック

**エンジンテスト**:
- `MantenhoEngine<SecondStageQuestion>` の周回動作
- OK/再チェック → 満点法判定が First Stage と同挙動であること

**ウィジェットテスト**:
- SS 出題画面のタテ並び表示レイアウト
- 音声フラグ False 時のスピーカー非表示
- 「活」「品」「意２」の特殊表示
- 見出し語にSSが1つも無い場合の除外動作

**E2E テスト**:
- ⑤ Stage選択 → Second Stage カードタップ → ⑤' → ⑥' → ⑦' → OK → 次問 → 満点法完了 → ⑩'

**目標追加テスト数**: 25項目（Phase 1 の 61 → 86 に増加）

---

## 3. Deliverable 2 — 体験版（¥100,000）

### 3.1 コンセプトと境界の定義

**未確定事項の暫定決定**（客户確認要）:
- 体験版 = **同一 APK の trial モード**（別ビルド不要、フラグで切替）
- trial モードでは **First Stage の第1〜3ブロック（№1〜144）のみアクセス可能**、Second Stage と Vimeo は非表示
- **アンロックコード**を入力すると **永続的に全機能アンロック**（デバイス単位、期限なし）
- コードは購入者に1つずつ発行、**単発利用**（同一コード再入力可、複数デバイス利用は事実上制限しない）

### 3.2 アンロックコード方式の設計

**技術オプション比較**:

| 方式 | 実装コスト | 破られやすさ | オフライン耐性 |
|---|---|---|---|
| A. 静的リスト（APK内埋込） | 低 | 中（APK解析で全コード漏洩） | ◎ |
| B. HMAC-SHA256 短コード | 中 | 中（秘密鍵APK内） | ◎ |
| C. Ed25519 署名コード | 高 | 低（公開鍵APK内、秘密鍵はAKAME保持） | ◎ |

**採用**: **B. HMAC-SHA256 短コード方式**

理由：
1. 教育向けアプリの単価と発行数（数百〜数千枚想定）に対して過剰なセキュリティは不要
2. Ed25519 は署名長が長すぎ、ユーザー入力に不向き（最短でも Base32 で40文字超）
3. HMAC 方式なら 16文字（Base32、80bit）で十分な衝突耐性
4. 秘密鍵がAPKから抽出されるリスクは、コード再発行という運用対応で吸収可能

**コード生成アルゴリズム**:

```
入力: purchase_id (発行連番、64bit)
      key_version (現行の秘密鍵バージョン、8bit)
      secret (HMAC鍵、256bit、AKAME保持)
処理:
  1. payload = key_version(1B) || purchase_id(8B) = 9 bytes
  2. mac = HMAC-SHA256(secret, payload)[:7]  # 上位7バイト = 56bit
  3. code_bytes = payload || mac = 16 bytes
  4. code_str = Base32(code_bytes).strip('=')  # 26文字 → 4文字ずつダッシュ区切りで整形
  5. 表示例: XXXX-XXXX-XXXX-XXXX-XXXX-XX

または Base58 でより短く: 22文字前後
```

**代替コンパクト方式**（短さ優先）:
- payload = purchase_id(4B) || key_version(1B) = 5 bytes
- mac = HMAC[:5] = 5 bytes
- code = Base32(10 bytes) = 16文字 → `XXXX-XXXX-XXXX-XXXX`

→ **こちらを採用**。16文字、`XXXX-XXXX-XXXX-XXXX` の形式でユーザー入力コストが許容範囲。

### 3.3 コード生成CLI (`tool/generate_codes.py`)

**責務**:
1. `codes_state.json` に発行済み purchase_id 連番を記録
2. コマンド `python generate_codes.py --count 50` で新規50コードを生成
3. 生成されたコードを CSV 出力（列: code, purchase_id, generated_at, key_version）
4. 秘密鍵は `~/.kaitan/codegen.key` に保存（APKには含めない）

**AKAME 用ワークフロー**:
- 客户から購入発生 → AKAME に「N枚発行」依頼
- AKAME が `generate_codes.py --count N` 実行
- CSV 客户にメール送付
- 客户が購入者に配布

### 3.4 アプリ側の検証と永続化

**アプリ内の秘密鍵**:
- 秘密鍵は **難読化した文字列定数** として `lib/data/trial/_secret.dart` に埋込
- ソースコード上で「見た目わからないよう」定数分割、XOR、Base64重ね等の軽い難読化
- （注：これは Attack-in-Depth ではなく "casual reverse-engineering deterrent"）

**検証ロジック** (`lib/data/trial/unlock_verifier.dart`):

```dart
class UnlockVerifier {
  static const _keyVersions = {1: _obfuscatedKeyV1};

  bool verify(String userInput) {
    // 1. 正規化: ダッシュ除去、大文字化
    final normalized = userInput.replaceAll('-', '').toUpperCase();
    if (normalized.length != 16) return false;
    // 2. Base32デコード
    final bytes = _base32Decode(normalized);
    if (bytes.length != 10) return false;
    // 3. payload と mac 分離
    final payload = bytes.sublist(0, 5);
    final mac = bytes.sublist(5, 10);
    // 4. key_version 抽出
    final kv = payload[4];
    final key = _keyVersions[kv];
    if (key == null) return false;
    // 5. HMAC 検証
    final expected = Hmac(sha256, key).convert(payload).bytes.sublist(0, 5);
    return _constantTimeEquals(expected, mac);
  }
}
```

**永続化**:
- 検証成功時、`progress.db` の `app_state` テーブルに `unlocked_at`（epoch秒）を保存
- アプリ起動時に `app_state.unlocked_at IS NOT NULL` チェック → trial/full モード分岐
- 一度アンロックされたら再検証不要（コード再入力を毎回求めない）

### 3.5 UX 設計（未アンロック時の見え方）

**トップ画面 (start_screen.dart)**:
- Second Stage カード → グレーアウト + 鍵アイコン + タップで「アンロックコード入力」画面へ
- First Stage カード → 「体験版：ブロック1〜3のみ利用可能」バッジ表示
- Vimeo タブ → 非表示

**範囲指定画面 (range_select_screen.dart)**:
- 未アンロック時、ブロック4〜46 をグレーアウト + 「アンロックで解放」ラベル

**アンロック入力画面（新規）**:
- コード入力フィールド（4文字ごとダッシュ自動挿入）
- 「アンロック」ボタン
- エラー時：「コードを確認してください」（詳細エラー理由は隠す）
- 成功時：「全機能がアンロックされました」→ 3秒後にトップに戻る

### 3.6 セキュリティトレードオフ

**認めるリスク**:
1. **APK 逆コンパイル + 秘密鍵抽出** → 悪意ある第三者が偽コード生成可能
2. **1コード複数デバイス使用** → 検知しない（サーバー無し前提のため）

**対策方針**:
1. リスク1: **key_version の運用**。漏洩発覚時は新しい key_version で秘密鍵ローテーション、旧バージョンのコードは新規発行停止（既存有効コードはそのまま使える）
2. リスク2: 対策不要（ビジネスモデル上、教育機関単位の購入で1コード1家庭の想定）

### 3.7 体験版のテスト戦略

**単体テスト**:
- HMAC 検証の positive/negative（正しいコード / 改竄コード / 空 / 過長 / 短小）
- key_version 未サポート時の拒否
- 定数時間比較の実装確認（timing attack 対策）

**ウィジェットテスト**:
- 未アンロック時の Second Stage カードグレーアウト
- 未アンロック時の第4〜46ブロックグレーアウト
- コード入力画面のダッシュ自動挿入
- アンロック成功 → トップ再描画で全機能表示

**E2E テスト**:
- trial モード起動 → コード入力 → 検証成功 → Second Stage 利用可能

**目標追加テスト数**: 15項目

---

## 4. Deliverable 3 — Vimeoビデオ連携（¥50,000）

### 4.1 データモデル

**方針**: `assets/content/videos.json` として独立バンドル。Vol.1 と Vol.2 で構成する見出し語ブロックに動画を紐付ける。

**スキーマ**:

```json
{
  "schema_version": 1,
  "count": 46,
  "entries": [
    {
      "id": 1,
      "block": 1,
      "vol": 1,
      "title": "ブロック1 解説（No.1〜48）",
      "vimeo_id": "1234567890",
      "vimeo_hash": "abc123def",
      "duration_sec": 720,
      "thumbnail_local": null
    }
  ]
}
```

- `vimeo_id`: Vimeo の動画ID（公開設定または埋込限定設定）
- `vimeo_hash`: プライベート動画のハッシュ（あれば）
- `duration_sec`: 表示用（Vimeo API から事前取得しておく、実行時APIは呼ばない）
- `thumbnail_local`: サムネイル画像のバンドル asset パス（あれば表示、なければ Vimeo デフォルト表示）

**Vimeo URL 形式**:
- 埋込プレイヤー URL: `https://player.vimeo.com/video/{vimeo_id}?h={vimeo_hash}&autoplay=0`
- プライバシー: 客户が「hide from vimeo.com + embed on selected sites」設定推奨。ドメイン許可リストは kaitan-app が独自ドメインを持たないため実質「どこでも埋込可」設定になる

### 4.2 WebView プレイヤー設計

**採用パッケージ**: `webview_flutter` 4.x（既に Phase 1 で予備実装済み）

**画面構成**:

```
┌────────────────────────────────┐
│  ← ブロック1 解説              │  ← AppBar
├────────────────────────────────┤
│                                │
│    [ Vimeo プレイヤー 16:9 ]   │
│                                │
├────────────────────────────────┤
│  総時間: 12分00秒              │
│  この動画で扱う語彙:            │
│  1. absorb  2. scatter  ...    │
│                                │
│  [ このブロックの学習を開始 ]   │
└────────────────────────────────┘
```

**実装ポイント**:
- WebView は動画部分のみ、下の情報エリアは Flutter ネイティブ
- 動画からブロックの単語学習にワンタップで導線
- 全画面再生は Vimeo プレイヤーの機能に任せる（Flutter 側で fullscreen 制御しない）

### 4.3 動画一覧画面

**構成**: 底部タブに「ビデオ」を追加、または start_screen から「ビデオ一覧」ボタンで遷移。

**表示形式**:
- ブロック順のカードリスト
- 各カード: サムネイル（あれば）+ タイトル + 総時間 + 再生ボタン
- **オフライン時**: 「インターネット接続が必要です」を各カードに表示、タップ不可

### 4.4 オフライン時のグレースフルデグラデーション

**方針**: アプリ本体は完全オフラインで動作するが、動画再生時のみネットワークが必要である旨を明示。

**判定タイミング**:
- 動画一覧画面表示時に `connectivity_plus` で状態チェック → 「オフライン」バナー表示
- 動画詳細画面遷移時に再判定
- WebView 読み込みエラー時は「動画が読み込めませんでした。ネットワーク接続を確認してください」

**依存追加**: `connectivity_plus` を pubspec.yaml に追加（唯一の新規依存）

### 4.5 ナビゲーション統合

**go_router 拡張**:

```dart
GoRoute(path: '/videos', name: 'video_list',
  builder: (c, s) => const VideoListScreen()),
GoRoute(path: '/videos/:id', name: 'video_detail',
  builder: (c, s) => VideoDetailScreen(id: int.parse(s.pathParameters['id']!))),
```

**トップ画面変更**:
- start_screen に「ビデオ解説を見る」ボタン追加

### 4.6 iOS対応（Phase 2 完了後の追加作業として）

iOS ビルド時に必要な追加設定：
- `Info.plist` の `NSAppTransportSecurity` で Vimeo ドメインを許可
- WKWebView の `allowsInlineMediaPlayback` 有効化
- Vimeo 埋込動画のフルスクリーン挙動テスト（Android と挙動差あり）

### 4.7 テスト戦略

**単体テスト**:
- videos.json スキーマ検証
- Vimeo URL 組立ロジック

**ウィジェットテスト**:
- 動画一覧のブロック順表示
- オフライン時のバナー表示
- 動画詳細画面の情報エリア（実際のWebView描画はモック）

**E2E**（限定的）:
- 動画一覧 → 動画詳細タップ → 情報表示（WebView実描画はスキップ、`WebViewController` モック）

**目標追加テスト数**: 10項目

---

## 5. Phase 1 既存コードへの影響

### 5.1 変更を要する既存ファイル（実物確認済み）

| ファイル | 変更内容 | 影響度 |
|---|---|---|
| `lib/features/session/domain/engine.dart` | **変更不要**（既にIDベース） | ゼロ |
| `lib/features/start/start_screen.dart` | 既存の Second Stage「準備中」カードを アクティブ化、Videoリンク追加 | 小 |
| `lib/features/range_select/range_screen.dart` | `stage` 引数追加、進捗DBアクセスを引数stage経由に | 中 |
| `lib/features/session/presentation/session_screen.dart` | stage 判定で SS/FS レンダラを切替 | 中 |
| `lib/features/session/presentation/session_controller.dart` | `ssRepoProvider` 追加、stage 判定 | 中 |
| `lib/data/progress/progress_db.dart` | `app_state` テーブル追加のみ (v1 → v2 マイグレーション) | 小 |
| `lib/data/progress/progress_repository.dart` | `kStageSecond` 定数追加、app_state 用リポジトリメソッド追加 | 小 |
| `lib/core/providers.dart` | SS Repository, Video Repository, Unlock Verifier のProvider追加、`/videos` `/unlock` ルート追加 | 小 |

### 5.2 追加する新規ファイル（想定）

```
lib/
  data/
    second_stage.dart               # SecondStageEntry, SecondStageRepository
    video.dart                      # VideoEntry, VideoRepository
    trial/
      unlock_verifier.dart          # HMAC検証
      _secret.dart                  # 難読化秘密鍵
      trial_state.dart              # unlock 状態管理
  features/
    second_stage/
      presentation/
        ss_session_screen.dart      # SS問題・解答画面
    trial/
      presentation/
        unlock_screen.dart          # コード入力画面
        locked_teaser.dart          # 未アンロック時のUI部品
    videos/
      presentation/
        video_list_screen.dart
        video_detail_screen.dart

assets/content/
  second_stage.json                 # SSエントリ本体
  videos.json                       # ビデオメタデータ

tool/
  import_second_stage.py            # SS Excel → JSON
  import_videos.py                  # Video CSV → JSON
  generate_codes.py                 # 体験版コード生成 CLI
```

### 5.3 progress.db マイグレーション

**実物確認**: 現行 `ProgressDb.schemaVersion = 1`。既存3テーブル（`word_progress`, `block_state`, `stage_progress`）は **全て `stage` TextColumn を保持済み**。Second Stage 導入では **既存テーブルへの構造変更は不要**、`stage = 'second'` の値を追加するのみ。

Phase 2 で新規に発生する DB 変更は **体験版のアンロック状態を保持する `app_state` テーブル1つのみ**。

```dart
// schemaVersion 1 → 2
class AppState extends Table {
  @override
  String get tableName => 'app_state';
  IntColumn get id => integer().withDefault(const Constant(1))();  // 単一行、常に id=1
  IntColumn get unlockedAt => integer().nullable()();               // epoch秒、null=未アンロック
  TextColumn get unlockCodeHash => text().nullable()();             // 使用したコードのHMAC値（監査用）
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

// ProgressDb.schemaVersion を 2 に変更、@DriftDatabase(tables: [...既存3, AppState])
@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.createTable(appState);
      await into(appState).insert(AppStateCompanion.insert(id: const Value(1)));
    }
  },
);
```

---

## 6. スプリント計画（8週間）

**前提**: 2026-07-07（月）着手 〜 2026-08-30（日）完成

### Week 1 (2026-07-07〜13): 基盤準備 + 体験版着手
- [ ] Phase 1 の First Stage 精算確認、Phase 2 契約確定
- [ ] `progress.db` v1 → v2 マイグレーション（`app_state` テーブル追加、Phase 1 テスト全通過維持）
- [ ] `kStageSecond` 定数追加、`RangeScreen` の stage 引数対応
- [ ] `start_screen.dart` の Second Stage カード「準備中」ラベル削除、遷移導線実装（データはまだSSデータ無しでもUI遷移だけ通す）
- [ ] 体験版：`UnlockVerifier` 実装 + HMAC 単体テスト
- [ ] 体験版：`generate_codes.py` CLI プロトタイプ
- [ ] 3新規パッケージ（`webview_flutter`, `crypto`, `connectivity_plus`）を `pubspec.yaml` に追加、`flutter pub get`
- （エンジンのジェネリック化は不要と確定 — 既にIDベース、そのまま流用可）

### Week 2 (2026-07-14〜20): 体験版UI + Vimeo基盤
- [ ] 体験版：`unlock_screen.dart` 実装
- [ ] 体験版：`locked_teaser.dart`（グレーアウト部品）
- [ ] 体験版：start_screen / range_screen へのモード反映
- [ ] Vimeo：`videos.json` サンプル作成、`VideoRepository` 実装
- [ ] Vimeo：`video_list_screen.dart` / `video_detail_screen.dart` スケルトン
- [ ] （並行）落合様の Second Stage 追加データ受領・確認

### Week 3 (2026-07-21〜27): Second Stage 実装
- [ ] `import_second_stage.py` 実装、Vol.1〜2 のSS Excelを取り込み
- [ ] `second_stage.json` バンドル、`SecondStageRepository` 実装
- [ ] `ss_session_screen.dart` UI 実装（複数タテ並び）
- [ ] SS 特殊ケース（活・品・意２）の表示ロジック
- [ ] `MantenhoEngine<SecondStageQuestion>` 起動導線

### Week 4 (2026-07-28〜08-03): 統合＆内部テスト
- [ ] SS のE2Eテスト（範囲指定 → 出題 → 解答 → OK/再チェック → 満点法）
- [ ] 体験版のE2Eテスト（未アンロック → コード入力 → 全機能解放）
- [ ] Vimeo のE2Eテスト（一覧 → 詳細 → オフライン時挙動）
- [ ] 全体テスト目標達成（86+15+10=最低101項目、目標120項目）
- [ ] `flutter analyze` エラー・警告ゼロ維持

### Week 5 (2026-08-04〜10): 客户レビュー1回目 + フィードバック対応
- [ ] Alpha APK ビルド、客户送付
- [ ] 客户からのUI・データ修正要求対応
- [ ] Vimeo 用の実データ（客户のVimeoアカウントから）取込み

### Week 6 (2026-08-11〜17): 客户レビュー2回目
- [ ] Beta APK ビルド、客户送付
- [ ] 客户からのUI・データ修正要求対応
- [ ] Second Stage 追加データ（客户が拡充した場合）取込み

### Week 7 (2026-08-18〜24): ポリッシュ＋Store提出準備
- [ ] アプリアイコン最終版反映
- [ ] スプラッシュ画面最終版反映
- [ ] **リリース署名キーストア（keystore）作成 + `key.properties` 設定 + `android/app/build.gradle.kts` の release signing 設定**（現行は debug キーで署名、Play 提出不可）
- [ ] Play Console 用リリース鍵バックアップ（LastPass 等の暗号化保管）
- [ ] Google Play ストア掲載素材（スクリーンショット6枚、説明文、キーワード）作成
- [ ] 内部テスト用配信で客户・関係者に配布

### Week 8 (2026-08-25〜30): 最終確認 + Google Play 提出
- [ ] リリース版APK（およびAAB）ビルド
- [ ] Play Console にアップロード、審査申請
- [ ] リリースノート・プライバシーポリシー最終化
- [ ] 客户への納品完了報告

### 予備期間（2026-09-01〜: 目標リリース以降）
- Google Play の審査結果対応（通常1〜3営業日、時に1週間）
- iOS ビルド着手（Mac調達次第）
- App Store 提出（別途スケジュール調整）

---

## 7. リスクレジスター

| # | リスク | 発生確率 | 影響度 | 対応策 |
|---|---|---|---|---|
| R1 | 落合様のSSデータ提供が7月中旬より遅れる | 中 | 高 | 体験版・Vimeo・UI枠組みを先行実装。SSエンジンとUIはモックデータでテスト完了させておく |
| R2 | Google Play 審査で拒否／指摘 | 中 | 中 | 提出前にコンテンツポリシー・データ安全性ラベル・年齢レーティングを事前確認 |
| R3 | Vimeo プライバシー設定と埋込許可ドメインの制約 | 低 | 中 | 客户との事前確認、テスト動画で埋込挙動検証 |
| R4 | 体験版アンロックコード秘密鍵の漏洩 | 低 | 低 | key_version ローテーション運用で吸収 |
| R5 | webview_flutter の Android 特定バージョン依存問題 | 低 | 中 | 対応 minSdkVersion 事前確認、Android 8以上を要求（現行 minSdkVersion 21 → 26に引上げ検討） |
| R6 | SS 特殊ケース（活・品・意２）の仕様が客户想定と異なる | 中 | 中 | Week 3 でモックUIを客户確認後に本実装 |
| R7 | iOS ビルド環境（Mac）未整備で Store 提出遅延 | 高 | 中 | Phase 2 は Android 先行リリースで確定、iOS は別スケジュール |
| R8 | Phase 1 テストの progress.db マイグレーションで既存テスト破壊 | 低 | 中 | Week 1 でマイグレーション実装後 Phase 1 全61テスト通過確認を必須ゲートに |
| R9 | **リリース署名キーストア未整備 → Google Play 提出時に致命的**（現行 build.gradle.kts は debug キー使用） | **高**（未対応の場合） | **高** | Week 7 でキーストア作成、`key.properties` 追加、release signingConfig 実装、生成鍵を安全にバックアップ |
| R10 | 追加3パッケージ（webview_flutter/crypto/connectivity_plus）と drift/riverpod のバージョン互換性 | 低 | 中 | Week 1 で pub get 実行、`flutter analyze` 通過確認、Phase 1 テスト回帰確認 |

---

## 8. Definition of Done

### 8.1 Second Stage
- [ ] `import_second_stage.py` が客户のExcelを完全にインポートできる
- [ ] `SecondStageRepository` が全エントリを提供、外部キー整合性ゼロ違反
- [ ] ⑤（Stage選択）から SS モードを起動できる
- [ ] SS の範囲指定・出題・解答・OK/再チェック・満点法完了・結果画面が動作する
- [ ] 特殊ケース（活・品・意２）が仕様通り表示される
- [ ] TTS 音声フラグが尊重される
- [ ] SS 用テスト最低 25項目通過
- [ ] `flutter analyze` エラー・警告ゼロ

### 8.2 体験版
- [ ] `generate_codes.py` で 100枚以上のコードを CSV 生成できる
- [ ] 未アンロック時：First Stage の第1〜3ブロックのみアクセス可能、Second Stage/Videoグレーアウト
- [ ] アンロック成功時：全機能が即座に有効化される
- [ ] 有効なコードで検証 → 100% 成功、無効なコードで検証 → 100% 失敗
- [ ] アンロック状態が progress.db に永続化される
- [ ] 体験版用テスト最低 15項目通過

### 8.3 Vimeoビデオ連携
- [ ] `videos.json` で全46ブロックのメタデータを保持
- [ ] 動画一覧画面から各動画詳細画面へ遷移可能
- [ ] Vimeo 埋込動画がWebViewで再生される
- [ ] オフライン時「ネットワークが必要」表示
- [ ] 動画詳細から「このブロックの学習を開始」導線が動作
- [ ] ビデオ用テスト最低 10項目通過

### 8.4 全体
- [ ] リリースAPKビルドがエラーなく完了、130〜150MB 想定範囲
- [ ] **リリース署名キーストア設定完了、release ビルドが本番キーで署名される**
- [ ] Play Console にアップロード、内部テスト経路配信可能
- [ ] 全テスト（Phase 1 + Phase 2）通過、目標 111項目 min / 120項目 stretch（Phase 1: 61 + SS: 25 + Trial: 15 + Video: 10 = 111）
- [ ] `flutter analyze` 全体でエラー・警告ゼロ
- [ ] `progress.db` v1 → v2 マイグレーションが実機で既存学習履歴を保持したまま動作

---

## 9. Phase 2 完了後の残作業（Phase 3候補、別見積）

- [ ] iOS ビルド環境構築（Mac調達 or クラウドMac利用）
- [ ] iOS 版ビルド・App Store 提出
- [ ] Google Play / App Store 継続保守（客户データ更新の随時反映）
- [ ] リリース後の不具合対応（バグ修正保証期間の定義要）
- [ ] （オプション）録音音源方式の TTS 精度改善（Phase 1 の 15+3+1 = 19 単語対象）
- [ ] （オプション）iCloud / Google ドライブ 学習履歴同期
- [ ] （オプション）ダークモード対応

---

## 10. 変更管理

本ドキュメントの版数管理:
- v1.0 (2026-07-06): 初版、AKAME 作成
- v1.0.1 (2026-07-06): 実物コードとの整合性検証を実施。以下を修正:
  - `MantenhoEngine` は既にIDベースのためジェネリック化不要と確定
  - `progress.db` 現行 v1、`stage` 列は既存済み → v1→v2（app_state追加のみ）に縮小
  - Riverpod v2 → v3.3.1（実物確認）
  - `webview_flutter` は pubspec 未追加であることを明記
  - Second Stage カードは start_screen に「準備中」状態で既存 → アクティブ化のみ
  - SS 関係タイプを11種→15種に拡張（複/同音/セ/法/意味(N)/関連語 を追加）
  - リリース署名キーストア未整備を R9 として追加、Week 7 の必須タスクに
- v1.1: 客户からのSS特殊ケース仕様確定後
- v2.0: Week 4 中間レビュー後の全体見直し

**客户確認要事項**（本計画確定前に決着必須）:
1. 体験版でアクセス可能なコンテンツ範囲（当計画では「第1〜3ブロックのみ」を仮置き）
2. アンロックコードの期限有無（当計画では「期限なし」を仮置き）
3. Vimeoの動画とブロックの1対1対応関係（1動画=1ブロック想定）
4. Second Stage 出題画面のタテ並び順序（見出し語id昇順で仮置き）
5. SS 見出し語にエントリがない場合の扱い（当計画では出題除外を仮置き）

---
