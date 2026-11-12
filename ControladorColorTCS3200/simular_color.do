# ==============================================================================
# Script de Simulación Individual para Sensor de Color TCS3200
# ==============================================================================

vlib work

# 1. Compilar medidor de periodo y controlador de color
vcom -work work MedidorPeriodo.vhd
vcom -work work ControladorColorTCS3200.vhd
vcom -work work tb_ControladorColorTCS3200.vhd

# 2. Iniciar simulación
vsim -t 1ps -lib work tb_ControladorColorTCS3200

# 3. Ondas
add wave -divider "RELOJ Y DISPARO"
add wave -format Logic /tb_ControladorColorTCS3200/clk
add wave -format Logic /tb_ControladorColorTCS3200/rst
add wave -format Logic /tb_ControladorColorTCS3200/start
add wave -format Logic /tb_ControladorColorTCS3200/piece_present

add wave -divider "CONTROL TCS3200"
add wave -format Logic /tb_ControladorColorTCS3200/S0
add wave -format Logic /tb_ControladorColorTCS3200/S1
add wave -format Logic /tb_ControladorColorTCS3200/S2
add wave -format Logic /tb_ControladorColorTCS3200/S3
add wave -format Logic /tb_ControladorColorTCS3200/tcs_out

add wave -divider "MAQUINA DE ESTADOS Y PERIODOS"
add wave -format Literal -radix ASCII /tb_ControladorColorTCS3200/DUT/estado_actual
add wave -format Literal -radix unsigned /tb_ControladorColorTCS3200/DUT/reg_per_R
add wave -format Literal -radix unsigned /tb_ControladorColorTCS3200/DUT/reg_per_G
add wave -format Literal -radix unsigned /tb_ControladorColorTCS3200/DUT/reg_per_B

add wave -divider "RESULTADO CLASIFICACION"
add wave -format Logic /tb_ControladorColorTCS3200/led_R
add wave -format Logic /tb_ControladorColorTCS3200/led_G
add wave -format Logic /tb_ControladorColorTCS3200/led_B
add wave -format Literal -radix binary /tb_ControladorColorTCS3200/color_code
add wave -format Logic /tb_ControladorColorTCS3200/color_ready

run -all
wave zoom full
