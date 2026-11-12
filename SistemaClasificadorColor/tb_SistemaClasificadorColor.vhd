-- ============================================================================
-- Banco de Pruebas: tb_SistemaClasificadorColor.vhd
-- Descripcion:
--   Entorno de simulacion y verificacion integral del subsistema de sensores.
--   Evalua la interaccion conjunta entre el detector de presencia IR,
--   el detector de dimension (altura) y el clasificador espectral TCS3200.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_SistemaClasificadorColor is
end entity;

architecture sim of tb_SistemaClasificadorColor is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '0';
    signal ir_sensor_out : std_logic := '1';
    signal ir_size_out   : std_logic := '1';
    signal tcs_out       : std_logic := '0';

    signal S0, S1        : std_logic;
    signal S2, S3        : std_logic;
    signal color_code    : std_logic_vector(1 downto 0);
    signal color_ready   : std_logic;
    signal size_code     : std_logic;
    signal presence_led  : std_logic;
    signal size_led      : std_logic;

    type color_sim_t is (COLOR_NINGUNO, PIEZA_ROJA, PIEZA_VERDE, PIEZA_AZUL);
    signal pieza_actual  : color_sim_t := COLOR_NINGUNO;
    signal sim_terminada : boolean := false;

begin

    -- Dispositivo bajo prueba (DUT)
    DUT: entity work.SistemaClasificadorColor
        generic map (
            CLK_FREQ_HZ     => 50_000_000,
            SETTLING_CYCLES => 10,
            DEBOUNCE_CYCLES => 5,
            IR_ACTIVE_LEVEL => '0'
        )
        port map (
            clk           => clk,
            rst           => rst,
            diag_mode     => '0',
            ir_sensor_out => ir_sensor_out,
            ir_size_out   => ir_size_out,
            tcs_out       => tcs_out,
            S0            => S0,
            S1            => S1,
            S2            => S2,
            S3            => S3,
            color_code    => color_code,
            color_ready   => color_ready,
            size_code     => size_code,
            presence_led  => presence_led,
            size_led      => size_led,
            diag_r        => open,
            diag_g        => open,
            diag_b        => open
        );

    -- Generador de senal de reloj (50 MHz)
    p_clk: process
    begin
        while not sim_terminada loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Emulacion del comportamiento del transductor TCS3200
    p_sensor_tcs: process
        variable semipe_actual : time := 500 ns;
    begin
        while not sim_terminada loop
            case pieza_actual is
                when PIEZA_ROJA =>
                    if S2 = '0' and S3 = '0' then
                        semipe_actual := 100 ns; -- Canal Rojo dominante (Periodo = 200 ns)
                    elsif S2 = '1' and S3 = '1' then
                        semipe_actual := 400 ns; -- Periodo = 800 ns
                    else
                        semipe_actual := 500 ns; -- Periodo = 1000 ns
                    end if;

                when PIEZA_VERDE =>
                    if S2 = '1' and S3 = '1' then
                        semipe_actual := 120 ns; -- Canal Verde dominante (Periodo = 240 ns)
                    elsif S2 = '0' and S3 = '0' then
                        semipe_actual := 450 ns; -- Periodo = 900 ns
                    else
                        semipe_actual := 480 ns; -- Periodo = 960 ns
                    end if;

                when PIEZA_AZUL =>
                    if S2 = '0' and S3 = '1' then
                        semipe_actual := 110 ns; -- Canal Azul dominante (Periodo = 220 ns)
                    elsif S2 = '0' and S3 = '0' then
                        semipe_actual := 520 ns; -- Periodo = 1040 ns
                    else
                        semipe_actual := 460 ns; -- Periodo = 920 ns
                    end if;

                when others =>
                    semipe_actual := 500 ns;
            end case;

            tcs_out <= '1'; wait for semipe_actual;
            tcs_out <= '0'; wait for semipe_actual;
        end loop;
        wait;
    end process;

    -- Proceso de estimulos y verificacion
    p_stim: process
    begin
        -- Inicializacion y ciclo de reset
        rst           <= '0';
        ir_sensor_out <= '1';
        ir_size_out   <= '1';
        pieza_actual  <= COLOR_NINGUNO;
        wait for 100 ns;

        rst <= '1';
        wait for 60 ns;
        assert presence_led = '0' report "Fallo: presence_led debe ser '0' en reposo" severity error;

        -- -------------------------------------------------------------
        -- Prueba 1: Deteccion y Clasificacion de Pieza Roja (Grande)
        -- -------------------------------------------------------------
        report "Caso 1: Deteccion de pieza Roja de tamano Grande" severity note;
        pieza_actual  <= PIEZA_ROJA;
        ir_sensor_out <= '0'; -- Sensor IR base activo
        ir_size_out   <= '0'; -- Sensor IR superior activo (tamano grande)

        wait until presence_led = '1';
        wait until color_ready = '1';
        wait for 20 ns;

        assert (color_code = "01" and size_code = '1')
            report "Fallo en clasificacion de pieza Roja Grande" severity error;
        report "Resultado verificado: Rojo (01) y Grande (1)" severity note;

        wait for 1 us;
        ir_sensor_out <= '1';
        ir_size_out   <= '1';
        pieza_actual  <= COLOR_NINGUNO;
        wait for 300 ns;

        -- -------------------------------------------------------------
        -- Prueba 2: Deteccion y Clasificacion de Pieza Verde (Pequena)
        -- -------------------------------------------------------------
        report "Caso 2: Deteccion de pieza Verde de tamano Pequeno" severity note;
        pieza_actual  <= PIEZA_VERDE;
        ir_sensor_out <= '0'; -- Solo sensor base activo
        ir_size_out   <= '1'; -- Sensor superior libre

        wait until presence_led = '1';
        wait until color_ready = '1';
        wait for 20 ns;

        assert (color_code = "10" and size_code = '0')
            report "Fallo en clasificacion de pieza Verde Pequena" severity error;
        report "Resultado verificado: Verde (10) y Pequeno (0)" severity note;

        wait for 1 us;
        ir_sensor_out <= '1';
        pieza_actual  <= COLOR_NINGUNO;
        wait for 300 ns;

        -- -------------------------------------------------------------
        -- Prueba 3: Deteccion y Clasificacion de Pieza Azul (Pequena)
        -- -------------------------------------------------------------
        report "Caso 3: Deteccion de pieza Azul" severity note;
        pieza_actual  <= PIEZA_AZUL;
        ir_sensor_out <= '0';

        wait until presence_led = '1';
        wait until color_ready = '1';
        wait for 20 ns;

        assert (color_code = "11")
            report "Fallo en clasificacion de pieza Azul" severity error;
        report "Resultado verificado: Azul (11)" severity note;

        wait for 1 us;
        ir_sensor_out <= '1';
        pieza_actual  <= COLOR_NINGUNO;
        wait for 300 ns;

        sim_terminada <= true;
        report "Verificacion integral completada exitosamente." severity note;
        wait;
    end process;

end architecture;
