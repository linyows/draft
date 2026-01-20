<p align="right"><a href="https://github.com/linyows/draft/blob/main/README.md">English</a> | 日本語</p>

<br><br><br><br><br><br>

<p align="center">
  <img alt="draft" src="https://github.com/linyows/draft/blob/main/misc/draft.svg?raw=true" width="200">
  <br><br>
  Markdown テンプレートジェネレーター
</p>

<br><br><br><br>

<p align="center">
  <a href="https://github.com/linyows/draft/actions/workflows/test.yml">
    <img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/linyows/draft/test.yml?branch=main&style=for-the-badge&labelColor=666666">
  </a>
  <a href="https://github.com/linyows/draft/releases">
    <img src="http://img.shields.io/github/release/linyows/draft.svg?style=for-the-badge&labelColor=666666&color=DDDDDD" alt="GitHub Release">
  </a>
</p>

## 特徴

- テンプレートからMarkdownドキュメントを生成
- ドキュメントIDの自動採番
- ドキュメント一覧付きのインデックスファイル生成
- ADRとDesign Docのテンプレートを内蔵
- カスタムテンプレートのサポート

## インストール

macOSまたはLinuxでHomebrewを使用してインストール:

```bash
$ brew tap linyows/draft
$ brew install linyows/draft/draft
```

### ソースからビルド

Zig 0.15.2以降が必要です。

```bash
$ git clone https://github.com/linyows/draft.git
$ cd draft
$ zig build --release=fast
```

バイナリは `./zig-out/bin/draft` に生成されます。

## 使い方

### 初期化

デフォルトの設定とテンプレートを含む `.draft` ディレクトリを作成:

```bash
draft init
```

以下が作成されます:
```
.draft/
├── config.json
└── templates/
    ├── adr.md
    ├── adr-index.md
    ├── design.md
    └── design-index.md
```

### ドキュメントの生成

```bash
draft <template> "<title>"
```

例:
```bash
draft adr "Authentication System Design"
draft design "API Design"
```

### インデックスの生成

```bash
draft <template> index
```

例:

```bash
draft adr index
```

出力ディレクトリに全ドキュメントの一覧表を含む `README.md` を生成します。

## 設定

`.draft/config.json`:

```json
{
  "templates_dir": ".draft/templates",
  "output_dir": "docs",
  "filename_format": "{{@id}}-{{@title}}.md"
}
```

| キー | 説明 | デフォルト |
|-----|-------------|---------|
| `templates_dir` | テンプレートファイルのディレクトリ | `.draft/templates` |
| `output_dir` | 生成ファイルの出力ディレクトリ | `docs` |
| `filename_format` | 出力ファイル名のパターン | `{{@title}}.md` |
| `templates` | テンプレートごとの設定オーバーライド | `null` |

### テンプレートごとの設定

特定のテンプレートに対して `output_dir` と `filename_format` をオーバーライドできます:

```json
{
  "templates_dir": ".draft/templates",
  "output_dir": "docs",
  "filename_format": "{{@title}}.md",
  "templates": {
    "adr": {
      "output_dir": "docs/adrs",
      "filename_format": "{{@id{4}}}-{{@title}}.md"
    },
    "design": {
      "output_dir": "docs/design",
      "filename_format": "{{@date}}-{{@title}}.md"
    }
  }
}
```

この設定では:
- `draft adr "My ADR"` → `docs/adrs/0001-My ADR.md` を作成
- `draft design "My Design"` → `docs/design/2024-01-01-My Design.md` を作成
- 他のテンプレートはグローバルの `output_dir` と `filename_format` を使用

## テンプレート変数

| 変数 | 説明 |
|----------|-------------|
| `{{@title}}` | 引数で指定したタイトル |
| `{{@today}}` | 今日の日付 (YYYY-MM-DD) |
| `{{@date}}` | 今日の日付 (YYYY-MM-DD) |
| `{{@name}}` | 現在のユーザー名 |
| `{{@id}}` | 自動採番ID (001, 002, ...) |
| `{{@id{N}}}` | N桁の自動採番ID (例: `{{@id{4}}}` -> 0001) |

## インデックス変数

| 変数 | 説明 |
|----------|-------------|
| `{{@index}}` | ドキュメント一覧表 (デフォルト列: Title, Date, Author) |
| `{{@index{@id\|@title\|@status}}}` | 指定した列でカスタム形式の表 |
| `{{@index{@id\|@title,asc:@id}}}` | ソート指定付きのカスタム形式 |
| `{{@index{@id\|@title\|@date,desc:@date}}}` | 日付降順でソート |

利用可能な列: `@id`, `@title`, `@date`, `@name`, `@status`

### インデックスのソート

列指定の後に `,asc:@field` または `,desc:@field` 構文でソート順を指定できます。

**デフォルトのソート動作** (ソート指定がない場合):
- ドキュメントに `@id` がある場合: `@id` の昇順
- ドキュメントに `@date` がある場合: `@date` の降順
- それ以外: ファイル更新日時の降順

**例:**
```markdown
{{@index{@id|@title|@author,asc:@id}}}    <!-- Sort by ID ascending -->
{{@index{@title|@date,desc:@date}}}       <!-- Sort by date descending -->
```

## カスタムテンプレート

`.draft/templates/` に独自のテンプレートを作成:

**`.draft/templates/rfc.md`**:
```markdown
# {{@title}}

- ID: {{@id{4}}}
- Date: {{@date}}
- Author: {{@name}}
- Status: Draft

## Summary

## Motivation

## Detailed Design

## Alternatives

## Unresolved Questions
```

**`.draft/templates/rfc-index.md`**:
```markdown
# RFC Index

{{@index{@id|@title|@status}}}
```

使用方法:
```bash
draft rfc "My RFC Title"
draft rfc index
```

## 開発

```bash
# テスト実行
zig build test

# ビルド
zig build

# 実行
zig build run -- help
```

## Author

[linyows](https://github.com/linyows)
