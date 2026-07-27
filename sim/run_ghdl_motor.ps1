#-------------------------------------------------------------------------------
# Analizza, elabora ed esegue il testbench della variante MOTORE (Windows).
# Uso:  dal root del progetto  ->  powershell -File sim\run_ghdl_motor.ps1
#-------------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$Std     = "08"
$WorkDir = "sim\work_motor"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$Src = @(
  "rtl\can_pkg.vhd",
  "rtl\can_bit_timing.vhd",
  "rtl\can_mac.vhd",
  "rtl\can_controller.vhd",
  "rtl\pwm_gen.vhd",
  "rtl\motor_expander.vhd",
  "rtl\can_motor_top.vhd",
  "sim\tb_can_motor.vhd"
)

Write-Host "== Analisi =="
& ghdl -a --std=$Std --workdir="$WorkDir" $Src

Write-Host "== Elaborazione =="
& ghdl -e --std=$Std --workdir="$WorkDir" -o "$WorkDir\tb" tb_can_motor

Write-Host "== Esecuzione =="
& ghdl -r --std=$Std --workdir="$WorkDir" tb_can_motor --stop-time=10ms --wave="$WorkDir\tb.ghw"

Write-Host "Onde salvate in $WorkDir\tb.ghw"
