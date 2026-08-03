# 快単アプリ Phase 2 実装計画 v1.1

**対象範囲**: Second Stage / 体験版 / Vimeoビデオ連携 ＋ 医系単語ブロック（第47ブロック相当）
**期間目安**: 2026-07-07 〜 2026-08-30（約8週間、うちPhase 1 追加改修に4週間を要し、Phase 2 実装は2026-08-04〜開始予定）
**リリース目標**: 2026年9月 高校生2学期開始
**作成日**: 2026-07-06（v1.0）／ 2026-07-06（v1.0.1）／ **2026-08-03（v1.1 — 客户データ全受領後の全面更新）**
**作成者**: AKAME

---

## 0. エグゼクティブサマリー

Phase 2 は Phase 1 で完成した「快単」の基盤の上に、3つの契約 Deliverable ＋ 1つの追加スコープ（客户 2026-07-13 依頼）を追加する。

| # | Deliverable | 契約金額 | 客户データ受領状況 |
|---|---|---|---|
| 1 | Second Stage（派生語・類義語・活用ドリル、全46ブロック） | ¥250,000 | ✅ **受領済み 2026-07-27**（V1: 945 entries / V2: 1,028 entries、合計1,973 entries） |
| 2 | 体験版（アンロックコード方式） | ¥100,000 | 客户データ不要 |
| 3 | Vimeoビデオ連携 | ¥50,000 | ✅ **受領済み 2026-07-13**（46 URLs、ブロック1〜46分） |
| +追加 | 医系単語ブロック（第47ブロック相当、First Stage形式） | 追加見積対象外／今契約枠内 | ✅ **受領済み 2026-08-02**（Excel 66語＋画像66枚＋例文66件） |
| **計** | | **¥400,000 (税抜)** | 客户データ全受領完了 |

**現在の状況**（2026-08-03時点）:
- Phase 1 の追加改修（docx訂正・音声ファイル差し替え・意味表示ルール変更・POS修正等）を通じて完成状態を維持し、2026-07-27 に First Stage 最終版APKを納品
- Phase 2 の**全客户データが揃った**ため、実装を本格着手可能な状態
- 体験版・Vimeo連携は当初計画どおり客户データ待ちなしで先行可能な部分もあるが、Phase 1 改修を優先していたため、実装は 2026-08-04 〜 開始する見込み

**Phase 1 資産の再利用**: `MantenhoEngine`（満点法状態機械）、`ProgressDb`（drift/SQLite）、`SessionScreen` の UI パーツ、拡張済み `TtsService`（recorded-audio 優先再生付き）はすべて Phase 2 でも共有利用する。ゼロからの再設計は行わない。

---

## 1. 前提と制約

### 1.1 継承する Phase 1 制約（実物確認済み、2026-08-03時点）
- Flutter 3.44 / Dart SDK ^3.12.0（`pubspec.yaml` env sdk 確認）
- **Riverpod v3.3.1**（`flutter_riverpod: ^3.3.1`、v2ではない — 契約書上はv2表記だが実装はv3）
- drift 2.33.0 + SQLite（content.db 読取専用 + progress.db 書込可能の2DB分離）
- go_router 17.2.3 ナビゲーション（`main.dart` は `MaterialApp.router` + `routerProvider`）
- flutter_tts 4.2.5
- **audioplayers 6.1.0**（v1.1 追記：Phase 1 の後期に追加。録音音源優先再生を実現）
- **完全オフライン / on-device / 通信なし / テレメトリなし**
- 現行 `applicationId = "jp.or.kai.kaitan"`（Android/iOS共通で流用予定）
- Phase 1 現状：全2,201語 + 2,201画像(WebP) + 43音声ファイル + 61テスト通過 + APK 136 MB

### 1.2 Phase 2 で新規追加する外部依存（現行 pubspec 未追加）
- `webview_flutter` ^4.x（Vimeo埋込用。**現行 pubspec には未追加、新規追加が必要**）
- `crypto` ^3.x（体験版コード検証、HMAC-SHA256。**新規追加**）
- `connectivity_plus` ^6.x（Vimeoオフライン判定、**新規追加**）
- 上記3つ以外は追加しない方針。依存を最小限に抑える。
- （`audioplayers` は Phase 1 で既に追加済み — Phase 2 では追加不要）

### 1.3 データソース（v1.1 実データ受領反映）
- **Second Stage 全46ブロック**：
  - `Appli開発［foxgold共有］/アプリ基本データ Second Stage V1.xlsx`（快単vol.1範囲、ブロック1-23、945エントリ、2026-07-27受領）
  - `Appli開発［foxgold共有］/アプリ基本データ Second Stage V2.xlsx`（快単vol.2範囲、ブロック24-46、1,028エントリ、2026-07-27受領）
  - 合計 1,973 エントリ、1,311 の見出し語に紐付き（見出し語 全2,201語のうち約60% にSSデータあり）
  - 残り約890語の見出し語には SS エントリなし（客户仕様「1ブロック48語のうちSSに出したいのは色付き行のみ」に準拠）
- **医系単語ブロック**（第47ブロック相当、追加スコープ）:
  - `Appli開発［foxgold共有］/アプリ基本データSecond Stage医系66.xlsx`（66語、2026-07-27 受領、例文2026-08-02 追加完了）
  - `Appli開発［foxgold共有］/医系単語2202-2267Second Stage画像/`（66 PNG @ 720×480）
  - 内容形式は First Stage と同じ（見出し語 + 品詞 + 意味 + 覚え方 + 例文）
- **体験版**: アンロックコードは AKAME 側のオフラインCLIツールで発行（客户データ不要）
- **Vimeo**: 46 URLs受領（2026-07-13）
  - フォーマット: `https://vimeo.com/{ID}/{hash}?fl=tl&fe=ec`（Vimeo unlisted-share 形式）
  - 埋込用 URL への変換: `https://player.vimeo.com/video/{ID}?h={hash}` （ingest 時に変換）
  - ブロック1-46 に対応、**医系単語ブロック（47）用の動画はなし**

### 1.4 プラットフォーム制約
- 初期リリースは Android のみ（iOS はビルド環境未整備、Phase 2 終了後）
- WebView は Vimeo 埋込プレイヤー経由（動画ダウンロード・オフライン再生は非対応）
- iOS 対応時は ATS（App Transport Security）設定で vimeo.com を許可する

---

## 2. Deliverable 1 — Second Stage（¥250,000）

### 2.1 客户のSSデータ仕様（v1.1 全データ受領後の実測）

**受領元**: `アプリ基本データ Second Stage V1.xlsx`（vol.1範囲）＋ `アプリ基本データ Second Stage V2.xlsx`（vol.2範囲）

**確定した実データ統計**（2026-07-27 受領・全数検証済み）:
- 合計 SS エントリ数: **1,973件**（V1: 945件、V2: 1,028件）
- 全46ブロック（1〜23 vol.1、24〜46 vol.2）にわたって収録、欠番なし
- 見出し語紐付き数: **1,311語**（Phase 1 の 2,201語のうち約60%）
- **890語の見出し語には SS エントリなし**（客户仕様に準拠、SS 対象外）
- 1ブロックあたりのエントリ数: min 26 / median 41〜46 / max 60
- 外部キー整合性: **0 orphan word_ids**、**0 重複 (word_id, relation, answer) 三つ組**、**0 malformed rows**

**基本構造**: Phase 1 の2,201語（見出し語）1つに対して、**0..N 個の Second Stage エントリ**を紐付ける。エントリはすべて「見出し語との関係」を持つ。客户記述：「この数はブロックごとに変わる」。

**⚠️ v1.1 重要な発見: 関係タイプは列挙型では扱えない**

パイロット3ブロック段階では15種程度に収まると想定していたが、実データを受領後の実測では、`問題` 列に **数百通りの free-form ラベル** が使用されていた。基本コード15種の周辺に、以下のような詳細指示形式が多数存在:

- `意 racism`（この単語の意味を問う）
- `セ 彼に留学するように勧める`（このセットフレーズを答えさせる、日本語プロンプト付き）
- `意３（名２，他１）`（意味を3つ、うち名詞義2つ・他動詞義1つ）
- `dig の活用と意味`（特定語の活用形+意味）
- `類義語とその名詞と動詞`（複合関係）
- `法 without と instead of の違い`（比較指示）
- `意 fertilizer`（関連語の意味）
- 他 数百通り

**設計上の含意**:
1. `SecondStageRelation` 列挙型設計を **廃止**、`relation` 列は **String型で自由文字列として保持**
2. 基本コード（`類/反/名/形/副/動/熟/活/品/法/複/同音/セ/前/意`）のみ「基本カテゴリ」として認識、UIでアイコン等の視覚要素に反映
3. 詳細指示（`意 racism`, `セ ...`, `意３（名２，他１）` 等）はそのまま解答画面のプロンプト文字列として表示

**関係タイプの分類（v1.1 実データ確定）**:

| 基本カテゴリ | 出現数（V1+V2 合計） |
|---|---|
| `名`（名詞派生・関連） | 約471件 |
| `形`（形容詞派生・関連） | 約195件 |
| `活`（動詞活用） | 約58件 |
| `他`（他動詞派生・意味） | 約58件 |
| `類`（類義語） | 約42件 |
| `反`（反意語） | 約61件 |
| `法`（語法） | 約62件 |
| `品`（品詞判別） | 約32件 |
| `熟`（熟語） | 約23件 |
| `意２/意３/意４…`（意味N個） | 約80件（意味数付きバリエーション含む） |
| `セ …`（セットフレーズ、日本語ヒント付き） | 約250件 |
| `複`（複数形） | 約15件 |
| `同音`（同音異義語） | 約10件 |
| `副` / `動` | 約12件 |
| その他 free-form（`意 word`, `類義語とその名詞と動詞` 等） | 約605件 |
| **合計** | **約1,973件** |

**注意事項**:
- `問題` 列の値は自由文字列のため、機械的な enum 変換は不可能
- 一部の値には日本語プロンプト（`セ 彼に留学するように勧める`）や単語別指示（`意 racism`）を含み、そのまま解答画面プロンプトとして表示すればよい
- 「意味の (2)」と「品詞 (2)」は混同注意（前者は Phase 2 の SS 出題種別、後者は Phase 1 words.json の meaning_mode=either_ok マーカー）

**旧v1.0.1の列挙表（参考のため保持）**:

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

**Dart 側モデル (`lib/data/second_stage.dart`) — v1.1 更新版**:

自由文字列を許容する設計に変更。基本カテゴリはヘルパー関数で判定する。

```dart
/// 基本15カテゴリ。UI 側でアイコンや色分けに使う（限定的）。
/// relation 文字列がこれらのプレフィックスで始まる場合に該当カテゴリと判定。
class SsRelationCategory {
  static const synonym = '類';
  static const antonym = '反';
  static const preposition = '前';
  static const idiom = '熟';
  static const conjugation = '活';
  static const posMarker = '品';
  static const usage = '法';
  static const plural = '複';
  static const homophone = '同音';
  static const setPhrase = 'セ';
  static const meaning = '意';
  static const nounForm = '名';
  static const adjForm = '形';
  static const advForm = '副';
  static const verbForm = '動';

  static const all = [
    synonym, antonym, preposition, idiom, conjugation, posMarker,
    usage, plural, homophone, setPhrase, meaning,
    nounForm, adjForm, advForm, verbForm,
  ];

  /// relation 文字列の先頭コード（例: `意 racism` → `意`）を返す。
  /// マッチしなければ null（表示は生の relation 文字列をそのまま使う）。
  static String? categoryOf(String relation) {
    final trimmed = relation.trim();
    for (final code in all) {
      if (trimmed == code || trimmed.startsWith('$code ') || trimmed.startsWith('$code　')) {
        return code;
      }
      // 意２ / 意３ / 名２ / 形２ 等の数字付き変異形にも対応
      if (RegExp(r'^' + code + r'\d+$').hasMatch(trimmed) ||
          RegExp(r'^' + code + r'（').hasMatch(trimmed)) {
        return code;
      }
    }
    return null;
  }
}

class SecondStageEntry {
  final int id;
  final int wordId;         // Phase 1 word.id への外部キー
  final int vol;
  final int block;
  final String relation;    // 生の文字列（例: `類`, `意 racism`, `セ 彼に留学するように勧める`, `意３（名２，他１）`）
  final String answer;      // 解答（英単語、句、活用形、または品詞マーカー文字列）
  final String? answerMeaning; // 解答の日本語訳（あれば）
  final bool ttsEnabled;
  final String? notes;

  /// UI 側で「基本カテゴリ」を必要とする場合の便利ゲッター。
  String? get category => SsRelationCategory.categoryOf(relation);
}

class SecondStageRepository {
  int get count;
  List<int> allBlocks();
  List<SecondStageEntry> byBlock(int block);
  List<SecondStageEntry> byWordId(int wordId);
  bool hasEntriesForBlock(int block);
  bool hasEntriesForWord(int wordId);
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

### 2.7 発音（TTS）取り扱い（v1.1 更新）

Phase 1 後期（2026-07-22）に `TtsService` が録音音源優先再生に拡張されている。Second Stage でもこれをそのまま利用:

- 見出し語（`diversity` 等）の発音: Phase 1 の `TtsService.speak(text, wordId: word.id)` を使用。43件の録音音源が優先再生され、無ければカタカナヒント（13件）、無ければ TTS 標準発音にフォールバック
- SS の解答語（`variety`, `diverse` 等）の発音: SS エントリの `tts_enabled` フラグを尊重（False の場合はスピーカーボタン非表示）。SS 解答用の録音音源は現状なし → 全て TTS 標準発音（客户からご要望あれば録音音源追加も可能）
- `TtsService.speak()` の現行シグネチャ: `speak(String text, {String? pronunciationHint, int? wordId})`。SS の解答再生には `wordId` を渡さず（wordIdは見出し語IDに紐付き、SS 解答語には紐付かないため）、`text` のみで呼び出す

### 2.8 Excel インポーターの拡張（v1.1 実データ対応）

`tool/import_excel.py` の兄弟スクリプトとして `tool/import_second_stage.py` を新規作成。

**入力ファイル**（実データ確定）:
- `Appli開発［foxgold共有］/アプリ基本データ Second Stage V1.xlsx`（sheet `快単vol.1`、945エントリ）
- `Appli開発［foxgold共有］/アプリ基本データ Second Stage V2.xlsx`（sheet `1101-1214`、1,028エントリ）

**責務**:
1. 上記2ファイルを両方読み取り、統合
2. 各行を SecondStageEntry に変換（B列の見出し語番号を親キーとして紐付け。ブロック番号は列Aから継承、`current_block` を行間で保持）
3. 見出し語情報は 列C(英単語)/D(品詞)/E(意味) — Phase 1 words.json 側と重複確認用（不一致 → warning）
4. **関係タイプは `relation` として生の文字列で保持**（enum 変換しない）
5. `answer` (列G)、`answer_meaning` (列H)、`tts_enabled` (列I: True/False) を保持
6. 空白セル・改行等の正規化（全角スペース除去、trim、末尾空白除去）
7. `assets/content/second_stage.json` を出力（1〜1,973 の連番 `id` を付与）
8. 統計サマリを stdout に出力（by_block, by_category, orphan word_id 検出、malformed 検出）

**バリデーション**（Phase 1 と同水準）:
- `word_id` が Phase 1 words.json に存在しない → error（実データでは 0件を確認済み）
- 空欄の `answer` かつ `relation` も空 → skip
- `tts_enabled` の正規化: `True`/`TRUE`/` FALSE ` 等の混在パターンに対応

**バリデーション実測結果**（2026-08-03 事前パス済み）:
- Orphan word_ids: 0
- Malformed rows: 0
- Duplicates: 0

### 2.9-A 医系単語ブロック（第47ブロック相当、追加スコープ）

**v1.1 新規追加**（2026-07-13 客户依頼、2026-07-27 データ受領、2026-08-02 例文完了）:

客户依頼: "Second Stage では快単vol.3に掲載している医系単語 №2202〜2267 の66語で1つのブロックを作ってください。**内容は First Stage と同じです**。"

**入力ファイル**:
- Excel: `アプリ基本データSecond Stage医系66.xlsx`（sheet `医系単語66`、66語 = 66行）
- 画像: `医系単語2202-2267Second Stage画像/*.png`（66枚、720×480 PNG、命名 `{id}{word}.png`）

**内容形式**: **First Stage と同じ 9-column schema**（B / 見出し№ / 英単語 / 品詞 / 意味 / 覚え方 / 覚え方の具体的方法 / 例文 / 日本語訳）— Second Stage の relational-drill 形式ではない。

**設計判断**:
- 医系ブロックは Second Stage 画面から起動されるが、内容は First Stage 形式のため、**Phase 1 の `words.json` 側に第47ブロック・vol=3 として追加**する
- Second Stage screen のブロック選択画面で「第47ブロック 医系単語」を選択すると、内部的には First Stage のフラッシュカードフロー（⑥ 問題 → ⑦ 解答 → OK/再チェック → 満点法）を起動
- Second Stage の relational-drill 用 `second_stage.json` には第47ブロック分のエントリは含まれない

**画像処理**（v1.1 追加設計）:
- 現行 `tool/import_images.py` は Phase 1 の JPEG 800×560 を想定。医系画像は 720×480 PNG
- インポーター拡張: 720×480 PNG も受入可（Pillow で開いてWebP変換、アスペクト比を保持したままリサイズ）
- 出力ファイル名: `assets/images/2202.webp` 〜 `2267.webp`（Phase 1 と同じ命名規則で連番拡張）
- 出力サイズ: 720×480 を保持（アプリの UI slot 800×560 内で余白を持たせて表示）

**words.json への統合**:
```python
# tool/import_excel.py 拡張版:
# vol=1 → 1..1100
# vol=2 → 1101..2201
# vol=3 → 2202..2267 (医系ブロック、block=47)
```
- 全ブロック数: 46 → **47**
- 全単語数: 2,201 → **2,267**
- meaning_mode: 医系66語はすべて `single` 想定（現時点で複数意味形式は含まれていないと確認済み）

**Second Stage ⑤(Stage選択) → ⑤' 範囲指定** への影響:
- Second Stage 範囲指定画面は 46 ブロック + 医系1ブロック = **47ブロックの格子**を表示
- 第47ブロックは「医系」ラベル付き、他46ブロックとは視覚的に区別（別色/別セクション）
- 学習フロー起動時、第47ブロック選択時は First Stage 形式のフラッシュカードフローに分岐

### 2.9-B Second Stage のテスト戦略

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

### 4.1 データモデル（v1.1 実URL受領後の確定）

**方針**: `assets/content/videos.json` として独立バンドル。ブロック1〜46 に1:1 対応（客户2026-07-13 提供）。

**受領URLフォーマット**（客户提供の実物）:
```
https://vimeo.com/1210995261/2e413b4072?fl=tl&fe=ec
                 ^^^^^^^^^^  ^^^^^^^^^^ ^^^^^^^^^^^^^
                 vimeo_id    hash       tracking (無視)
```

**埋込用への変換**（ingest 時に自動変換）:
```
https://player.vimeo.com/video/1210995261?h=2e413b4072
```

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
      "title": "第1ブロック 解説",
      "vimeo_id": "1210995261",
      "vimeo_hash": "2e413b4072",
      "duration_sec": 360,
      "thumbnail_local": null
    }
    // ...46件
  ]
}
```

- `vimeo_id`: Vimeo の動画ID（客户からのURL の1つ目のパスセグメント）
- `vimeo_hash`: unlisted-share hash（URL の2つ目のパスセグメント。私設リンク経由の埋込に必須）
- `duration_sec`: 客户提示「1動画≒6分」→ 360秒を仮値、実測値取得は Vimeo API不使用のため手動 or 概算
- `thumbnail_local`: 現状 null。将来サムネイル画像を客户から受領した場合に対応
- **医系ブロック（47）用の動画URLは未受領**。videos.json entries には含めず、UI 側で47ブロック目には動画リンクを表示しない

**Vimeo URL 46本の受領内訳**（2026-07-13 客户メールより）:
- 1-10, 11-20, 21-23, 24-30, 31-40, 41-46 の6グループに分けて記載（合計46本）

**プライバシー設定**: 客户URL の `/{id}/{hash}` 形式は Vimeo の unlisted-share 設定であり、hash なしではアクセス不可。埋込用 URL に hash を含めれば動作する。**Vimeo 側の追加設定（embed domain allowlist）は不要**（現状の設定で埋込動作を確認済み仮定）。

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

### 5.1 変更を要する既存ファイル（v1.1 Phase 1 進化後の実物確認）

| ファイル | 変更内容 | 影響度 |
|---|---|---|
| `lib/features/session/domain/engine.dart` | **変更不要**（IDベースのまま） | ゼロ |
| `lib/features/start/start_screen.dart` | 既存 Second Stage「準備中」カードを アクティブ化、Video リンク追加 | 小 |
| `lib/features/range_select/range_screen.dart` | `stage` 引数追加、進捗DBアクセスを引数stage経由に。47ブロック格子対応（第47は医系ラベル） | 中 |
| `lib/features/session/presentation/session_screen.dart` | stage 判定で SS/FS レンダラを切替。医系ブロック（vol=3）は FS レンダラを流用 | 中 |
| `lib/features/session/presentation/session_controller.dart` | `ssRepoProvider` 追加、stage 判定。既存の `audioManifestProvider` 経由の TtsService 初期化はそのまま流用 | 中 |
| `lib/data/progress/progress_db.dart` | `app_state` テーブル追加のみ (v1 → v2 マイグレーション) | 小 |
| `lib/data/progress/progress_repository.dart` | `kStageSecond` 定数追加、app_state 用リポジトリメソッド追加 | 小 |
| `lib/core/providers.dart` | SS Repository, Video Repository, Unlock Verifier の Provider 追加、`/videos` `/unlock` ルート追加 | 小 |
| `lib/data/tts_service.dart` | **変更不要**（Phase 1 で `wordId` 対応済み、SS 解答再生には `wordId` を渡さないだけ） | ゼロ |
| `tool/import_excel.py` | vol=3（医系ブロック）対応 — 66語追加、block=47、720×480 PNG 画像対応 | 中 |
| `tool/import_images.py` | 720×480 PNG 入力対応（現状は 800×560 JPEG 想定）、アスペクト比保持リサイズ | 中 |

### 5.2 追加する新規ファイル（v1.1 更新版）

```
lib/
  data/
    second_stage.dart               # SecondStageEntry, SecondStageRepository
    video.dart                      # VideoEntry, VideoRepository
    trial/
      unlock_verifier.dart          # HMAC検証
      _secret.dart                  # 難読化秘密鍵（.gitignore済み前提で管理）
      trial_state.dart              # unlock 状態管理
  features/
    second_stage/
      presentation/
        ss_session_screen.dart      # SS問題・解答画面（relation-drill形式、複数タテ並び）
    trial/
      presentation/
        unlock_screen.dart          # コード入力画面
        locked_teaser.dart          # 未アンロック時のUI部品
    videos/
      presentation/
        video_list_screen.dart
        video_detail_screen.dart

assets/content/
  second_stage.json                 # 1,973 SS エントリ本体（v1.1 実データ確定）
  videos.json                       # 46 ビデオメタデータ（v1.1 実URL確定）

tool/
  import_second_stage.py            # SS Excel V1+V2 → JSON
  import_videos.py                  # Vimeo URL リスト → JSON（unlisted-share URL 分解）
  generate_codes.py                 # 体験版コード生成 CLI
```

**Phase 1 で既に追加され、Phase 2 でも利用される既存資産**（参考）:
```
lib/
  data/
    tts_service.dart                # 録音音源優先再生対応済み（Phase 1、2026-07-22）
  core/
    providers.dart                  # audioManifestProvider あり（Phase 1）

assets/
  audio/*.{mp3,wav,mp4}             # 43 音声ファイル + manifest.json（Phase 1）
  content/words.json                # 2,201語（Phase 1） → 2,267語（Phase 2 医系追加後）
  images/*.webp                     # 2,201 illustrations（Phase 1） → 2,267（Phase 2）

tool/
  import_audio.py                   # 音声インポートCLI（Phase 1）
  apply_mnemonic_overrides.py       # docx→太字範囲上書き（Phase 1）
  apply_word_overrides.py           # docx→POS等上書き（Phase 1）
  pronunciation_overrides.json      # 発音ヒント override（Phase 1、現在13件）
  mnemonic_overrides.json           # 太字範囲 override（Phase 1、現在5件）
  word_overrides.json               # POS 等 override（Phase 1、現在1件）
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

## 6. スプリント計画（v1.1 実際の進捗を反映）

**⚠️ 大きなズレ**: v1.0.1 では 2026-07-07 〜 2026-08-30 の8週間で Phase 2 全体を完成させる想定だったが、実際は Phase 1 の追加改修（客户の docx 訂正、音声ファイル差し替え、意味表示ルール変更、POS 修正等）に4週間を要し、Phase 2 の実装は **2026-08-04 開始** となる。残り約4週間で Phase 2 全 Deliverable を仕上げる圧縮スケジュールに再構成。

### Week 1〜4 (2026-07-07〜08-03): **Phase 1 追加改修に費消** ✅ 完了
実施内容:
- [x] Phase 1 の First Stage 精算確認、Phase 2 契約確定 → 精算は「明日までに手続き」と 2026-07-27 に受領
- [x] Second Stage V1/V2 データ受領 (2026-07-27)、医系ブロックデータ受領 (2026-07-27、例文 2026-08-02)
- [x] Vimeo URLs 46本 受領 (2026-07-13)
- [x] Phase 1 での追加改修:
  - 意味表示の全体ルール変更（両方大 + 「、」区切り、「ひとつめOK」ラベル削除）
  - docx 記載15項目の実装バグ修正（太字範囲、品詞表記、括弧内小さく等）
  - 4画像差し替え（758/858/911/1179）
  - 音声ファイル導入（43件 mp3/wav/mp4）と `TtsService` の録音優先再生化
  - Excel→words.json → mnemonic overrides → word overrides のパイプライン整備
  - `audioplayers` パッケージ追加、`audioManifestProvider` 追加
- [x] Second Stage・Trial・Vimeo の **実装コード側は未着手**

### Week 5 (2026-08-04〜10): Phase 2 実装スタート ← **今週から**
- [ ] 3新規パッケージ（`webview_flutter`, `crypto`, `connectivity_plus`）を `pubspec.yaml` に追加、`flutter pub get`
- [ ] `progress.db` v1 → v2 マイグレーション（`app_state` テーブル追加、Phase 1 全61テスト通過維持）
- [ ] `kStageSecond` 定数追加、`RangeScreen` の stage 引数対応
- [ ] `import_second_stage.py` 実装、V1+V2 のSS Excelを取り込み → `second_stage.json` 生成
- [ ] `import_videos.py` 実装、46 Vimeo URL → `videos.json` 生成
- [ ] `import_excel.py` に vol=3 医系ブロック対応追加（66語 + 720×480 PNG→WebP）

### Week 6 (2026-08-11〜17): SS 出題フロー + 体験版 + Vimeo UI
- [ ] `SecondStageRepository` 実装 + テスト
- [ ] `ss_session_screen.dart` UI 実装（複数タテ並び、自由文字列 relation 表示）
- [ ] SS 特殊ケース（活・品・意 N・セ 日本語プロンプト・自由文字列）の表示ロジック
- [ ] Second Stage 起動導線（start_screen「準備中」外し + `RangeScreen(stage: kStageSecond)`）
- [ ] 医系ブロック（vol=3, block=47）は Second Stage 範囲指定画面から First Stage フラッシュカードフローで起動
- [ ] 体験版：`UnlockVerifier` 実装 + HMAC 単体テスト + `generate_codes.py` CLI
- [ ] 体験版：`unlock_screen.dart` + `locked_teaser.dart`
- [ ] Vimeo：`VideoRepository` + `video_list_screen.dart` + `video_detail_screen.dart` + WebView埋込
- [ ] Vimeo：オフライン時のグレースフル表示（`connectivity_plus`）

### Week 7 (2026-08-18〜24): 統合＆内部テスト + Alpha APK
- [ ] SS のE2Eテスト（範囲指定 → 出題 → 解答 → OK/再チェック → 満点法 → 結果）
- [ ] 体験版のE2Eテスト（未アンロック → コード入力 → 全機能解放）
- [ ] Vimeo のE2Eテスト（一覧 → 詳細 → 埋込再生 → オフライン時）
- [ ] 全体テスト目標: Phase 1 の 61 + SS 25 + Trial 15 + Video 10 = **111項目 最低ライン、120目標**
- [ ] `flutter analyze` エラー・警告ゼロ維持
- [ ] Alpha APK ビルド、客户送付
- [ ] **リリース署名キーストア（keystore）作成 + `key.properties` 設定 + `android/app/build.gradle.kts` の release signing 設定**（現行は debug キーで署名、Play 提出不可）

### Week 8 (2026-08-25〜30): 客户レビュー対応 + Store提出準備 + 最終ビルド
- [ ] 客户からの UI・データ修正要求対応（緊急のみ、大きな仕様変更は Phase 3 に持ち越し）
- [ ] アプリアイコン最終版反映（客户提供 or デフォルト維持を客户確認）
- [ ] スプラッシュ画面最終版反映
- [ ] Google Play ストア掲載素材（スクリーンショット6枚、説明文、キーワード）作成
- [ ] リリース版APK/AABビルド、Play Console にアップロード、内部テスト経路配信
- [ ] リリースノート・プライバシーポリシー最終化
- [ ] 客户への Phase 2 納品完了報告

### 予備期間（2026-09-01〜: 目標リリース以降）
- Google Play の審査結果対応（通常1〜3営業日、時に1週間）
- iOS ビルド着手（Mac調達次第）
- App Store 提出（別途スケジュール調整）

**圧縮スケジュールにおけるスコープ調整方針**:
- Phase 2 の3 Deliverable（SS / 体験版 / Vimeo）と医系ブロックは9月2学期開始に間に合わせる
- ストア掲載素材の完成度（スクリーンショット枚数、翻訳、キーワード最適化）は最低限で提出、リリース後に追加改善
- iOS 対応は Phase 2 の期間内には含めない（Phase 3 別見積扱い、当初計画から不変）

---

## 7. リスクレジスター（v1.1 更新）

| # | リスク | 発生確率 | 影響度 | 対応策・現況 |
|---|---|---|---|---|
| R1 | 落合様のSSデータ提供が7月中旬より遅れる | ~~中~~ | ~~高~~ | ✅ **CLOSED**: 2026-07-27 に V1+V2 受領、2026-08-02 に医系例文完了 |
| R2 | Google Play 審査で拒否／指摘 | 中 | 中 | 提出前にコンテンツポリシー・データ安全性ラベル・年齢レーティングを事前確認 |
| R3 | Vimeo プライバシー設定と埋込許可ドメインの制約 | 低 | 中 | ✅ **概ね解決**: 客户提供 URL は unlisted-share 形式 `/{id}/{hash}` で埋込動作予定。Alpha APK で実機確認予定 |
| R4 | 体験版アンロックコード秘密鍵の漏洩 | 低 | 低 | key_version ローテーション運用で吸収 |
| R5 | webview_flutter の Android 特定バージョン依存問題 | 低 | 中 | 対応 minSdkVersion 事前確認、Android 8以上を要求（現行 minSdkVersion 21 → 26に引上げ検討） |
| R6 | SS 特殊ケース（活・品・意２）の仕様が客户想定と異なる | ~~中~~ 低 | 中 | ✅ **半解決**: 実データが受領されたことで基本カテゴリ（活・品・意N）の解釈は確定。ただし **R11 参照**: 実データには数百通りの自由文字列 relation が含まれるという新たな課題が浮上 |
| R7 | iOS ビルド環境（Mac）未整備で Store 提出遅延 | 高 | 中 | Phase 2 は Android 先行リリースで確定、iOS は別スケジュール |
| R8 | Phase 1 テストの progress.db マイグレーションで既存テスト破壊 | 低 | 中 | Week 5 でマイグレーション実装後 Phase 1 全61テスト通過確認を必須ゲートに |
| R9 | **リリース署名キーストア未整備 → Google Play 提出時に致命的**（現行 build.gradle.kts は debug キー使用） | **高**（未対応の場合） | **高** | Week 7 でキーストア作成、`key.properties` 追加、release signingConfig 実装、生成鍵を安全にバックアップ |
| R10 | 追加3パッケージ（webview_flutter/crypto/connectivity_plus）と drift/riverpod のバージョン互換性 | 低 | 中 | Week 5 で pub get 実行、`flutter analyze` 通過確認、Phase 1 テスト回帰確認 |
| **R11** | **SS 関係タイプに数百通りの自由文字列が含まれる（v1.1 新規発見）** | **確定** | 中 | 列挙型設計を撤回し、String 型で保持 + 基本カテゴリ判定ヘルパーで対応。UI は生の relation 文字列をそのまま解答画面に表示。実装工数は増加せず（enum 変換ロジック不要のため） |
| **R12** | **Phase 2 実装期間が当初計画から4週間圧縮**（Phase 1 追加改修に4週間費消） | 高 | 中 | Deliverable スコープは維持、ストア掲載素材の完成度を最低限まで削減。iOS はPhase 3 に持ち越し（当初計画から不変） |
| **R13** | **医系ブロック（第47）用の Vimeo 動画URL 未提供** | 中 | 低 | 46ブロック分のみ動画表示、第47ブロックには動画リンクなしで動作させる（客户要望なしの前提）。将来客户が動画追加すれば `videos.json` に追記で対応 |
| **R14** | 医系ブロック画像 720×480 の色域・アスペクト比が Phase 1 800×560 と異なる | 低 | 低 | インポーター側でアスペクト保持リサイズ、UI slot 内で余白表示。視覚的な違和感は最小限 |

---

## 8. Definition of Done

### 8.1 Second Stage
- [ ] `import_second_stage.py` が V1+V2 の1,973エントリを完全にインポートできる
- [ ] `SecondStageRepository` が全エントリを提供、外部キー整合性ゼロ違反（実データで既に検証済み）
- [ ] ⑤（Stage選択）から SS モードを起動できる
- [ ] SS の範囲指定（46ブロック + 医系1ブロック = 47ブロック格子）・出題・解答・OK/再チェック・満点法完了・結果画面が動作する
- [ ] 自由文字列 relation（`意 racism`、`セ 彼に...`、`意３（名２，他１）` 等）が解答画面プロンプトとしてそのまま表示される
- [ ] 基本カテゴリ（活・品・意N・セ 等）ヘルパー判定が動作
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
- [ ] `videos.json` で全46ブロックのメタデータを保持（vimeo_id/hash 正確に抽出）
- [ ] 動画一覧画面から各動画詳細画面へ遷移可能
- [ ] Vimeo 埋込動画がWebViewで再生される（`player.vimeo.com/video/{ID}?h={hash}` 形式）
- [ ] オフライン時「ネットワークが必要」表示
- [ ] 動画詳細から「このブロックの学習を開始」導線が動作
- [ ] 医系ブロック（第47）は動画リンクなし
- [ ] ビデオ用テスト最低 10項目通過

### 8.4 医系単語ブロック（第47）
- [ ] `import_excel.py` が vol=3 医系66語を取り込み、`words.json` の全単語数が 2,201 → 2,267 になる
- [ ] `import_images.py` が 720×480 PNG を WebP に変換し、`assets/images/2202.webp` 〜 `2267.webp` を生成
- [ ] `manifest.json` の image count が 2,201 → 2,267
- [ ] 全46ブロック → **47ブロック**の格子が Second Stage 範囲指定画面で表示される
- [ ] 第47ブロック選択時、First Stage フラッシュカードフロー（⑥⑦）で学習開始できる
- [ ] 66語すべての例文・日本語訳が表示される

### 8.5 全体
- [ ] リリースAPKビルドがエラーなく完了、140〜160MB 想定範囲（医系画像・SS データ追加で若干増）
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
- **v1.1 (2026-08-03): Phase 2 全客户データ受領後の全面再検証**。主要な変更:
  - **Deliverable 追加**: 医系単語ブロック（第47ブロック相当、66語）を追加スコープとして正式記載（客户 2026-07-13 依頼）
  - **SS 実データ確定**: パイロット3ブロックの想定 → 実データ 1,973 エントリ・46ブロック・見出し語1,311語（Phase 1 の60%）
  - **SS 関係タイプ設計を根本的に見直し**: 列挙型（15種）→ 自由文字列 String 型 + 基本カテゴリ判定ヘルパー。実データに数百通りの free-form label が含まれるため（`意 racism`、`セ 彼に...`、`意３（名２，他１）` 等）
  - **Vimeo URL 実物受領**: 46本のURL、`https://vimeo.com/{ID}/{hash}?fl=tl&fe=ec` 形式。ingest 時に埋込用に変換
  - **Phase 1 進化を反映**: `audioplayers` パッケージ追加済み、`TtsService.speak()` に `wordId` 引数追加済み、43音声ファイルバンドル済み、mnemonic/word overrides 仕組み追加済み
  - **スプリント計画を圧縮**: Phase 1 追加改修に4週間費消したため、Phase 2 実装は 2026-08-04 開始 → 8-30 完成の4週間圧縮スケジュール
  - **リスク追加**: R11（自由文字列 relation）、R12（4週間圧縮）、R13（医系ブロック用動画なし）、R14（画像アスペクト比違い）
  - **DoD 拡張**: 医系ブロック用 Section 8.4 を追加、全体単語数目標を 2,201 → 2,267、ブロック数 46 → 47
- v1.2 (予定): Phase 2 実装着手後（Week 5〜6）に SS 実装での実装上の発見を反映
- v2.0 (予定): Alpha APK 送付後、客户フィードバック反映

**客户確認要事項の現況**（v1.1 更新）:
1. ~~体験版でアクセス可能なコンテンツ範囲~~ → 依然として「第1〜3ブロックのみ」で仮置き、実装後の客户確認で最終化
2. ~~アンロックコードの期限有無~~ → 依然として「期限なし」で仮置き、実装後の客户確認で最終化
3. ✅ Vimeoの動画とブロックの1対1対応関係 → **確定**（46本URL＝46ブロック）
4. Second Stage 出題画面のタテ並び順序 → 見出し語 id 昇順で仮置き、変更要否は客户確認
5. SS 見出し語にエントリがない場合の扱い → 出題除外で仮置き（実データで890語がこれに該当）
6. **v1.1新規**: 医系ブロック（第47）の Vimeo 動画は必要か（現状 46 URL に含まれず）
7. **v1.1新規**: 医系ブロックの発音音声（TTS でよいか、録音音源が必要か）
8. **v1.1新規**: SS 解答語の発音音声（TTS でよいか、録音音源が必要か）
9. **v1.1新規**: 医系ブロックを Second Stage 範囲指定画面でどう視覚的に区別するか（別色/別セクション/デフォルト等）

---
