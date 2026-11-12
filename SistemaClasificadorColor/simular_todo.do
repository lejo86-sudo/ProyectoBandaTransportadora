# ==============================================================================
# Script de Simulación Integral para ModelSim Altera
# Proyecto: Clasificador de Color TCS3200 con Sensor IR
# ==============================================================================

vlib work

# 1. Compilar subsistema Sensor IR
vcom -work work ../DetectorPresenciaIR/DetectorPresenciaIR.vhd

# 2. Compilar subsistema Sensor de Color TCS3200
vcom -work work ../ControladorColorTCS3200/MedidorPeriodo.vhd
vcom -work work ../ControladorColorTCS3200/ControladorColorTCS3200.vhd

# 3. Compilar Top-Level y Testbench
vcom -work work SistemaClasificadorColor.vhd
vcom -work work tb_SistemaClasificadorColor.vhd

# 4. Iniciar simulación
vsim -t 1ps -lib work tb_SistemaClasificadorColor

# 5. Agregar señales al visor Wave
add wave -divider "RELOJ Y RESET"
add wave -format Logic /tb_SistemaClasificadorColor/clk
add wave -format Logic /tb_SistemaClasificadorColor/rst

add wave -divider "SENSOR IR Y PRESENCIA"
add wave -format Logic /tb_SistemaClasificadorColor/ir_sensor_out
add wave -format Logic /tb_SistemaClasificadorColor/presence_led
add wave -format Logic /tb_SistemaClasificadorColor/DUT/piece_present_sig
add wave -format Logic /tb_SistemaClasificadorColor/DUT/start_color_sig

add wave -divider "CONTROL TCS3200"
add wave -format Logic /tb_SistemaClasificadorColor/S0
add wave -format Logic /tb_SistemaClasificadorColor/S1
add wave -format Logic /tb_SistemaClasificadorColor/S2
add wave -format Logic /tb_SistemaClasificadorColor/S3
add wave -format Logic /tb_SistemaClasificadorColor/tcs_out

add wave -divider "FSM COLOR INTERNA"
add wave -format Literal -radix ASCII /tb_SistemaClasificadorColor/DUT/SUBSISTEMA_COLOR_TCS/estado_actual
add wave -format Literal -radix unsigned /tb_SistemaClasificadorColor/DUT/SUBSISTEMA_COLOR_TCS/reg_per_R
add wave -format Literal -radix unsigned /tb_SistemaClasificadorColor/DUT/SUBSISTEMA_COLOR_TCS/reg_per_G
add wave -format Literal -radix unsigned /tb_SistemaClasificadorColor/DUT/SUBSISTEMA_COLOR_TCS/reg_per_B

add wave -divider "SALIDAS CLASIFICACION LED"
add wave -format Logic /tb_SistemaClasificadorColor/led_R
add wave -format Logic /tb_SistemaClasificadorColor/led_G
add wave -format Logic /tb_SistemaClasificadorColor/led_B

# 6. Ejecutar y ajustar zoom
run -all
wave zoom full
