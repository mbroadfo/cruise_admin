import os
from typing import Optional

def dump_project_files(
    directory: str,
    output_file: str,
    include_extensions: Optional[list[str]] = None,
    include_filenames: Optional[list[str]] = None,
    exclude_dirs: Optional[list[str]] = None
) -> None:
    os.makedirs(os.path.dirname(output_file), exist_ok=True)

    if os.path.exists(output_file):
        os.remove(output_file)

    if include_extensions is None:
        include_extensions = ['.py', '.json', '.js', '.ts', '.jsx', '.tsx', '.html', '.css', '.sh']
    if include_filenames is None:
        include_filenames = ['Dockerfile', 'Makefile']
    if exclude_dirs is None:
        exclude_dirs = ['venv', '.mypy_cache', os.path.join('infra', 'build')]

    with open(output_file, 'w', encoding='utf-8') as outfile:
        for root, dirs, files in os.walk(directory):
            dirs[:] = [d for d in dirs if os.path.join(root, d) not in [os.path.join(directory, x) for x in exclude_dirs]]

            for file in files:
                file_path = os.path.join(root, file)
                ext = os.path.splitext(file)[1]

                if (
                    (ext in include_extensions or file in include_filenames)
                    and not file_path.startswith(os.path.dirname(output_file))
                ):
                    outfile.write(f"# File: {file_path}\n\n")
                    try:
                        with open(file_path, 'r', encoding='utf-8') as infile:
                            outfile.write(infile.read())
                    except Exception as e:
                        outfile.write(f"# Could not read file: {e}")
                    outfile.write("\n\n")

# Usage
project_directory = '.'
output_directory = os.path.join(os.getcwd(), 'output')
output_file = os.path.join(output_directory, 'cruise_admin_dump.txt')
dump_project_files(project_directory, output_file)
print(f"All selected project files have been combined into {output_file}")
