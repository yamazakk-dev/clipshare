# ClipShare

ClipShare は、Mac と Android のテキストクリップボードを同一 LAN または Tailscale 経由で双方向同期する常駐アプリです。Mac 側が WebSocket サーバー、Android 側がクライアントとして動作します。

## 構成

- `mac/`: SwiftPM 製の Mac アプリと共通プロトコル層
- `android/`: Android アプリ
- `docs/superpowers/`: 設計書と実装計画

既知の制限: Android の JVM ユニットテストは Maven 版 `org.json`、実機は Android framework 版を使用するため、パーサーの境界挙動が異なる可能性があります。

## Mac のビルドとテスト

```sh
cd mac
swift build
swift test
swift build -c release
```

release ビルドの実行ファイルは `mac/.build/release/clipshare-mac` に生成されます。通信ポートの既定値は `4747` です。ペアリング用トークンは初回起動時に自動生成され、`UserDefaults` に保存されます。トークンなどの秘密情報をコードやリポジトリへ保存しないでください。

## Mac で起動

```sh
cd mac
swift run clipshare-mac
```

起動後は Dock に表示せず、メニューバーの ClipShare アイコンから接続状態、同期 ON/OFF、最後に同期したテキスト、ペアリング用トークンを確認できます。

## launchd へ登録

`mac/com.ymac.clipshare.plist` の `ProgramArguments` には `/path/to/clipshare` というプレースホルダーが入っています。**LaunchAgentsへコピーする前に**、自分のクローン先ディレクトリの絶対パスへ書き換えてください。リポジトリを移動した場合も同様に更新して再登録します。

```sh
cd mac
swift build -c release
# com.ymac.clipshare.plist の /path/to/clipshare を実際のクローン先へ書き換える
mkdir -p "$HOME/Library/LaunchAgents"
cp com.ymac.clipshare.plist "$HOME/Library/LaunchAgents/com.ymac.clipshare.plist"
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ymac.clipshare.plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ymac.clipshare.plist"
launchctl kickstart -k "gui/$(id -u)/com.ymac.clipshare"
```

登録解除:

```sh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ymac.clipshare.plist"
```

メニューの「終了」でアプリを停止できます。LaunchAgent の登録自体も解除する場合は、上記の `bootout` を実行してください。
