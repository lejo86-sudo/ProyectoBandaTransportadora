# ==============================================================================
# Script de Simulación Individual para Sensor de Presencia IR
# ==============================================================================

vlib work

vcom -work work DetectorPresenciaIR.vhd
vcom -work work tb_DetectorPresenciaIR.vhd

vsim -t 1ps -lib work tb_DetectorPresenciaIR

add wave -divider "RELOJ Y RESET"
add wave -format Logic /tb_DetectorPresenciaIR/clk
add wave -format Logic /tb_DetectorPresenciaIR/rst

add wave -divider "ENTRADA FISICA IR"
add wave -format Logic /tb_DetectorPresenciaIR/ir_sensor_out

add wave -divider "FILTRO Y SINCRONIZADOR"
add wave -format Logic /tb_DetectorPresenciaIR/DUT/sync2
add wave -format Literal -radix unsigned /tb_DetectorPresenciaIR/DUT/filter_cnt
add wave -format Logic /tb_DetectorPresenciaIR/DUT/stable_detect

add wave -divider "SALIDAS"
add wave -format Logic /tb_DetectorPresenciaIR/presence_led
add wave -format Logic /tb_DetectorPresenciaIR/piece_present
add wave -format Logic /tb_DetectorPresenciaIR/start_color_pulse

run -all
wave zoom full
