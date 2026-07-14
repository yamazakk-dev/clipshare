# ClipShare

ClipShare is a lightweight, one-to-one text clipboard synchronization tool for macOS and Android. It connects directly over a trusted LAN or Tailscale network, with the Mac acting as a WebSocket server and the Android device as its client.

ClipShare は、Mac と Android の間でテキストクリップボードを同期する1対1接続用アプリです。Mac が WebSocket サーバー、Android がクライアントとして動作し、同一LANまたは Tailscale 経由で接続します。

- 既定ポート: `4747`
- 同期対象: テキスト
- 認証: Macで生成される共有トークン
- 通信経路: 同一LANまたは Tailscale

## アーキテクチャ

```text
Mac                                      Android

NSPasteboard                             ClipboardManager
    │                                          ▲
    ▼                                          │
PasteboardWatcher                         SyncService
    │                                     (OkHttp WebSocket)
    ▼                                          │
LoopGuard ── ClipServer :4747 ◀── LAN / Tailscale ──┘
              (WebSocket + token認証)

Android → Mac の送信操作:
  クイック設定タイル / テキスト共有シート → SyncService → ClipServer
```

同じテキストが受信直後に送り返されないよう、Mac・Androidの両側で `LoopGuard` によるループ防止を行います。

## Mac側セットアップ

動作要件は macOS 13 以降です。

### ビルド

```sh
cd mac
swift build -c release
```

実行ファイルは `mac/.build/release/clipshare-mac` に生成されます。手動で起動する場合は次を実行します。

```sh
cd mac
.build/release/clipshare-mac
```

ClipShare はDockには表示されず、メニューバーに常駐します。初回起動時にペアリング用トークンが自動生成されます。メニューの「トークンをコピー」をクリックすると、Androidへ入力するトークンをコピーできます。

### launchdへ登録

手順は `CLAUDE.md` と同じです。`mac/com.ymac.clipshare.plist` の `ProgramArguments` には `/path/to/clipshare` というプレースホルダーが入っています。**ファイルをコピーする前に**、これを自分のクローン先ディレクトリの絶対パスへ書き換えてください。

例えば、リポジトリを `/Users/example/src/clipshare` にクローンした場合、設定する実行ファイルパスは次のとおりです。

```text
/Users/example/src/clipshare/mac/.build/release/clipshare-mac
```

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

以降、本README内の `/path/to/clipshare` は各自のクローン先ディレクトリに読み替えてください。リポジトリを移動した場合も、plist内のパスを更新してから再登録します。

登録解除:

```sh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ymac.clipshare.plist"
```

標準出力とエラーは次のファイルに記録されます。

```text
/tmp/com.ymac.clipshare.stdout.log
/tmp/com.ymac.clipshare.stderr.log
```

## Android側セットアップ

Android 10（API 29）以降に対応しています。ビルドにはJDK 17とAndroid SDKが必要です。

### ビルドとインストール

USBデバッグを有効にしてAndroid端末を接続し、次を実行します。

```sh
cd android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 接続設定

AndroidでClipShareを開き、設定画面へ次の値を入力します。

- ホスト: `your-mac`（MacのTailscale MagicDNS名の例）
- ポート: `4747`
- トークン: Macのメニューバーからコピーしたトークン

ホストの初期値は空欄です。Tailscaleを使用する場合はMacのMagicDNS名またはTailscale IPアドレス、同一LANでは到達可能なホスト名またはLAN IPアドレスを指定してください。

設定を保存して「同期サービスを開始」を押します。通知の表示を求められた場合は許可してください。接続後、設定画面と常駐通知が「接続済み」になります。

安定して同期を続けるため、設定画面の「バッテリー最適化の設定を開く」からClipShareを最適化対象外にしてください。GalaxyやXiaomiなど、独自のバックグラウンド制限がある端末では、端末メーカーの設定でもバックグラウンド動作を許可してください。

### クイック設定タイル

1. 通知シェードを開く
2. クイック設定の編集画面を開く
3. 「クリップを送信」タイルを有効なタイルへ追加する
4. Androidでテキストをコピーした後、タイルをタップしてMacへ送信する

### 共有シート

テキストを共有できるアプリで共有メニューを開き、「ClipShareへ送信」を選択します。共有されたテキストがMacへ送信され、処理完了後に共有画面は自動で閉じます。

## 使い方

### MacからAndroid

Mac側メニューで同期をONにし、Androidの同期サービスを起動して接続済みにします。その状態でMac上のテキストをコピーすると、Androidのクリップボードへ自動的に反映されます。

### AndroidからMac

Android 10以降では通常アプリによるバックグラウンドのクリップボード読取が制限されているため、次のいずれかで送信します。

- テキストをコピーし、クイック設定の「クリップを送信」をタップする
- 対象テキストを共有し、「ClipShareへ送信」を選択する

受信したテキストはMacのクリップボードへ書き込まれます。

## 既知の制限

- Android 10以降のバックグラウンド読取制限により、AndroidでコピーしただけではMacへ自動送信されません。完全自動化はTask 7として調査済みですが、Shizukuなど追加セットアップが必要なため現在は実装を見送っています。
- 通信は暗号化されていない平文WebSocketです。共有トークンも通信経路上では平文になるため、信頼できる同一LANまたは暗号化されたTailscaleネットワーク内でのみ使用してください。インターネットへポート`4747`を直接公開しないでください。
- テキストクリップボードのみを対象とし、画像やファイルは同期しません。
- 1台のMacと1台のAndroidでの利用を想定しています。

## トラブルシューティング

### 接続できない

次を順に確認してください。

1. MacとAndroidが同じLAN、または同じTailscaleネットワークに接続されている
2. Androidのホストが `your-mac` のようなTailscale MagicDNS名、または到達可能なホスト名／IPアドレスになっている
3. MacとAndroidのポートがどちらも `4747` になっている
4. Androidへ入力したトークンがMacのメニューに表示されるトークンと完全に一致している
5. Mac側メニューの同期がONで、ClipShareが起動している
6. macOSのファイアウォールが `clipshare-mac` の受信接続を許可している
7. Androidの同期サービスが開始され、常駐通知が表示されている

Macでポートの待受を確認するには、次を実行します。

```sh
lsof -nP -iTCP:4747 -sTCP:LISTEN
```

launchdで起動している場合はログも確認してください。

```sh
tail -f /tmp/com.ymac.clipshare.stdout.log /tmp/com.ymac.clipshare.stderr.log
```

### Android側の接続が頻繁に切れる

- ClipShareをバッテリー最適化の対象外にする
- メーカー独自のスリープ／自動起動制限から除外する
- Android設定画面で同期サービスを一度停止し、再度開始する
- Wi-FiまたはTailscale接続を確認する

### タイルから送信できない

- 先にAndroidでテキストをコピーしてからタイルをタップする
- Androidのロックを解除して再試行する
- ClipShareのトークンと接続設定を確認する

接続中でない場合も、送信操作を行った最新のテキスト1件は保持され、再接続後に送信されます。
