#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Analizza, elabora ed esegue il testbench della variante MOTORE con GHDL.
# Uso:  cd al root del progetto  ->  bash sim/run_ghdl_motor.sh
#-------------------------------------------------------------------------------
set -e

STD=08
WORKDIR=sim/work_motor
mkdir -p "$WORKDIR"

SRC=(
  rtl/can_pkg.vhd
  rtl/can_bit_timing.vhd
  rtl/can_mac.vhd
  rtl/can_controller.vhd
  rtl/pwm_gen.vhd
  rtl/motor_expander.vhd
  rtl/can_motor_top.vhd
  sim/tb_can_motor.vhd
)

echo "== Analisi =="
ghdl -a --std=$STD --workdir="$WORKDIR" "${SRC[@]}"

echo "== Elaborazione =="
ghdl -e --std=$STD --workdir="$WORKDIR" -o "$WORKDIR/tb" tb_can_motor

echo "== Esecuzione =="
ghdl -r --std=$STD --workdir="$WORKDIR" tb_can_motor \
  --stop-time=10ms --wave="$WORKDIR/tb.ghw"

echo "Onde salvate in $WORKDIR/tb.ghw (aprire con: gtkwave $WORKDIR/tb.ghw)"
