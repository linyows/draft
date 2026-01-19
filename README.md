# Draft

A Markdown template generator written in Zig.

## Features

- Generate Markdown documents from templates
- Auto-increment document IDs
- Generate index files with document listings
- Built-in ADR and Design Doc templates
- Custom templates support

## Installation

### Build from source

Requires Zig 0.15.2 or later.

```bash
git clone https://github.com/linyows/draft.git
cd draft
zig build --release=fast
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

Available columns: `@id`, `@title`, `@date`, `@name`, `@status`

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
