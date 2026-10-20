# Foxode からの直接配布

対象は Apple Silicon（arm64）/ macOS 13 以降です。正式な Bundle ID は `com.foxode.keyboardshortcutter.app`、現在の直接配布用ビルドは1.1.7（ビルド9）です。App Sandbox は使いません。最小対応 OS 上での実機検証は未実施です。

2026-10-20時点で、1.1.7の自動テスト146件（純粋ロジック51件、macOS統合95件）、lint、Developer ID署名付きビルドが成功しています。`/Applications` への適用後、監視中と既存設定のハッシュ一致を確認しました。macOS 27.0.1 / Apple Siliconで、テスト用のAppKit入力欄と一時プロファイルのChromeに対し、1.1.7本体経由で右Option単独と左Option→右Optionを自動操作し、AppKit・Chromeとも24回中24回「あいう」になりました。Codexでの実操作、他の入力先・IME・キーボード配列や全操作条件の確認ではありません。1.1.7の配布用アプリとDMGのApple公証が成功し、署名・公証チケット・Gatekeeperを検証しています。GitHub Releasesで配布します。

## ビルドと署名

必要なものはフル版 Xcode、秘密鍵を伴う有効な Developer ID Application 証明書、および `notarytool` 用にキーチェーンに保存した認証プロファイルです。API キー・秘密鍵・キーチェーン情報をリポジトリへ入れないでください。

```sh
make test
make lint
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
codesign --verify --strict --verbose=2 "build/Keyboard Shortcutter.app"
codesign --display --verbose=4 "build/Keyboard Shortcutter.app"
```

`SIGNING_IDENTITY` は証明書名か証明書の SHA-1 値を指定できます。指定がない場合と `-` の場合は開発用アドホック署名です。Developer ID 署名時は `--options runtime --timestamp` を付け、不要な Entitlements や Hardened Runtime の例外は加えません。署名に失敗した場合はスクリプトが終了し、アドホック署名へ切り替えません。

アイコンのソースは `scripts/create-icon.swift` です。`make icon` で `Resources/KeyboardShortcutter.icns` を再生成できます。ビルドは保存済みの `.icns` を使い、Xcode プロジェクトにも同じリソースを含めます。

## 公証と配布ファイル

配布には署名済みアプリを格納した DMG を使います。次の例は、上記の Developer ID 署名付きビルドを作成した後に実行します。証明書名とプロファイル名は、自分のキーチェーンに保存したものへ置き換えます。出力先に同じ名前の DMG がある場合は、既存ファイルを別の場所へ保管してから実行してください。

```sh
shortcutter_payload_dir="$(mktemp -d "$PWD/build/dmg-content.XXXXXX")"
ditto "build/Keyboard Shortcutter.app" "$shortcutter_payload_dir/Keyboard Shortcutter.app"
ln -s /Applications "$shortcutter_payload_dir/Applications"
hdiutil create -volname "Keyboard Shortcutter" -srcfolder "$shortcutter_payload_dir" \
  -format UDZO -fs HFS+ build/Keyboard-Shortcutter-1.1.7-arm64.dmg
codesign --sign "Developer ID Application: Your Name (TEAMID)" --timestamp \
  --identifier com.foxode.keyboardshortcutter.app.dmg \
  build/Keyboard-Shortcutter-1.1.7-arm64.dmg
./scripts/swift-env.sh xcrun notarytool submit build/Keyboard-Shortcutter-1.1.7-arm64.dmg \
  --keychain-profile "YOUR_NOTARY_PROFILE" --wait
```

公証結果が `Accepted` であることを確認してから、配布する DMG にチケットを添付します。失敗時は `notarytool log` で原因を確認し、公開しません。

```sh
./scripts/swift-env.sh xcrun stapler staple build/Keyboard-Shortcutter-1.1.7-arm64.dmg
./scripts/swift-env.sh xcrun stapler validate build/Keyboard-Shortcutter-1.1.7-arm64.dmg
codesign --verify --strict --verbose=2 build/Keyboard-Shortcutter-1.1.7-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 \
  build/Keyboard-Shortcutter-1.1.7-arm64.dmg
shasum -a 256 build/Keyboard-Shortcutter-1.1.7-arm64.dmg
```

Apple の [配布パッケージ作成手順](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) に従い、アプリを署名した後に DMG を署名し、最外部の DMG を公証・ステープルします。中の `.app` への個別ステープルは必須ではありません。公証ログで DMG と内包するアプリが対象になっていることを確認します。署名後に `.app` 内のファイルを変更せず、配布ファイルの SHA-256 とバージョンをリリース記録に残します。

公開時はバージョンに対応するソースコードのタグを作成し、[GitHub Releases](https://github.com/foxode-app/keyboard-shortcutter/releases) に検証済み DMG と SHA-256 のチェックサムを添付します。認証キー・署名証明書・公証ログ・開発用出力は添付しません。Foxode の製品ページには GitHub Releases のダウンロードリンク、対応環境、権限の説明、プライバシー説明と問い合わせ先を掲載します。公開前にダウンロードした実物で署名、Gatekeeper、起動、権限付与と主要機能を確認し、未検証の項目はリリースノートで明示します。[実機チェックリスト](MANUAL_TESTS.md) を使用してください。

## 初回起動と旧版からの移行

1. 旧版が実行中なら終了します。新版を `/Applications` に置いてから開きます。
2. 通常のキー監視には「入力監視」を許可します。Fキーの割り当て、「Option 本来の動作を無効にする」、音量などのシステム操作、または「ショートカット送信」を使う場合は「アクセシビリティ」を許可します。1.1.5以降は、ひらがなを含む入力ソース選択自体にアクセシビリティを必要としません。1.1.7は、許可されている場合に限り、ひらがなへの切り替えが前面アプリに反映されなかったときの自動補正にアクセシビリティを使います。旧版1.1.3は擬似かなキーを送るため要件が異なりました。
3. Bundle ID が旧版の `local.keyboardshortcutter.app` から変わるため、新版に対して権限を許可し直します。必要に応じて権限一覧に残る旧版を取り除き、新版を追加して再起動します。
4. `~/Library/Application Support/KeyboardShortcutter/settings.json` のルールと Option 抑止設定はそのまま読み込みます。一時停止状態は、新版に保存済みの値がない場合のみ旧版から引き継ぎます。旧版の設定は削除しません。
5. 旧版のログイン項目を解除し、新版で「ログイン時に起動」を設定し直します。アプリは権限やログイン項目の許可を自動で引き継ぎません。

入力文字列の記録・保存・送信、ネットワーク解析、管理者権限、外部ドライバはありません。URL アクションで起動する既定のアプリは通常どおり通信します。
