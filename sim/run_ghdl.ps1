#-------------------------------------------------------------------------------
# Analizza, elabora ed esegue il testbench con GHDL su Windows (PowerShell).
# Uso:  dal root del progetto  ->  powershell -File sim\run_ghdl.ps1
#-------------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$Std     = "08"
$WorkDir = "sim\work"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$Src = @(
  "rtl\can_pkg.vhd",
  "rtl\can_bit_timing.vhd",
  "rtl\can_mac.vhd",
  "rtl\can_controller.vhd",
  "rtl\io_expander.vhd",
  "rtl\can_ioexpander_top.vhd",
  "sim\tb_can_ioexpander.vhd"
)

Write-Host "== Analisi =="
& ghdl -a --std=$Std --workdir="$WorkDir" $Src

Write-Host "== Elaborazione =="
& ghdl -e --std=$Std --workdir="$WorkDir" -o "$WorkDir\tb" tb_can_ioexpander

Write-Host "== Esecuzione =="
& ghdl -r --std=$Std --workdir="$WorkDir" tb_can_ioexpander --stop-time=10ms --wave="$WorkDir\tb.ghw"

Write-Host "Onde salvate in $WorkDir\tb.ghw"
