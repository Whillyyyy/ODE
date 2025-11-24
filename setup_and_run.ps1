<#
setup_and_run.ps1
Automates development setup for the URS Capstone project on Windows.
What it does:
 - Checks for required binaries (mysql, php, dotnet)
 - Prompts for MySQL root password and imports db\schema.sql
 - Sets environment variables for the current session
 - Runs `php create_admin.php` to create an admin and prints the API key
 - Runs `php seed_sample.php` to insert sample data
 - Starts the PHP built-in server for the `api/` folder (background)

Usage (PowerShell):
  - Open PowerShell as your normal user (or Admin if needed for mysql)
  - Allow script execution for this session: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force`
  - Run: `cd "C:\Users\ADMIN PC\Desktop\Capstone"; .\setup_and_run.ps1`
#>

# Helper: check command exists
function Check-Cmd($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

Write-Host "Starting URS Capstone setup..." -ForegroundColor Cyan

# 1) Check prerequisites
$missing = @()
if (-not (Check-Cmd php)) { $missing += 'php' }
if (-not (Check-Cmd mysql)) { $missing += 'mysql (client)'}
if (-not (Check-Cmd dotnet)) { $missing += '.NET SDK (dotnet)'}

if ($missing.Count -gt 0) {
    Write-Host "Missing required tools:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host " - $_" }
    Write-Host "Install the missing tools (PHP, MySQL client, .NET SDK) and re-run this script." -ForegroundColor Yellow
    exit 1
}

# 2) Import DB schema
$schemaPath = Join-Path $PSScriptRoot 'db\schema.sql'
if (-not (Test-Path $schemaPath)) {
    Write-Host "Cannot find schema.sql at $schemaPath" -ForegroundColor Red
    exit 1
}

Write-Host "Importing database schema..." -ForegroundColor Green
Write-Host "You will be prompted for your MySQL root password if required." -ForegroundColor Yellow
# Use cmd to allow interactive password prompt
$cmd = "mysql -u root -p < \"$schemaPath\""
cmd /c $cmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "mysql import returned exit code $LASTEXITCODE. If import failed, ensure MySQL client is installed and accessible." -ForegroundColor Red
    # continue: user might want to try manual import
}
else {
    Write-Host "Database import attempted (check MySQL for errors)." -ForegroundColor Green
}

# 3) Set environment variables for current session
Write-Host "Setting environment variables for this PowerShell session..." -ForegroundColor Green
$env:DB_HOST = '127.0.0.1'
$env:DB_NAME = 'urs_clinic'
$env:DB_USER = 'root'
# For DB password we ask the user (do not store persistently)
$plainDbPass = Read-Host "Enter DB password for user 'root' (leave blank if none)" -AsSecureString
if ($plainDbPass.Length -gt 0) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($plainDbPass)
    $unsecure = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    $env:DB_PASS = $unsecure
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
} else {
    $env:DB_PASS = ''
}

# Encryption key
$env:ENCRYPTION_KEY = Read-Host "Enter an ENCRYPTION_KEY (32+ bytes) or press Enter to auto-generate" 
if ([string]::IsNullOrWhiteSpace($env:ENCRYPTION_KEY)) {
    $env:ENCRYPTION_KEY = [System.BitConverter]::ToString((1..32 | ForEach-Object { Get-Random -Maximum 256 })) -Replace '-',''
    Write-Host "Generated ENCRYPTION_KEY: $env:ENCRYPTION_KEY" -ForegroundColor Yellow
} else {
    Write-Host "Using provided ENCRYPTION_KEY." -ForegroundColor Green
}

# 4) Create admin user via php script
$scriptDir = Join-Path $PSScriptRoot 'api\scripts'
if (-not (Test-Path (Join-Path $scriptDir 'create_admin.php'))) {
    Write-Host "Cannot find create_admin.php in $scriptDir" -ForegroundColor Red
} else {
    Write-Host "Creating admin user..." -ForegroundColor Green
    $adminUser = Read-Host "Admin username" -Default 'admin'
    $adminPass = Read-Host "Admin password (will be used for auth.php)" -AsSecureString
    $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass)
    $adminPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)

    Push-Location $scriptDir
    $out = & php create_admin.php $adminUser $adminPassPlain 2>&1
    Pop-Location
    Write-Host "create_admin.php output:" -ForegroundColor Cyan
    Write-Host $out
    # Attempt to extract api_key from output
    if ($out -match 'api_key:\s*([a-f0-9]+)') {
        $apiKey = $matches[1]
        Write-Host "Detected api_key: $apiKey" -ForegroundColor Green
    } else {
        Write-Host "Could not automatically parse api_key. Check the output above to copy the key." -ForegroundColor Yellow
        $apiKey = Read-Host "Paste API key from script output (or type it now)"
    }
}

# 5) Seed sample data
if (Test-Path (Join-Path $scriptDir 'seed_sample.php')) {
    Write-Host "Seeding sample data..." -ForegroundColor Green
    Push-Location $scriptDir
    & php seed_sample.php
    Pop-Location
}

# 6) Start PHP dev server for api/ (background)
$apiDir = Join-Path $PSScriptRoot 'api'
Write-Host "Starting PHP built-in server for api/ on http://localhost:8000" -ForegroundColor Green
Start-Process -FilePath php -ArgumentList '-S localhost:8000' -WorkingDirectory $apiDir
Write-Host "PHP server started (check task manager/console or open http://localhost:8000)" -ForegroundColor Cyan

Write-Host "Setup complete. Use the printed API key to test endpoints." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  - Run the Admin app: cd admin; dotnet run" -ForegroundColor Yellow
Write-Host "  - Open frontend demo: open frontend\index.html in your browser" -ForegroundColor Yellow
Write-Host "Example verify curl (replace YOUR_API_KEY):" -ForegroundColor White
Write-Host "curl -X POST http://localhost:8000/verify_fingerprint.php -H \"Content-Type: application/json\" -H \"X-API-KEY: $apiKey\" -d '{\"template_base64\":\"c2FtcGxlX3RlbXBsYXRlX2J5dGVz\"}'" -ForegroundColor Magenta

# Keep PowerShell open to preserve env vars in this session
Write-Host "Script finished. Keep this PowerShell session open to preserve environment variables for further commands." -ForegroundColor Cyan
