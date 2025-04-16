# PowerShell script to analyze Python type hints and UML for lambda_admin_portal

$ProjectPath = "./admin"
Write-Host "`nScanning Python files in: $ProjectPath"

# 1. Class attributes without type hints
Write-Host "`n[1] Class attributes without type hints..."
Select-String -Path "$ProjectPath\*.py" -Pattern "self\.\w+\s*=" | ForEach-Object { $_.Line }

# 2. Methods missing return type hints
Write-Host "`n[2] Methods missing return type hints..."
Select-String -Path "$ProjectPath\*.py" -Pattern 'def .+\(.*\):' | Where-Object { $_ -notmatch "->" } | ForEach-Object { $_.Line }

# 3. Class definitions and member references
Write-Host "`n[3] Class definitions and references..."
Select-String -Path "$ProjectPath\*.py" -Pattern "class \w+" | ForEach-Object { $_.Line }
Select-String -Path "$ProjectPath\*.py" -Pattern "self\.\w+" | ForEach-Object { $_.Line }

# 4. Run mypy for type checking
Write-Host "`n[4] Running mypy..."
mypy "$ProjectPath" --disallow-untyped-defs --disallow-untyped-calls --ignore-missing-imports

# 5. Run ruff for linting
Write-Host "`n[5] Running ruff..."
ruff check "$ProjectPath"

# 6. Find unused code with vulture
Write-Host "`n[6] Running vulture for unused code..."
python -m vulture "$ProjectPath"

# 7. Generate UML diagram with pyreverse (if available)
if (Get-Command pyreverse -ErrorAction SilentlyContinue) {
    Write-Host "`n[7] Generating UML diagram..."
    pyreverse -o png -p lambda_admin "$ProjectPath"
    Write-Host "UML Diagram saved as classes.png"
} else {
    Write-Host "`n[7] Skipping UML generation - 'pyreverse' not found in PATH."
}

Write-Host "`nAnalysis complete!"
