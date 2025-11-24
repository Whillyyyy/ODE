# Run-dev helper: set env vars and start PHP server
$env:DB_HOST = '127.0.0.1'
$env:DB_NAME = 'urs_clinic'
$env:DB_USER = 'root'
$env:DB_PASS = ''
$env:ENCRYPTION_KEY = '32_byte_change_me_please_0123456789'

Write-Host "Starting PHP built-in server at http://localhost:8000 (api/ folder)"
Start-Process -NoNewWindow -FilePath php -ArgumentList '-S localhost:8000' -WorkingDirectory (Join-Path $PSScriptRoot 'api')

Write-Host "To run the ASP.NET Admin app:"
Write-Host "  cd admin; dotnet run"
Write-Host "To open frontend demo: open frontend/index.html in browser"
