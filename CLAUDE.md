# ClipShare

ClipShare は、Mac と Android のテキストクリップボードを同一 LAN または Tailscale 経由で双方向同期する常駐アプリです。Mac 側が WebSocket サーバー、Android 側がクライアントとして動作します。

## 構成

- `mac/`: SwiftPM 製の Mac アプリと共通プロトコル層
- `android/`: Android アプリ（今後実装）
- `docs/superpowers/`: 設計書と実装計画

## Mac のビルドとテスト

```sh
cd mac
swift build
swift test
```

通信には固定ポート `4747` を使用します。ペアリング用トークンなどの秘密情報は、コードやリポジトリへ保存しないでください。
