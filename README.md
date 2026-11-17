# 42 Python Subject Scraper

A Python CLI tool that automates folder and file scaffolding for **42 Python projects** directly from their PDF subject.

## What does this script do?

* **Generates the root folder:** Extracts the project title from the first page of the PDF and creates a clean root directory (appending a numeric suffix if the folder already exists to prevent overwriting).
* **Scans the entire subject:** Parses every page looking for the standard 42 Python subject blocks (`Directory`, `Files to Submit`, and `Authorized`).
* **Creates exercises and files:** Automatically creates each required subdirectory along with its corresponding files, writing the list of authorized functions inside each file.

> **Note:** This script is specifically designed for the formatting of 42 Python project subjects.

## Requirements

* Python 3.10 or higher
* Dependency:
  ```bash
  pip install pypdf
  ```

## Usage

```bash
python3 main.py <file.pdf> <target_folder>
```

### Example

```bash
python3 main.py ./en.subject.pdf ./projects
```
