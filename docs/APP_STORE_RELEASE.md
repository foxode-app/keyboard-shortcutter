# Keyboard Shortcutter の Mac App Store 申請準備

現在は **Foxode からの Developer ID 署名・公証付き直接配布**を優先しています。[直接配布の手順](DIRECT_RELEASE.md) を参照してください。App Sandbox は無効であり、そのまま Mac App Store に提出することはできません。App Store Connect へのアプリ登録・ビルドアップロード・審査提出は未実施です。

## 直接配布版との違い

正式な Bundle ID は `com.foxode.keyboardshortcutter.app`、バージョンは 1.0.0（ビルド 1）です。アプリのアイコンとユーティリティのカテゴリを設定済みです。`make app` は既定ではローカル用アドホック署名、`SIGNING_IDENTITY` を指定すると Developer ID の Hardened Runtime・タイムスタンプ付き署名を行います。

自分で配布する場合は、自身の Apple Developer Program アカウントと署名環境を用意してください。Developer ID による直接配布と、App Store の署名・Sandbox 対応・審査は別の手順です。証明書や秘密鍵はソースコードに保存しません。

App Store 版を追加する場合は、下記の機能検証後に Xcode の Team・App Store 用署名を構成し、Archive を作成して App Store Connect にアップロードします。[Apple の署名 ID 管理](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates)

## 機能の対応方針

Mac App Store では App Sandbox が必須です。[Apple の Sandbox 設定手順](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

| 現在の機能 | 実装 | 申請前に必要な対応 |
| --- | --- | --- |
| 左右の修飾キー単独押し・ショートカットの監視 | `EventMonitor.swift` の `.listenOnly` | 入力監視の許可を使うイベント監視は Sandbox 内でも対応可能。実際の署名済みビルドで検証する。 |
| Option 本来の動作を無効化 | `.defaultTap` と `OptionEventFilter.swift` によるイベント書換え・抑止 | アクセシビリティ権限に依存。現行方式の Sandbox・審査適合性を確認し、対応できなければ App Store 版から除外する。 |
| 前面アプリへのショートカット送信 | `ActionExecutor.swift` の `CGEvent.post` | アクセシビリティ権限に依存。実行できることと審査に適合することを分けて確認する。 |
| ABC・ひらがな等への切替 | `InputSourceService.swift` の `TISSelectInputSource` | Sandbox 内で、他アプリの入力欄にフォーカスしたまま切替できるか検証する。 |
| アプリ起動 | `NSOpenPanel` で選択したパスを保存 | 標準の Applications 以外の場所も含め、アプリ再起動後にアクセスできるか検証する。必要なら security-scoped bookmark を導入する。 |
| URL を開く・ログイン時起動・設定保存 | `NSWorkspace`・`SMAppService`・Application Support | Sandbox 内で動作確認する。設定保存先のコンテナ化と既存設定の移行方針を確認する。 |

受動監視については [Apple DTS の回答](https://developer.apple.com/forums/thread/811443) に、入力監視権限による `CGEventTap` は Sandbox アプリでも利用可能と説明されています。グローバルなキー監視全体が禁止されているわけではありません。

Apple は [Sandbox と互換性のない機能](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) に支援アプリでのアクセシビリティ API 使用を挙げています。これは現行の Option 抑止・キー送信の確認が必要な根拠であり、すべての `CGEvent` API が一律禁止という意味ではありません。

## 提出までの作業

1. **配布者情報を確定する。** Apple Developer Program に加入し、使用する Team、公開名、無料または有料、配布地域を決める。アカウントの契約状況も確認する。
2. **App Store 版の仕様を確定する。** 上の表の検証を行い、提供可能な機能を決める。権限の履歴による誤判定を避けるため、新しいテスト環境でも確認する。
3. **配布用ビルドを構成する。** Sandbox と最小限の Entitlements、Team と配布用署名、登録する Bundle ID、アイコン、カテゴリ、バージョンを確認する。正式な Bundle ID は `com.foxode.keyboardshortcutter.app`。
4. **プライバシーとサポートを整える。** 公開プライバシーポリシー URL、アプリ内のポリシーリンク、サポート URL と連絡先を用意する。現行コードは入力文字列の記録、ネットワーク送信、解析 SDK を持たないため、プライバシー申告は「データを収集しない」が候補。最終ビルドに合わせて回答する。[Apple のプライバシー申告手順](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
5. **App Store Connect に新規 macOS アプリを作成する。** 名前、主言語、Bundle ID、SKU を登録する。アプリレコードを作成してからビルドをアップロードする。[Apple のアプリ登録手順](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
6. **紹介文と画像を登録する。** 説明、キーワード、年齢制限の回答、権利情報、審査連絡先を用意する。Mac のスクリーンショットは 16:10 の指定サイズで、最低1枚必要。実際に提供する機能だけを紹介する。[Apple のスクリーンショット仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
7. **Archive と検証を行う。** Xcode Organizer で App Store Connect 向けの検証・アップロードを行う。処理済みビルドを選択し、価格・配信地域・公開方法・輸出コンプライアンス等の必要項目を完了する。
8. **審査用の操作説明を付けて提出する。** メニューバーからの起動、入力監視の許可、左右 Option の動作、入力ソースの設定、監視停止手順を説明する。審査承認前に公開完了とは扱わない。

## 登録情報の下書き

機能が確定するまで、次の内容は候補です。

| 項目 | 候補または確認事項 |
| --- | --- |
| アプリ名 | Keyboard Shortcutter |
| プラットフォーム | macOS |
| 主言語 | 日本語 |
| カテゴリ | ユーティリティ |
| バージョン | 1.0.0、初回ビルド番号 1 |
| 対応環境 | 現在は macOS 13 以降、Apple Silicon のみ。Intel 対応とは表記しない。 |
| SKU | `keyboard-shortcutter-macos` を候補とし、アカウント内の重複を確認する。 |
| Bundle ID | `com.foxode.keyboardshortcutter.app`。App Store Connect 登録時に利用可否を確認する。 |
| 紹介文の要点 | 左右の修飾キーやキーの組み合わせに、入力ソース切替・アプリ起動・URL を割り当てるメニューバーアプリ。Sandbox で検証できた機能に合わせて調整する。 |
| 価格・地域・公開方法 | 配布者が決定する。 |
| プライバシーポリシー・サポート URL | 公開先と連絡先を確定する。 |

## 検証状況

- 2026年10月13日に `make test` を再実行し、83 件成功。
- `make xcode` でローカル用アドホック署名の Release ビルドが成功。
- 直接配布準備として Bundle ID・アイコン・任意の Developer ID 署名経路を追加。Sandbox は無効のまま。テスト成功は Sandbox 適合や審査承認を示すものではない。
- 入力権限付きの実操作、Sandbox 内での入力ソース切替、macOS 13 実機での動作は未検証。[実機テスト](MANUAL_TESTS.md) を参照する。

`PrivacyInfo.xcprivacy` は現時点で存在しません。ただし [Required Reason API の現行説明](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) の対象 OS に macOS は含まれていないため、純粋 macOS アプリについて未作成だけを申請不可の理由にはしません。公開プライバシーポリシーと App Store Connect のプライバシー申告は別途必要です。
