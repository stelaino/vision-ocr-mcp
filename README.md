<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-6.0+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0+">
  <img src="https://img.shields.io/badge/MCP-2025--11--25-blue?style=flat-square" alt="MCP Spec">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT">
  <img src="https://img.shields.io/badge/Offline-100%25-success?style=flat-square" alt="100% Offline">
</p>

<h1 align="center">Vision OCR MCP</h1>

<p align="center">
  <strong>macOS Native Offline OCR — Model Context Protocol Server</strong>
</p>

<p align="center">
  High-performance text extraction powered by Apple Vision Framework.<br>
  Supports Streamable HTTP and Stdio transports. No cloud. No API keys. No data leaves your Mac.
</p>

<p align="center">
  <a href="README.md">English</a> •
  <a href="README.zh.md">简体中文</a> •
  <a href="README.ja.md">日本語</a>
</p>

---

## Highlights

- **Native Performance** — Built with Swift and Apple Vision Framework, the same engine behind Live Text in Photos.app
- **Dual Transport** — Streamable HTTP for remote/network integration + Stdio for local IDE integration
- **Background Service** — Install as macOS LaunchAgent, auto-start at login, no terminal needed
- **Web UI Dashboard** — Built-in management interface for testing, monitoring, and configuration
- **CLI First** — Use as a standalone command-line OCR tool without any MCP client
- **100% Offline** — Zero network dependency, all processing happens on-device
- **Multi-format** — Images (PNG, JPEG, HEIC, TIFF, WebP) and multi-page PDFs
- **Structured Output** — Plain text, JSON with bounding boxes, or Markdown
- **Multi-language** — Chinese, English, Japanese, Korean, and 15+ languages via Vision Framework
- **Apple Silicon Optimized** — Native ARM64 binary with Neural Engine acceleration

## Quick Start

### Install via Homebrew (Recommended)

```bash
brew install stelaino/tap/vision-ocr-mcp
```

### Build from Source

```bash
git clone https://github.com/stelaino/vision-ocr-mcp.git
cd vision-ocr-mcp
swift build -c release
cp .build/release/vision-ocr-mcp /usr/local/bin/
```

### Run as MCP Server

```bash
# Stdio transport (for Claude Desktop, Cursor, Windsurf, etc.)
vision-ocr-mcp serve --transport stdio

# Streamable HTTP transport (for remote/network clients)
vision-ocr-mcp serve --transport http --port 8765

# HTTP with Web UI enabled
vision-ocr-mcp serve --transport http --port 8765 --ui
```

### Background Service (Auto-start)

```bash
# Install as macOS LaunchAgent (auto-start at login, runs in background)
vision-ocr-mcp service install --port 8765

# Manage the background service
vision-ocr-mcp service start
vision-ocr-mcp service stop
vision-ocr-mcp service restart
vision-ocr-mcp service status

# Uninstall the background service
vision-ocr-mcp service uninstall
```

Once installed, the server runs as a global background service — no terminal window needed, survives logout/reboot, and is accessible at `http://localhost:8765/mcp`.

### Run as CLI Tool

```bash
# Extract text from an image
vision-ocr-mcp ocr ~/Desktop/screenshot.png

# Extract with structured output (JSON with bounding boxes)
vision-ocr-mcp ocr ~/Documents/scan.pdf --format json

# Specify language and page range
vision-ocr-mcp ocr invoice.pdf --lang zh-Hans+en --pages 1-3

# Output to file
vision-ocr-mcp ocr image.png --output result.txt
vision-ocr-mcp ocr image.png --output result.json --format json

# Batch process a directory
vision-ocr-mcp ocr ./scans/ --output-dir ./results/ --format markdown
```

## Web UI Dashboard

Access the built-in management interface at `http://localhost:8765/ui` when running in HTTP mode.

**Features:**
- Live OCR testing — drag & drop images for instant recognition
- Request history & statistics
- Server configuration management
- Performance monitoring (latency, throughput)
- Multi-language switching (EN / 中文 / 日本語)

## MCP Client Configuration

### Claude Desktop / Cursor / Windsurf

Add to your MCP configuration:

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

### Streamable HTTP (Remote)

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

Start server with authentication:

```bash
vision-ocr-mcp serve --transport http --port 8765 --api-key "your-secret-key"
```

## Available Tools

| Tool | Description | Input |
|------|-------------|-------|
| `ocr_extract_text` | Extract text from images or PDFs | `file_path`, `base64`, or `url` |
| `analyze_document` | Structured document analysis with layout | `file_path` + options |
| `analyze_document_structure` | Smart structure (tables/paragraphs/lists) | `file_path` (macOS 26+) |
| `detect_text_regions` | Detect text regions with bounding boxes | `file_path` |
| `detect_barcodes` | Detect QR codes and barcodes | `file_path` |
| `detect_document_bounds` | Detect document edges + auto-crop | `file_path` |
| `ocr_screen_region` | Capture & OCR a screen region | `x`, `y`, `width`, `height` |
| `ocr_clipboard` | OCR image from system clipboard | (none) |
| `watch_folder` | Monitor folder for auto-OCR | `folder_path` |
| `batch_ocr` | Process multiple files in batch | `file_paths[]` |

### Tool Parameters

#### `ocr_extract_text`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | * | Local file path (supports `~` expansion) |
| `base64` | string | * | Base64-encoded image data |
| `url` | string | * | Image URL (auto-download) |
| `languages` | string | No | Recognition languages, e.g. `"zh-Hans+en"` |
| `format` | string | No | Output format: `text` \| `json` \| `markdown` |
| `pages` | string | No | Page range for PDFs, e.g. `"1-5"` |

*One of `file_path`, `base64`, or `url` is required.

#### `analyze_document`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | Yes | Path to document file |
| `include_boxes` | bool | No | Include bounding box coordinates (default: true) |
| `include_confidence` | bool | No | Include confidence scores (default: true) |
| `reading_order` | bool | No | Sort by reading order (default: true) |

### Example Response

```json
{
  "text": "Hello World\nThis is a sample document.",
  "pages": [
    {
      "page": 1,
      "blocks": [
        {
          "text": "Hello World",
          "confidence": 0.98,
          "boundingBox": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.04 }
        }
      ]
    }
  ],
  "metadata": {
    "totalPages": 1,
    "languages": ["en"],
    "processingTime": "0.23s"
  }
}
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   CLI Interface                            │
│              (ArgumentParser)                              │
├──────────────┬──────────────────────────────────┬────────┤
│              │                                   │        │
│  ┌───────────▼──────────┐  ┌────────────────────▼─────┐ │
│  │   Stdio Transport    │  │  HTTP Transport          │ │
│  │   (JSON-RPC stdin)   │  │  (Streamable HTTP)       │ │
│  └───────────┬──────────┘  │  + Web UI (Static Files) │ │
│              │              └────────────┬─────────────┘ │
│  ┌───────────▼──────────────────────────▼───────────────┐│
│  │              MCP Server Core                          ││
│  │        (Tool Registry + Handler)                      ││
│  └───────────────────────┬──────────────────────────────┘│
│                          │                                │
│  ┌───────────────────────▼──────────────────────────────┐│
│  │            OCR Engine Layer                            ││
│  │  ┌──────────┐  ┌───────────┐  ┌──────────────┐      ││
│  │  │ Image    │  │  PDF      │  │  Text Region │      ││
│  │  │ Parser   │  │  Parser   │  │  Detector    │      ││
│  │  └────┬─────┘  └─────┬────┘  └──────┬───────┘      ││
│  │       └───────────────┼──────────────┘               ││
│  │                       ▼                               ││
│  │         Apple Vision Framework                        ││
│  │    (VNRecognizeTextRequest + VNDetectTextRect)        ││
│  └──────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────┘
```

## Performance

Benchmarked on MacBook Pro M2 Pro (macOS 14.5):

| Scenario | Time | Accuracy |
|----------|------|----------|
| Single image (1080p) | ~120ms | 99.2% |
| PDF page (A4 300dpi) | ~200ms | 98.8% |
| Batch 10 images | ~800ms | 99.0% |
| Chinese + English mixed | ~150ms | 97.5% |

## Supported Formats

### Images
PNG, JPEG/JPG, HEIC, TIFF, WebP, BMP, GIF

### Documents
PDF (single and multi-page)

### Languages
Chinese (Simplified/Traditional), English, Japanese, Korean, French, German, Spanish, Portuguese, Italian, Russian, and more.

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 13.0+ (Ventura) |
| Swift | 6.0+ |
| Xcode | 16.0+ (build only) |
| Architecture | Apple Silicon (arm64) or Intel (x86_64) |

## Comparison

| Feature | vision-ocr-mcp | ocrtool-mcp | macos-vision-mcp |
|---------|---------------|-------------|------------------|
| Language | Swift (native) | Swift | Node.js + Swift |
| Transport | Stdio + HTTP | Stdio only | Stdio only |
| Background service | Yes (LaunchAgent) | No | No |
| Web UI | Yes | No | No |
| CLI mode | Yes | No | No |
| PDF support | Yes | No | Yes |
| Bounding boxes | Yes | Yes | Yes |
| Batch processing | Yes | No | No |
| Streamable HTTP | Yes | No | No |

## Development

```bash
# Run tests
swift test

# Build debug
swift build

# Build release
swift build -c release

# Run with UI
swift run vision-ocr-mcp serve --transport http --port 8765 --ui
```

## Roadmap

- [x] Core OCR with Vision Framework
- [x] Stdio MCP transport
- [x] Streamable HTTP transport
- [x] CLI standalone mode
- [x] PDF multi-page support
- [x] Background service (LaunchAgent)
- [x] Web UI Dashboard
- [ ] Table structure recognition
- [ ] Handwriting recognition mode
- [ ] Document layout analysis (headers, footers, columns)
- [ ] Live Text-style real-time recognition
- [ ] Homebrew formula

## Contributing

Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) before submitting a PR.

## License

[MIT](LICENSE) — Use freely in personal and commercial projects.

---

<p align="center">
  <sub>Built with Apple Vision Framework — the same engine powering Live Text across macOS, iOS, and iPadOS.</sub>
</p>
