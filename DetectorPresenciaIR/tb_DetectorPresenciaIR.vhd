-- ============================================================================
-- Banco de Pruebas: tb_DetectorPresenciaIR.vhd
-- Descripcion:
--   Entorno de simulacion y verificacion para el detector de presencia IR.
--   Valida el rechazo de ruido transitorio (glitches opticos), la respuesta
--   frente a deteccion estable y la generacion monotiro de start_color_pulse.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_DetectorPresenciaIR is
end entity;

architecture sim of tb_DetectorPresenciaIR is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk               : std_logic := '0';
    signal rst               : std_logic := '0';
    signal ir_sensor_out     : std_logic := '1';
    signal presence_led      : std_logic;
    signal piece_present     : std_logic;
    signal start_color_pulse : std_logic;

    signal sim_terminada : boolean := false;

begin

    -- Dispositivo bajo prueba (DUT) con constante de integracion reducida para simulacion
    DUT: entity work.DetectorPresenciaIR
        generic map (
            IR_ACTIVE_LEVEL => '0',
            DEBOUNCE_CYCLES => 5
        )
        port map (
            clk               => clk,
            rst               => rst,
            ir_sensor_out     => ir_sensor_out,
            presence_led      => presence_led,
            piece_present     => piece_present,
            start_color_pulse => start_color_pulse
        );

    -- Generador de senal de reloj maestro (50 MHz)
    p_clk: process
    begin
        while not sim_terminada loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Proceso de estimulos
    p_stim: process
    begin
        -- Inicializacion y ciclo de reset
        rst           <= '0';
        ir_sensor_out <= '1';
        wait for 60 ns;
        rst <= '1';
        wait for 40 ns;

        -- 1. Evaluacion de inmunidad frente a pulsos espurios (menores a DEBOUNCE_CYCLES)
        ir_sensor_out <= '0';
        wait for 40 ns; -- 2 ciclos de reloj (debe ser ignorado)
        ir_sensor_out <= '1';
        wait for 60 ns;
        assert presence_led = '0' 
            report "Fallo: El pulso transitorio no fue filtrado" severity error;

        -- 2. Deteccion valida y sostenida de pieza
        ir_sensor_out <= '0';
        wait until presence_led = '1';
        report "Deteccion confirmada: presence_led activo" severity note;
        
        wait until start_color_pulse = '1';
        wait for CLK_PERIOD / 2;
        assert start_color_pulse = '1' report "Fallo: start_color_pulse no detectado" severity error;
        wait for CLK_PERIOD;
        assert start_color_pulse = '0' report "Fallo: start_color_pulse debe durar exactamente un ciclo" severity error;

        -- Intervalo de permanencia en estacion
        wait for 500 ns;
        assert presence_led = '1' report "Fallo: presence_led debe permanecer en alto" severity error;

        -- 3. Liberacion de la estacion de deteccion
        ir_sensor_out <= '1';
        wait until presence_led = '0';
        report "Liberacion de sensor confirmada: presence_led inactivo" severity note;
        wait for 100 ns;

        sim_terminada <= true;
        report "Verificacion funcional completada exitosamente." severity note;
        wait;
    end process;

end architecture;
