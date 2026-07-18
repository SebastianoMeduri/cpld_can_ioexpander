#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Analizza, elabora ed esegue il testbench con GHDL (https://ghdl.github.io).
# Uso:  cd al root del progetto  ->  bash sim/run_ghdl.sh
#-------------------------------------------------------------------------------
set -e

STD=08
WORKDIR=sim/work
mkdir -p "$WORKDIR"

SRC=(
  rtl/can_pkg.vhd
  rtl/can_bit_timing.vhd
  rtl/can_mac.vhd
  rtl/can_controller.vhd
  rtl/quad_decoder.vhd
  rtl/io_expander.vhd
  rtl/can_ioexpander_top.vhd
  sim/tb_can_ioexpander.vhd
)

echo "== Analisi =="
ghdl -a --std=$STD --workdir="$WORKDIR" "${SRC[@]}"

echo "== Elaborazione =="
ghdl -e --std=$STD --workdir="$WORKDIR" -o "$WORKDIR/tb" tb_can_ioexpander

echo "== Esecuzione =="
ghdl -r --std=$STD --workdir="$WORKDIR" tb_can_ioexpander \
  --stop-time=10ms --wave="$WORKDIR/tb.ghw"

echo "Onde salvate in $WORKDIR/tb.ghw (aprire con: gtkwave $WORKDIR/tb.ghw)"
