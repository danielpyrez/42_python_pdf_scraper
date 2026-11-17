import sys
import os
import re
from pypdf import PdfReader


def _get_title(text: str) -> str:
    title: str = ''
    for i in text:
        if i == '\n':
            break
        title += i
    return title


def main() -> None:
    if 2 > len(sys.argv) > 3:
        print("[ERROR] Use: python3 main.py <file.pdf> [target/folder]")
        exit()

    pattern = r"Directory:\s*(.+)\nFiles to Submit:\s*(.+)\nAuthorized:\s*(.+)"

    try:
        pdf_file = sys.argv[1]
        if len(sys.argv) == 3:
            target_folder = sys.argv[2]
        else:
            target_folder = '.'
        sheet = PdfReader(pdf_file)

        title = _get_title(sheet.pages[0].extract_text()).replace(' ', '_')
        base_path = os.path.join(target_folder, title)
        project_path = base_path

        i = 1
        while os.path.exists(project_path):
            project_path = f'{base_path}_{i}'
            i += 1
        os.makedirs(project_path, exist_ok=True)
        os.chdir(project_path)

        for _, page in enumerate(sheet.pages, start=1):
            text = page.extract_text()
            matches = list(re.finditer(pattern, text))
            if not matches:
                continue

            for i, match in enumerate(matches, start=1):
                directories = [d.strip() for d in match.group(1).split(",")\
                               if d.strip()] if match.group(1) else []

                files = [f.strip() for f in match.group(2).split(",")\
                         if f.strip()] if match.group(2) else []

                authorized = [a.strip() for a in match.group(3).split(",")\
                              if a.strip()] if match.group(3) else []

                if not directories or not files:
                    continue

                for directory in directories:
                    os.makedirs(directory)
                for file in files:
                    with open(os.path.join(directories[0], file), "w") as f:
                        f.write(f'"Autorized functions: {authorized}"')

        print(f"Project created succesfully at: {project_path}")

    except Exception as e:
        print(f"[ERROR] {str(e)}")

if __name__ == "__main__":
    main()
