import os

def dump_python_files(directory: str, output_file: str) -> None:
    # Ensure the output directory exists
    os.makedirs(os.path.dirname(output_file), exist_ok=True)

    # Delete the output file if it already exists
    if os.path.exists(output_file):
        os.remove(output_file)

    # Open the output file in write mode
    with open(output_file, 'w', encoding='utf-8') as outfile:
        # Walk through the directory
        for root, dirs, files in os.walk(directory):
            # Exclude the 'vend' directory
            if 'venv' in dirs:
                dirs.remove('venv')  # This prevents os.walk from traversing into 'vend'

            for file in files:
                file_path = os.path.join(root, file)

                # Ignore Python files in the output directory itself
                if file.endswith('.py') and not file_path.startswith(os.path.dirname(output_file)):
                    # Write the file name as a header
                    outfile.write(f"# File: {file_path}\n\n")
                    # Read and write the content of the file
                    with open(file_path, 'r', encoding='utf-8') as infile:
                        outfile.write(infile.read())
                    outfile.write("\n\n")  # Add some space between files

# Specify the directory containing your Python files and the output file
project_directory = '.'  # Current directory
output_directory = os.path.join(os.getcwd(), 'output')
output_file = os.path.join(output_directory, 'cruise_admin_dump.txt')

# Combine the files
dump_python_files(project_directory, output_file)
print(f"All Python files have been combined into {output_file}")
