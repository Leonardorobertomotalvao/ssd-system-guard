$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado no PATH."
}

git init
git add .
git commit -m "Initial public release of SSD System Guard"

Write-Host ""
Write-Host "Repositório local criado." -ForegroundColor Green
Write-Host ""
Write-Host "Agora crie um repositório vazio no GitHub e rode:" -ForegroundColor Cyan
Write-Host 'git remote add origin https://github.com/SEU-USUARIO/ssd-system-guard.git'
Write-Host 'git branch -M main'
Write-Host 'git push -u origin main'
