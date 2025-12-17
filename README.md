*English | [中文](README_zh.md)* 

# MarkdownDisplayView

A powerful iOS Markdown rendering component built on TextKit 2, providing smooth rendering performance and rich customization options. It also supports streaming rendering of Markdown content.

## Demo Effects

### Normal Rendering
![Normal Rendering](./Effects/normal.gif)

### Streaming Rendering
![Streaming Rendering](./Effects/streaming.gif)

## ✨ Features
- 🚀 **High-Performance Rendering** — Based on TextKit 2, supports asynchronous rendering, incremental updates, streaming rendering, etc. Full loading and rendering of sample Markdown content takes less than 200ms (compared to over 400ms for the MarkdownView library with the same content).
- 🎨 **Full Markdown Support** — Headings, lists, tables, code blocks, blockquotes, images, and more.
- 🌈 **Syntax Highlighting** — Supports syntax highlighting for 20+ programming languages (Swift, Python, JavaScript, etc.).
- 📑 **Automatic Table of Contents** — Automatically extracts headings to generate an interactive TOC.
- 🎯 **Highly Customizable** — Comprehensive configuration for fonts, colors, spacing, etc.
- 🔗 **Event Callbacks** — Link taps, image taps, TOC navigation.
- 📱 **Native iOS** — Built with UIKit and TextKit 2 for excellent performance.
- 🌓 **Dark Mode** — Built-in light and dark theme configurations.

## 📋 Requirements
- iOS 15.0+ (due to TextKit 2 requirement)
- Swift 5.9+
- Xcode 16.0+

## 📦 Installation
### Swift Package Manager
#### Method 1: Add via Xcode
1. Open your project in Xcode.
2. Choose `File` → `Add Package Dependencies...`
3. Enter the repository URL: `https://github.com/yourusername/MarkdownDisplayView.git`
4. Select the version and click `Add Package`.

#### Method 2: In Package.swift
Add the dependency in `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/yourusername/MarkdownDisplayView.git", from: "1.0.0")
]
