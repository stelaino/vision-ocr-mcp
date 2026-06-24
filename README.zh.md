<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-6.0+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0+">
  <img src="https://img.shields.io/badge/MCP-2025--11--25-blue?style=flat-square" alt="MCP Spec">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT">
  <img src="https://img.shields.io/badge/离线-100%25-success?style=flat-square" alt="100% 离线">
</p>

<h1 align="center">Vision OCR MCP</h1>

<p align="center">
  <strong>macOS 原生离线 OCR — Model Context Protocol 服务器</strong>
</p>

<p align="center">
  基于 Apple Vision Framework 的高性能文字提取。<br>
  支持 Streamable HTTP 和 Stdio 双传输模式。无需云端、无需密钥、数据不离开你的 Mac。
</p>

<p align="center">
  <a href="README.md">English</a> •
  <a href="README.zh.md">简体中文</a> •
  <a href="README.ja.md">日本語</a>
</p>

---

## 特性亮点

- **原生性能** — 使用 Swift 和 Apple Vision Framework 构建，与 Photos.app 中的实况文本同款引擎
- **双传输模式** — Streamable HTTP 支持远程/网络集成 + Stdio 支持本地 IDE 集成
- **后台服务** — 安装为 macOS LaunchAgent，登录时自动启动，无需终端窗口
- **Web 管理界面** — 内置管理面板，支持在线测试、监控和配置
- **CLI 优先** — 无需 MCP 客户端即可作为独立命令行 OCR 工具使用
- **100% 离线** — 零网络依赖，所有处理都在本机完成
- **多格式支持** — 图片 (PNG, JPEG, HEIC, TIFF, WebP) 和多页 PDF
- **结构化输出** — 纯文本、带边界框的 JSON、或 Markdown 格式
- **多语言识别** — 中文、英文、日文、韩文等 15+ 种语言
- **Apple Silicon 优化** — 原生 ARM64 二进制，Neural Engine 加速

## 快速开始

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/stelaino/vision-ocr-mcp/main/install.sh | bash
```

### 通过 Homebrew 安装

```bash
brew install stelaino/tap/vision-ocr-mcp
```

### 从源码构建

```bash
git clone https://github.com/stelaino/vision-ocr-mcp.git
cd vision-ocr-mcp
make install   # 自动构建并安装到 /usr/local/bin
```

### 作为 MCP 服务器运行

```bash
# Stdio 传输（适用于 Claude Desktop、Cursor、Windsurf 等）
vision-ocr-mcp serve --transport stdio

# Streamable HTTP 传输（适用于远程/网络客户端）
vision-ocr-mcp serve --transport http --port 8765

# HTTP 模式 + Web 管理界面
vision-ocr-mcp serve --transport http --port 8765 --ui
```

### 后台服务（开机自启）

```bash
# 安装为 macOS LaunchAgent（登录时自动启动，后台运行）
vision-ocr-mcp service install --port 8765

# 管理后台服务
vision-ocr-mcp service start
vision-ocr-mcp service stop
vision-ocr-mcp service restart
vision-ocr-mcp service status

# 卸载后台服务
vision-ocr-mcp service uninstall
```

安装后，服务器将作为全局后台服务运行 — 无需终端窗口，重启后自动恢复，通过 `http://localhost:8765/mcp` 访问。

### 作为 CLI 工具使用

```bash
# 从图片提取文字
vision-ocr-mcp ocr ~/Desktop/screenshot.png

# 结构化输出（带边界框的 JSON）
vision-ocr-mcp ocr ~/Documents/scan.pdf --format json

# 指定语言和页码范围
vision-ocr-mcp ocr invoice.pdf --lang zh-Hans+en --pages 1-3

# 输出到文件
vision-ocr-mcp ocr image.png --output result.txt
vision-ocr-mcp ocr image.png --output result.json --format json

# 批量处理整个目录
vision-ocr-mcp ocr ./scans/ --output-dir ./results/ --format markdown
```

## Web 管理界面

在 HTTP 模式运行时，访问 `http://localhost:8765/ui` 即可使用内置管理界面。

**功能：**
- 在线 OCR 测试 — 拖拽图片即时识别
- 请求历史与统计
- 服务器配置管理
- 性能监控（延迟、吞吐量）
- 多语言界面切换（EN / 中文 / 日本語）

## MCP 客户端配置

### Claude Desktop / Cursor / Windsurf

在 MCP 配置中添加：

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

### Streamable HTTP（远程）

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

设置密钥认证（三种方式，按优先级）：

```bash
# 方式 1: CLI 参数
vision-ocr-mcp serve --transport http --port 8765 --api-key "your-secret-key"

# 方式 2: 环境变量
export VISION_OCR_MCP_API_KEY="your-secret-key"
vision-ocr-mcp serve --transport http --port 8765

# 方式 3: 服务安装时指定
vision-ocr-mcp service install --port 8765 --api-key "your-secret-key" --ui
```

## 可用工具

| 工具 | 描述 | 输入 |
|------|------|------|
| `ocr_extract_text` | 从图片或 PDF 提取文字 | `file_path`、`base64` 或 `url` |
| `analyze_document` | 结构化文档分析（含布局） | `file_path` + 选项 |
| `detect_text_regions` | 检测文字区域及边界框 | `file_path` |
| `detect_barcodes` | 检测二维码和条形码 | `file_path` |
| `detect_document_bounds` | 文档边界检测 + 自动裁剪 | `file_path` |
| `ocr_screen_region` | 截取屏幕区域并 OCR | `x`、`y`、`width`、`height` |
| `ocr_clipboard` | 从系统剪贴板 OCR 图片 | （无需参数） |
| `watch_folder` | 监控文件夹自动 OCR | `folder_path` |
| `batch_ocr` | 批量处理多个文件 | `file_paths[]` |

### 工具参数

#### `ocr_extract_text`

| 参数 | 类型 | 必填 | 描述 |
|------|------|------|------|
| `file_path` | string | * | 本地文件路径（支持 `~` 展开） |
| `base64` | string | * | Base64 编码的图片数据 |
| `url` | string | * | 图片 URL（自动下载） |
| `languages` | string | 否 | 识别语言，如 `"zh-Hans+en"` |
| `format` | string | 否 | 输出格式：`text` \| `json` \| `markdown` |
| `pages` | string | 否 | PDF 页码范围，如 `"1-5"` |

*`file_path`、`base64`、`url` 三者必填其一。

### 响应示例

```json
{
  "text": "你好世界\n这是一份示例文档。",
  "pages": [
    {
      "page": 1,
      "blocks": [
        {
          "text": "你好世界",
          "confidence": 0.98,
          "boundingBox": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.04 }
        }
      ]
    }
  ],
  "metadata": {
    "totalPages": 1,
    "languages": ["zh-Hans"],
    "processingTime": "0.23s"
  }
}
```

## 架构

```
┌──────────────────────────────────────────────────────────┐
│                   CLI 接口层                               │
│              (ArgumentParser)                              │
├──────────────┬──────────────────────────────────┬────────┤
│              │                                   │        │
│  ┌───────────▼──────────┐  ┌────────────────────▼─────┐ │
│  │   Stdio 传输         │  │  HTTP 传输               │ │
│  │   (JSON-RPC stdin)   │  │  (Streamable HTTP)       │ │
│  └───────────┬──────────┘  │  + Web UI (静态文件)     │ │
│              │              └────────────┬─────────────┘ │
│  ┌───────────▼──────────────────────────▼───────────────┐│
│  │              MCP 服务器核心                            ││
│  │        (工具注册 + 处理器)                             ││
│  └───────────────────────┬──────────────────────────────┘│
│                          │                                │
│  ┌───────────────────────▼──────────────────────────────┐│
│  │            OCR 引擎层                                  ││
│  │  ┌──────────┐  ┌───────────┐  ┌──────────────┐      ││
│  │  │ 图片解析 │  │  PDF 解析 │  │  文字区域    │      ││
│  │  │ Parser   │  │  Parser   │  │  检测器      │      ││
│  │  └────┬─────┘  └─────┬────┘  └──────┬───────┘      ││
│  │       └───────────────┼──────────────┘               ││
│  │                       ▼                               ││
│  │         Apple Vision Framework                        ││
│  │    (VNRecognizeTextRequest + VNDetectTextRect)        ││
│  └──────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────┘
```

## 性能

MacBook Pro M2 Pro (macOS 14.5) 基准测试:

| 场景 | 耗时 | 准确率 |
|------|------|--------|
| 单张图片 (1080p) | ~120ms | 99.2% |
| PDF 单页 (A4 300dpi) | ~200ms | 98.8% |
| 批量 10 张图片 | ~800ms | 99.0% |
| 中英混排 | ~150ms | 97.5% |

## 支持格式

### 图片
PNG, JPEG/JPG, HEIC, TIFF, WebP, BMP, GIF

### 文档
PDF（单页和多页）

### 语言
简体中文、繁体中文、英文、日文、韩文、法文、德文、西班牙文、葡萄牙文、意大利文、俄文等。

## 系统要求

| 要求 | 版本 |
|------|------|
| macOS | 12.0+（Monterey） |
| Swift | 6.0+ |
| Xcode | 16.0+（仅构建时需要） |
| 架构 | Apple Silicon (arm64) 或 Intel (x86_64) |

## 竞品对比

| 特性 | vision-ocr-mcp | ocrtool-mcp | macos-vision-mcp |
|------|---------------|-------------|------------------|
| 开发语言 | Swift（原生） | Swift | Node.js + Swift |
| 传输方式 | Stdio + HTTP | 仅 Stdio | 仅 Stdio |
| 后台服务 | 有（LaunchAgent） | 无 | 无 |
| Web 界面 | 有 | 无 | 无 |
| CLI 模式 | 有 | 无 | 无 |
| PDF 支持 | 有 | 无 | 有 |
| 边界框 | 有 | 有 | 有 |
| 批量处理 | 有 | 无 | 无 |
| Streamable HTTP | 有 | 无 | 无 |

## 开发

```bash
# 运行测试
swift test

# 调试构建
swift build

# 发布构建
swift build -c release

# 带 UI 运行
swift run vision-ocr-mcp serve --transport http --port 8765 --ui
```

## 路线图

- [x] Vision Framework 核心 OCR
- [x] Stdio MCP 传输
- [x] Streamable HTTP 传输
- [x] CLI 独立模式
- [x] PDF 多页支持
- [x] 后台服务（LaunchAgent）
- [x] Web 管理界面
- [x] Bearer Token 认证
- [x] CORS 跨域支持
- [x] 速率限制
- [x] 条形码/二维码检测
- [x] 文档边界检测
- [x] 屏幕区域 OCR
- [x] 剪贴板 OCR
- [x] 批量处理
- [x] 文件夹监控自动 OCR
- [x] 一键安装脚本
- [x] GitHub Actions 自动发布
- [ ] 表格结构识别
- [ ] 手写体识别模式
- [ ] 文档版面分析（页眉、页脚、分栏）
- [ ] 类实况文本的实时识别
- [ ] Homebrew formula 发布

## 贡献

欢迎贡献！提交 PR 前请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE) — 可自由用于个人和商业项目。

---

<p align="center">
  <sub>基于 Apple Vision Framework 构建 — 与 macOS、iOS、iPadOS 中实况文本同款引擎。</sub>
</p>
