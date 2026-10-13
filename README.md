# Keyboard Shortcutter

Apple Silicon Mac 向けの、Swift / SwiftUI 製メニューバーアプリです。物理キーの操作とアクションをルールとして保存します。標準設定は **左 Alt（Option）単独押し → ABC 英字**、**右 Alt（Option）単独押し → ひらがな**です。どちらも変更・無効化・削除できます。

## ダウンロード

[GitHub Releases の v1.0.0](https://github.com/foxode-app/keyboard-shortcutter/releases/tag/v1.0.0) から `Keyboard-Shortcutter-1.0.0-arm64.dmg` をダウンロードし、アプリを Applications にドラッグしてください。初回公開はプレビュー版です。対応環境・権限・既知の制限は、この README と [Foxode の製品ページ](https://foxode.com/products/keyboard-shortcutter/) に記載しています。

Releases の DMG がインストール用ファイルです。GitHub が自動生成する「Source code」は、下記の手順でビルドするためのソースコードです。

## 必要環境

- **実行環境: macOS 13 Ventura 以降、Apple Silicon（M シリーズ / arm64）。**
- ビルド: **フル版 Xcode 16 以降**。Command Line Tools 単体では、検証環境の SwiftUI マクロプラグインと XCTest が不足するため、アプリのビルド・テストはできません。
- 開発環境: macOS 27.0.1、Swift 6.4、Xcode 27.0。Swift 言語モードは 5。最小対応 OS 上での実機検証は別途必要です。
- 外部ライブラリ、Homebrew、仮想 HID ドライバ、常駐デーモンは不要です。

## ビルドとインストール

```sh
git clone https://github.com/foxode-app/keyboard-shortcutter.git
cd keyboard-shortcutter
make test
make app
open "build/Keyboard Shortcutter.app"
```

`make app` は arm64 の Release 実行ファイルとアイコンを `build/Keyboard Shortcutter.app` に格納します。既定は開発用のアドホック署名です。`SIGNING_IDENTITY="Developer ID Application: …" make app` で、指定した署名 ID による Hardened Runtime・タイムスタンプ付きの配布用署名に切り替わります。公開前に別途公証とステープルが必要です。[直接配布の手順](docs/DIRECT_RELEASE.md) を参照してください。継続して利用する場合は、アプリを終了し、Finder で `/Applications` にコピーしてからそのコピーを開いてください。権限を付与する前に配置場所を決めておくと設定しやすくなります。

Xcode からは `KeyboardShortcutter.xcodeproj` を開き、`KeyboardShortcutter` スキームで Build / Run できます。ターミナルからの Xcode ビルドは次の通りです。

```sh
make xcode
open "build/xcode/Build/Products/Release/Keyboard Shortcutter.app"
```

すべての Make コマンドとビルドスクリプトは、指定済みの `DEVELOPER_DIR`、現在選択されているフル版 Xcode、`/Applications/Xcode.app` の順に開発環境を選びます。システム全体の `xcode-select` 設定は変更しません。別の場所の Xcode を使う場合は `DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer" make app` と指定できます。Swift Package のテストは `make test` で実行します。Xcode アプリ用スキームにはテストターゲットを含めていません。

## 初回設定と操作

Foxode からの直接配布を対象にしています。Mac App Store への配布を進める場合は [申請準備と機能の対応状況](docs/APP_STORE_RELEASE.md) を参照してください。App Sandbox は無効です。

1. メニューバーのキーボードアイコンから「設定を開く…」を選びます。
2. 入力監視の権限を付与し、案内に従ってアプリを再起動または監視を再開します。
3. 初期ルールの入力ソースを確認します。左 Option には ABC、右 Option には日本語の「ひらがな」を選びます。候補は実行時に取得し、利用可能な ABC とひらがなを優先して初期提案します。ひらがなを識別できない場合、右 Option の入力ソースは未設定になるため手動で選択してください。入力ソースの ID は固定していません。
4. テキストエディタで左 Option を単独で押して離すと英字、右 Option を単独で押して離すとひらがなになることを確認します。

「マッピングを追加」でルールを追加できます。トリガーは左右別の Option / Command / Control / Shift の単独押し、またはキーと修飾キーの組み合わせです。単独押しは離したときに判定し、押している間に別のキーやマウス操作をすると実行しません。長押しだけであれば単独押しとして扱います。キーリピートで繰り返し実行しません。

記録ボタンでショートカット入力欄にフォーカスを置き、組み合わせを押すと登録できます。単独修飾キーは一覧から左右を指定します。アクションは次の 4 種類です。

- **入力ソース選択:** システムの入力ソース一覧から選択。
- **アプリ起動:** ファイル選択ダイアログで `.app` を指定。
- **URL を開く:** `https`、`http`、`mailto` の URL を既定のアプリで開く。
- **ショートカット送信:** 指定したキー操作を前面のアプリへ送信。物理キーが離されるまで待ち、5 秒以内に離されなければ中止します。

メニューから監視の一時停止・再開、設定、終了を操作できます。「ログイン時に起動」は任意で有効化できます。macOS が承認を求める場合は「一般 → ログイン項目」で確認してください。

## Option（Alt）本来の動作を無効にする

設定のマッピング画面で **「Option（Alt）本来の動作を無効にする」** をオンにすると、監視中は左右の物理 Option を前面アプリへ修飾キーとして渡さなくなります。初期値はオフです。このモードではアクセシビリティを許可してください。通常モードの入力監視とは必要な権限が異なります。切り替える前に、押しているキーをすべて離してください。

- 左 Option 単独 → ABC 英字、右 Option 単独 → ひらがなのルールは引き続き動作します。
- Option + K は前面アプリには K として届きます。Option + 矢印や Option を使う特殊文字入力、クリック・スクロールの修飾にも Option を渡しません。Command / Control / Shift など他の修飾キーは維持します。
- このアプリのルール判定は元の物理キー操作を使うため、登録した Control + Option + K などのトリガーは引き続き利用できます。「ショートカット送信」で意図的に送る Option の組み合わせも維持します。
- 一時停止・終了・ショートカット記録中は抑止を停止し、通常の Option に戻ります。オフにすると通常の受動監視へ戻り、設定は再起動後も保持されます。

この機能は実行中のアプリのイベント監視により働きます。起動前・ログイン画面・Secure Keyboard Entry などの保護された入力、ハードウェア状態を直接読むアプリまで一律に無効化する機能ではありません。音量・輝度などの特殊メディアキーとの組み合わせも対象外になる場合があります。権限付きの実機動作は [確認手順](docs/MANUAL_TESTS.md) に沿って検証してください。

## 権限とプライバシー

Option の動作を無効にしない場合は **受動的な `CGEventTap`（listen-only）** で入力イベントを観測します。元のキーイベントを削除・変更しないため、登録した組み合わせは前面のアプリや macOS にも届き、既存ショートカットと両方が動く場合があります。必要な「入力監視」権限は「システム設定 → プライバシーとセキュリティ → 入力監視」で付与してください。

Option の動作を無効にする場合は **能動的な `CGEventTap`（defaultTap）** で Option の押下・解放イベントを抑止し、その他のキー・マウス・スクロールイベントから Option フラグを除去します。この書き換えに必要な権限は「アクセシビリティ」です。このモードでは入力監視を追加条件にしません。権限が足りない場合や監視を開始できない場合は開始失敗を表示し、無効化が動作中とは表示しません。[Apple のイベントタップ仕様](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions) を参照してください。

「ショートカット送信」も `CGEvent` による合成入力のため、アクセシビリティが必要です。どちらかの機能を利用する場合に、設定画面から明示的に許可してください。Option 抑止がオフで、入力ソース切り替え・アプリ起動・URL 起動だけであればアクセシビリティは不要です。

入力された文字列は取得・記録・保存せず、判定に必要なキーコードと押下状態のみをメモリで扱います。ネットワーク通信、解析、テレメトリー、管理者権限の要求、シェルコマンド実行はありません。URL アクションで起動したブラウザなどは、通常どおり通信します。

## 設定ファイル

ルールは `~/Library/Application Support/KeyboardShortcutter/settings.json` にバージョン付き JSON として保存します。初期ルールは設定ファイルがない場合のみ作成します。既存設定をアップグレード時に初期化しません。Option の抑止設定は `disableOptionModifiers` として保存し、項目がない既存設定ではオフとして読み込みます。破損した設定や未対応のスキーマはエラーとして表示し、元ファイルを保持します。修復が必要な場合は、アプリ終了後にファイルをバックアップしてから編集してください。

正式な Bundle ID は `com.foxode.keyboardshortcutter.app` です。旧ローカル版（`local.keyboardshortcutter.app`）からは一時停止状態を、新版に設定がない場合のみ引き継ぎます。ルール・Option 抑止設定の JSON 保存先は変更しません。入力監視・アクセシビリティの許可は新しいアプリに対して再設定してください。旧版を終了してから入れ替え、「ログイン時に起動」は新版で有効にし直してください。

## 制限とトラブルシューティング

- **監視を開始できない:** 通常モードでは入力監視、Option 抑止モードではアクセシビリティがオンかを確認してください。許可したアプリと起動したアプリが同じ場所かも確認し、アプリを再起動します。アドホック署名は再ビルドにより変わるため、権限一覧で削除・追加が必要な場合があります。
- **Option が無効にならない:** 設定のチェック、監視中の表示、アクセシビリティ権限を確認してください。一時停止・キー記録を終了し、すべてのキーを離してから TextEdit で確認します。権限変更後は再起動が必要な場合があります。監視エラーが表示される間は抑止できません。
- **一部のアプリで反応しない:** パスワード欄や Secure Keyboard Entry などではイベントを取得できないことがあります。TextEdit など通常の入力欄でも確認してください。
- **切り替わらない:** macOS の「キーボード → テキスト入力」で入力ソースを追加し、アプリ内の一覧を更新して選び直してください。入力方式の変換状態やアプリごとの入力ソース設定も影響します。
- **競合の警告:** 同じトリガーを持つ有効なルールが複数あると、どれも実行しません。片方を無効化するかトリガーを変更してください。macOS や他アプリのショートカット競合は自動検出できません。
- **キーの表示と刻印が違う:** キーコードは物理位置に対応し、文字ラベルは主に ANSI 配列です。JIS / ISO や非英語配列では記録機能と実機確認を併用してください。
- **Caps Lock:** 通常の flagsChanged はロック状態を表し、物理的な離した瞬間を確実に取得できないため、単独押しトリガーは提供しません。
- **ログイン時に起動しない:** `/Applications` のアプリで有効化し、macOS のログイン項目の承認を確認してください。

## 開発

| 場所 | 内容 |
| --- | --- |
| `Sources/ShortcutCore/` | ルール、キー判定、設定保存のロジック |
| `Sources/KeyboardShortcutter/` | SwiftUI 画面と macOS の入力・権限連携 |
| `Tests/` | ロジックと権限不要の macOS 統合テスト |
| `Resources/` | Info.plist とアプリアイコン |
| `scripts/` | Xcode 選択、アプリ組み立て、アイコン生成 |
| `KeyboardShortcutter.xcodeproj/` | Xcode 用の共有プロジェクトとスキーム |
| `docs/` | 設計、実機確認、配布手順 |

```sh
make icon                  # AppKit のソースから .icns を再生成
make build                 # Debug ビルド
make test                  # 判定・保存・検証、および権限不要のmacOS統合テスト
./scripts/swift-env.sh xcrun swift test --filter TriggerMatcherTests
make format                # Swift 標準 formatter で整形（利用可能なツールチェーン）
make lint                  # 同じ規約を検査
```

Swift は 4 スペース、型は UpperCamelCase、メソッド・変数は lowerCamelCase を使用します。外部依存がないため依存関係ロックファイルは生成されません。変更時は `make test`、`make lint`、`make app` を実行してください。コミットは簡潔な命令形で、PR には目的・検証結果と UI 変更のスクリーンショットを含めます。

アプリは Apple のシステムフレームワークを使用し、第三者のソースコード・ライブラリ・フォントを同梱していません。アプリアイコンは `scripts/create-icon.swift` の図形描画から生成しています。API キー、署名証明書、秘密鍵、個人の設定、ビルド出力はコミットしないでください。

設計と拡張手順は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、実機確認は [docs/MANUAL_TESTS.md](docs/MANUAL_TESTS.md) を参照してください。ユニットテストだけでは、権限付きのグローバル入力動作を検証できません。

## 検証結果（2026-10-13）

macOS 27.0.1 / Apple Silicon / Xcode 27.0 で、以下を確認しました。

- `make test`: 83 件成功（純粋ロジック 43 件、macOS 統合 40 件）。Option抑止のイベント変換、AppKitでの通常文字への変換、設定互換性、旧 Bundle ID からの一時停止設定の移行を含みます。
- `make lint`、`make app`、Xcode プロジェクトの Release ビルドが成功。
- 正式 Bundle ID・アイコンを含む arm64 `.app` のアドホック署名検証が成功。
- 旧ローカル版の短時間起動確認は 2026-10-12 に実施。正式 Bundle ID の署名済み配布版については、別途実機確認が必要です。
- 設定画面の起動・内容サイズ 880×660、初期ルール 2 件、ABC / ひらがなの列挙を確認。

入力監視・アクセシビリティ権限を許可した状態での実キーボード操作、グローバルなOption抑止、キー送信、ログイン時起動、macOS 13 実機での動作は未検証です。[実機テストチェックリスト](docs/MANUAL_TESTS.md) に沿って確認してください。

## ライセンス

[MIT License](LICENSE)。Copyright (c) 2026 Foxode.
