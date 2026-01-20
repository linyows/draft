<p align="right">English | <a href="https://github.com/linyows/draft/blob/main/README.ja.md">日本語</a></p>

<br><br><br><br><br><br>

<p align="center">
  <img alt="draft" src="https://github.com/linyows/draft/blob/main/misc/draft.svg?raw=true" width="200">
  <br><br>
  Markdown template generator
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

## Features

- Generate Markdown documents from templates
- Auto-increment document IDs
- Generate index files with document listings
- Built-in ADR and Design Doc templates
- Custom templates support

## Installation

Install via Homebrew on macOS or Linux:

```bash
$ brew tap linyows/draft
$ brew install linyows/draft/draft
```

### Build from source

Requires Zig 0.15.2 or later.

```bash
$ git clone https://github.com/linyows/draft.git
$ cd draft
$ zig build --release=fast
```

The binary will be available at `./zig-out/bin/draft`.

## Usage

### Initialize

Create `.draft` directory with default config and templates:

```bash
draft init
```

This creates:
```
.draft/
├── config.json
└── templates/
    ├── adr.md
    ├── adr-index.md
    ├── design.md
    └── design-index.md
```

### Generate a document

```bash
draft <template> "<title>"
```

Examples:
```bash
draft adr "Authentication System Design"
draft design "API Design"
```

### Generate index

```bash
draft <template> index
```

Example:

```bash
draft adr index
```

This generates `README.md` in the output directory with a table of all documents.

## Configuration

`.draft/config.json`:

```json
{
  "templates_dir": ".draft/templates",
  "output_dir": "docs",
  "filename_format": "{{@id}}-{{@title}}.md"
}
```

| Key | Description | Default |
|-----|-------------|---------|
| `templates_dir` | Directory containing template files | `.draft/templates` |
| `output_dir` | Directory for generated files | `docs` |
| `filename_format` | Output filename pattern | `{{@title}}.md` |
| `templates` | Per-template configuration overrides | `null` |

### Per-Template Configuration

You can override `output_dir` and `filename_format` for specific templates:

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

With this configuration:
- `draft adr "My ADR"` → creates `docs/adrs/0001-My ADR.md`
- `draft design "My Design"` → creates `docs/design/2024-01-01-My Design.md`
- Other templates use the global `output_dir` and `filename_format`

## Template Variables

| Variable | Description |
|----------|-------------|
| `{{@title}}` | Title specified as argument |
| `{{@today}}` | Today's date (YYYY-MM-DD) |
| `{{@date}}` | Today's date (YYYY-MM-DD) |
| `{{@name}}` | Current user name |
| `{{@id}}` | Auto-increment ID (001, 002, ...) |
| `{{@id{N}}}` | Auto-increment ID with N digits (e.g., `{{@id{4}}}` -> 0001) |

## Index Variables

| Variable | Description |
|----------|-------------|
| `{{@index}}` | Document list table (default columns: Title, Date, Author) |
| `{{@index{@id\|@title\|@status}}}` | Custom format table with specified columns |
| `{{@index{@id\|@title,asc:@id}}}` | Custom format with sort specification |
| `{{@index{@id\|@title\|@date,desc:@date}}}` | Sort by date descending |

Available columns: `@id`, `@title`, `@date`, `@name`, `@status`

### Index Sorting

You can specify a sort order using the `,asc:@field` or `,desc:@field` syntax after the column specification.

**Default sort behavior** (when no sort is specified):
- If documents have `@id`: sort by `@id` ascending
- Else if documents have `@date`: sort by `@date` descending
- Else: sort by file modification time descending

**Examples:**
```markdown
{{@index{@id|@title|@author,asc:@id}}}    <!-- Sort by ID ascending -->
{{@index{@title|@date,desc:@date}}}       <!-- Sort by date descending -->
```

## Custom Templates

Create your own templates in `.draft/templates/`:

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

Then use:
```bash
draft rfc "My RFC Title"
draft rfc index
```

## Development

```bash
# Run tests
zig build test

# Build
zig build

# Run
zig build run -- help
```

## Author

[linyows](https://github.com/linyows)
