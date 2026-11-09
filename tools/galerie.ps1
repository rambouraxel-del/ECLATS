# Actualise la galerie 3D (Windows). Usage : $env:GODOT="C:\chemin\godot.exe"; .\tools\galerie.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
& $godot --headless --import
& $godot --headless -s tools/galerie/galerie_export.gd -- @args
if (-not (Test-Path galerie/catalogue.json)) { throw "Catalogue absent." }
Write-Host "Galerie prête dans galerie/ (aperçu : python -m http.server -d galerie 8000)"
