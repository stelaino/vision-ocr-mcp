<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-6.0+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0+">
  <img src="https://img.shields.io/badge/MCP-2025--11--25-blue?style=flat-square" alt="MCP Spec">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT">
  <img src="https://img.shields.io/badge/オフライン-100%25-success?style=flat-square" alt="100% オフライン">
</p>

<h1 align="center">Vision OCR MCP</h1>

<p align="center">
  <strong>macOS ネイティブオフライン OCR — Model Context Protocol サーバー</strong>
</p>

<p align="center">
  Apple Vision Framework による高性能テキスト抽出。<br>
  Streamable HTTP と Stdio デュアルトランスポート対応。クラウド不要・APIキー不要・データはMacから出ません。
</p>

<p align="center">
  <a href="README.md">English</a> •
  <a href="README.zh.md">简体中文</a> •
  <a href="README.ja.md">日本語</a>
</p>

---

## 特長

- **ネイティブ性能** — Swift と Apple Vision Framework で構築。写真アプリのテキスト認識と同じエンジン
- **デュアルトランスポート** — リモート/ネットワーク連携用 Streamable HTTP + ローカル IDE 連携用 Stdio
- **バックグラウンドサービス** — macOS LaunchAgent としてインストール、ログイン時自動起動、ターミナル不要
- **Web 管理画面** — テスト、モニタリング、設定が可能な内蔵管理インターフェース
- **CLI ファースト** — MCP クライアント不要のスタンドアロン OCR ツールとしても使用可能
- **100% オフライン** — ネットワーク依存ゼロ、全処理がデバイス上で完結
- **マルチフォーマット** — 画像 (PNG, JPEG, HEIC, TIFF, WebP) とマルチページ PDF
- **構造化出力** — プレーンテキスト、バウンディングボックス付き JSON、または Markdown
- **多言語認識** — 中国語、英語、日本語、韓国語など 15+ 言語対応
- **Apple Silicon 最適化** — ネイティブ ARM64 バイナリ、Neural Engine アクセラレーション

## クイックスタート

### Homebrew でインストール（推奨）

```bash
brew install stelaino/tap/vision-ocr-mcp
```

### ソースからビルド

```bash
git clone https://github.com/stelaino/vision-ocr-mcp.git
cd vision-ocr-mcp
swift build -c release
cp .build/release/vision-ocr-mcp /usr/local/bin/
```

### MCP サーバーとして実行

```bash
# Stdio トランスポート（Claude Desktop、Cursor、Windsurf 等向け）
vision-ocr-mcp serve --transport stdio

# Streamable HTTP トランスポート（リモート/ネットワーククライアント向け）
vision-ocr-mcp serve --transport http --port 8765

# HTTP モード + Web 管理画面
vision-ocr-mcp serve --transport http --port 8765 --ui
```

### バックグラウンドサービス（自動起動）

```bash
# macOS LaunchAgent としてインストール（ログイン時に自動起動、バックグラウンド実行）
vision-ocr-mcp service install --port 8765

# バックグラウンドサービス管理
vision-ocr-mcp service start
vision-ocr-mcp service stop
vision-ocr-mcp service restart
vision-ocr-mcp service status

# バックグラウンドサービスのアンインストール
vision-ocr-mcp service uninstall
```

インストール後、サーバーはグローバルバックグラウンドサービスとして実行されます — ターミナルウィンドウ不要、再起動後も自動復旧、`http://localhost:8765/mcp` でアクセス可能。

### CLI ツールとして使用

```bash
# 画像からテキスト抽出
vision-ocr-mcp ocr ~/Desktop/screenshot.png

# 構造化出力（バウンディングボックス付き JSON）
vision-ocr-mcp ocr ~/Documents/scan.pdf --format json

# 言語とページ範囲を指定
vision-ocr-mcp ocr invoice.pdf --lang ja+en --pages 1-3

# ファイルに出力
vision-ocr-mcp ocr image.png --output result.txt
vision-ocr-mcp ocr image.png --output result.json --format json

# ディレクトリをバッチ処理
vision-ocr-mcp ocr ./scans/ --output-dir ./results/ --format markdown
```

## Web 管理画面

HTTP モードで実行中に `http://localhost:8765/ui` にアクセスして管理画面を利用できます。

**機能:**
- ライブ OCR テスト — 画像をドラッグ＆ドロップで即時認識
- リクエスト履歴と統計
- サーバー設定管理
- パフォーマンスモニタリング（レイテンシ、スループット）
- 多言語インターフェース切替（EN / 中文 / 日本語）

## MCP クライアント設定

### Claude Desktop / Cursor / Windsurf

MCP 設定に追加：

```json
{
  "mcpServers": {
    "vision-ocr": {
      "command": "vision-ocr-mcp",
      "args": ["serve", "--transport", "stdio"]
    }
  }
}
```

### Streamable HTTP（リモート）

```json
{
  "mcpServers": {
    "vision-ocr": {
      "url": "http://localhost:8765/mcp",
      "headers": {
        "Authorization": "Bearer your-api-key"
      }
    }
  }
}
```

認証付きでサーバーを起動：

```bash
vision-ocr-mcp serve --transport http --port 8765 --api-key "your-secret-key"
```

## 利用可能なツール

| ツール | 説明 | 入力 |
|--------|------|------|
| `ocr_extract_text` | 画像または PDF からテキスト抽出 | `file_path`、`base64`、または `url` |
| `analyze_document` | レイアウト付き構造化ドキュメント分析 | `file_path` + オプション |
| `analyze_document_structure` | スマート構造解析（テーブル/段落/リスト） | `file_path`（macOS 26+） |
| `detect_text_regions` | バウンディングボックスでテキスト領域検出 | `file_path` |
| `detect_barcodes` | QR コードとバーコードを検出 | `file_path` |
| `detect_document_bounds` | ドキュメント境界検出 + 自動クロップ | `file_path` |
| `ocr_screen_region` | 画面領域をキャプチャして OCR | `x`、`y`、`width`、`height` |
| `ocr_clipboard` | システムクリップボードの画像を OCR | （パラメータ不要） |
| `watch_folder` | フォルダ監視で自動 OCR | `folder_path` |
| `batch_ocr` | 複数ファイルのバッチ処理 | `file_paths[]` |

### ツールパラメータ

#### `ocr_extract_text`

| パラメータ | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `file_path` | string | * | ローカルファイルパス（`~` 展開対応） |
| `base64` | string | * | Base64 エンコード画像データ |
| `url` | string | * | 画像 URL（自動ダウンロード） |
| `languages` | string | いいえ | 認識言語、例: `"ja+en"` |
| `format` | string | いいえ | 出力形式: `text` \| `json` \| `markdown` |
| `pages` | string | いいえ | PDF ページ範囲、例: `"1-5"` |

*`file_path`、`base64`、`url` のいずれか一つが必須。

### レスポンス例

```json
{
  "text": "こんにちは世界\nこれはサンプル文書です。",
  "pages": [
    {
      "page": 1,
      "blocks": [
        {
          "text": "こんにちは世界",
          "confidence": 0.97,
          "boundingBox": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.04 }
        }
      ]
    }
  ],
  "metadata": {
    "totalPages": 1,
    "languages": ["ja"],
    "processingTime": "0.25s"
  }
}
```

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────┐
│                   CLI インターフェース                      │
│              (ArgumentParser)                              │
├──────────────┬──────────────────────────────────┬────────┤
│              │                                   │        │
│  ┌───────────▼──────────┐  ┌────────────────────▼─────┐ │
│  │   Stdio トランスポート │  │  HTTP トランスポート     │ │
│  │   (JSON-RPC stdin)   │  │  (Streamable HTTP)       │ │
│  └───────────┬──────────┘  │  + Web UI (静的ファイル) │ │
│              │              └────────────┬─────────────┘ │
│  ┌───────────▼──────────────────────────▼───────────────┐│
│  │              MCP サーバーコア                          ││
│  │        (ツールレジストリ + ハンドラー)                  ││
│  └───────────────────────┬──────────────────────────────┘│
│                          │                                │
│  ┌───────────────────────▼──────────────────────────────┐│
│  │            OCR エンジン層                               ││
│  │  ┌──────────┐  ┌───────────┐  ┌──────────────┐      ││
│  │  │ 画像     │  │  PDF      │  │  テキスト    │      ││
│  │  │ パーサー │  │  パーサー │  │  領域検出    │      ││
│  │  └────┬─────┘  └─────┬────┘  └──────┬───────┘      ││
│  │       └───────────────┼──────────────┘               ││
│  │                       ▼                               ││
│  │         Apple Vision Framework                        ││
│  │    (VNRecognizeTextRequest + VNDetectTextRect)        ││
│  └──────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────┘
```

## パフォーマンス

MacBook Pro M2 Pro (macOS 14.5) ベンチマーク:

| シナリオ | 所要時間 | 精度 |
|----------|----------|------|
| 単一画像 (1080p) | ~120ms | 99.2% |
| PDF 1ページ (A4 300dpi) | ~200ms | 98.8% |
| バッチ 10枚 | ~800ms | 99.0% |
| 日英混在 | ~150ms | 97.5% |

## 対応フォーマット

### 画像
PNG, JPEG/JPG, HEIC, TIFF, WebP, BMP, GIF

### ドキュメント
PDF（シングルページ・マルチページ）

### 言語
日本語、中国語（簡体字/繁体字）、英語、韓国語、フランス語、ドイツ語、スペイン語、ポルトガル語、イタリア語、ロシア語など。

## システム要件

| 要件 | バージョン |
|------|-----------|
| macOS | 13.0+（Ventura） |
| Swift | 6.0+ |
| Xcode | 16.0+（ビルド時のみ） |
| アーキテクチャ | Apple Silicon (arm64) または Intel (x86_64) |

## 比較

| 機能 | vision-ocr-mcp | ocrtool-mcp | macos-vision-mcp |
|------|---------------|-------------|------------------|
| 開発言語 | Swift（ネイティブ） | Swift | Node.js + Swift |
| トランスポート | Stdio + HTTP | Stdio のみ | Stdio のみ |
| バックグラウンドサービス | あり（LaunchAgent） | なし | なし |
| Web UI | あり | なし | なし |
| CLI モード | あり | なし | なし |
| PDF 対応 | あり | なし | あり |
| バウンディングボックス | あり | あり | あり |
| バッチ処理 | あり | なし | なし |
| Streamable HTTP | あり | なし | なし |

## 開発

```bash
# テスト実行
swift test

# デバッグビルド
swift build

# リリースビルド
swift build -c release

# UI 付き実行
swift run vision-ocr-mcp serve --transport http --port 8765 --ui
```

## ロードマップ

- [x] Vision Framework コア OCR
- [x] Stdio MCP トランスポート
- [x] Streamable HTTP トランスポート
- [x] CLI スタンドアロンモード
- [x] PDF マルチページ対応
- [x] バックグラウンドサービス（LaunchAgent）
- [x] Web 管理画面
- [ ] テーブル構造認識
- [ ] 手書き認識モード
- [ ] ドキュメントレイアウト分析（ヘッダー、フッター、段組み）
- [ ] ライブテキスト風リアルタイム認識
- [ ] Homebrew formula

## コントリビュート

コントリビュート歓迎！PR 提出前に [コントリビュートガイド](CONTRIBUTING.md) をお読みください。

## ライセンス

[MIT](LICENSE) — 個人・商用プロジェクトで自由に使用可能。

---

<p align="center">
  <sub>Apple Vision Framework で構築 — macOS、iOS、iPadOS のテキスト認識と同じエンジン。</sub>
</p>
