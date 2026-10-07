param(
    [string]$Repo = "G:\ssd-system-guard",
    [string]$GoogleVerification = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "SSD System Guard - SEO patch" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Repo)) {
    throw "Repositorio nao encontrado: $Repo"
}

# Locate the GitHub Pages index.
$candidates = @(
    (Join-Path $Repo "index.html"),
    (Join-Path $Repo "docs\index.html"),
    (Join-Path $Repo "site\index.html"),
    (Join-Path $Repo "website\index.html")
)

$Index = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
        $Index = $candidate
        break
    }
}

if (-not $Index) {
    $found = Get-ChildItem -LiteralPath $Repo -Recurse -Filter "index.html" -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\node_modules\\|\\bin\\|\\obj\\'
        } |
        Select-Object -First 1

    if ($found) {
        $Index = $found.FullName
    }
}

if (-not $Index) {
    throw "Nao encontrei index.html no repositorio."
}

Write-Host "Site encontrado:" -ForegroundColor Green
Write-Host $Index

$SiteDir = Split-Path -Parent $Index
$Backup = "$Index.pre-seo-backup"

if (-not (Test-Path -LiteralPath $Backup)) {
    Copy-Item -LiteralPath $Index -Destination $Backup -Force
    Write-Host "Backup criado: $Backup"
}

$html = Get-Content -LiteralPath $Index -Raw -Encoding UTF8

$start = "<!-- SSD System Guard SEO v1 -->"
$end = "<!-- /SSD System Guard SEO v1 -->"

$seo = @'
<!-- SSD System Guard SEO v1 -->
<title>SSD System Guard — Proteção de downloads e jogos no SSD C: | Windows</title>
<meta name="description" content="SSD System Guard é um aplicativo open source para Windows que monitora downloads de risco, novos jogos Steam/Epic no SSD C:, executáveis portáteis, alertas e quarentena.">
<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">

<link rel="canonical" href="https://leonardorobertomotalvao.github.io/ssd-system-guard/">

<meta property="og:type" content="website">
<meta property="og:site_name" content="SSD System Guard">
<meta property="og:title" content="SSD System Guard — Proteção inteligente para o SSD do sistema">
<meta property="og:description" content="Proteja o SSD C: contra downloads de risco e novas instalações de jogos Steam/Epic. Open source para Windows.">
<meta property="og:url" content="https://leonardorobertomotalvao.github.io/ssd-system-guard/">

<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="SSD System Guard">
<meta name="twitter:description" content="Proteção inteligente para downloads, Steam/Epic e executáveis no SSD do sistema.">

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "SSD System Guard",
  "url": "https://leonardorobertomotalvao.github.io/ssd-system-guard/",
  "downloadUrl": "https://github.com/Leonardorobertomotalvao/ssd-system-guard/releases/latest",
  "operatingSystem": "Windows 10, Windows 11",
  "applicationCategory": "UtilitiesApplication",
  "description": "Aplicativo open source para Windows que monitora downloads de risco, novos jogos Steam/Epic no SSD C:, executáveis portáteis, alertas e quarentena.",
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "BRL"
  },
  "sameAs": [
    "https://github.com/Leonardorobertomotalvao/ssd-system-guard"
  ]
}
</script>
<!-- /SSD System Guard SEO v1 -->
'@

if (-not [string]::IsNullOrWhiteSpace($GoogleVerification)) {
    $verification = '<meta name="google-site-verification" content="' +
        $GoogleVerification.Replace('"','') +
        '">'
    $seo = $seo.Replace(
        '<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">',
        '<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">' +
        [Environment]::NewLine +
        $verification
    )
}

# Remove our previous SEO block if the script is re-run.
if ($html.Contains($start) -and $html.Contains($end)) {
    $pattern = '(?s)<!-- SSD System Guard SEO v1 -->.*?<!-- /SSD System Guard SEO v1 -->'
    $html = [regex]::Replace($html, $pattern, "")
}

# Avoid competing title/description/canonical declarations.
$html = [regex]::Replace(
    $html,
    '(?is)<title>.*?</title>',
    ''
)

$html = [regex]::Replace(
    $html,
    '(?is)<meta\s+name=["'']description["''][^>]*>',
    ''
)

$html = [regex]::Replace(
    $html,
    '(?is)<link\s+rel=["'']canonical["''][^>]*>',
    ''
)

if ($html -notmatch '(?i)</head>') {
    throw "O index.html nao possui </head>."
}

$html = [regex]::Replace(
    $html,
    '(?i)</head>',
    ($seo + [Environment]::NewLine + '</head>'),
    1
)

Set-Content -LiteralPath $Index -Value $html -Encoding UTF8

$sitemap = @'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://leonardorobertomotalvao.github.io/ssd-system-guard/</loc>
    <lastmod>2026-10-07</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
</urlset>

'@

$SitemapPath = Join-Path $SiteDir "sitemap.xml"
Set-Content -LiteralPath $SitemapPath -Value $sitemap -Encoding UTF8

Write-Host ""
Write-Host "SEO aplicado." -ForegroundColor Green
Write-Host "Index: $Index"
Write-Host "Sitemap: $SitemapPath"
Write-Host ""
Write-Host "Agora revise com:" -ForegroundColor Cyan
Write-Host 'git diff -- index.html docs/index.html sitemap.xml docs/sitemap.xml'
Write-Host ""
