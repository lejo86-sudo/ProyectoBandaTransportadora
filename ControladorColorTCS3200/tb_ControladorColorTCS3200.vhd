-- ============================================================================
-- Banco de Pruebas: tb_ControladorColorTCS3200.vhd
-- Descripcion:
--   Entorno de simulacion y verificacion funcional para el controlador
--   y clasificador optoelectronico TCS3200.
--   Modela la respuesta fotometrica del sensor frente a piezas de tonalidad
--   Roja, Verde y Azul mediante modulacion de frecuencia dependiente del filtro.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_ControladorColorTCS3200 is
end entity;

architecture sim of tb_ControladorColorTCS3200 is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '0';
    signal start         : std_logic := '0';
    signal piece_present : std_logic := '0';
    signal tcs_out       : std_logic := '0';

    signal S0, S1        : std_logic;
    signal S2, S3        : std_logic;
    signal led_R         : std_logic;
    signal led_G         : std_logic;
    signal led_B         : std_logic;
    signal color_code    : std_logic_vector(1 downto 0);
    signal color_ready   : std_logic;
    signal busy          : std_logic;

    type color_sim_t is (COLOR_ROJO, COLOR_VERDE, COLOR_AZUL);
    signal pieza_sim     : color_sim_t := COLOR_ROJO;
    signal sim_terminada : boolean := false;

begin

    -- Dispositivo bajo prueba (DUT)
    DUT: entity work.ControladorColorTCS3200
        generic map (
            CLK_FREQ_HZ     => 50_000_000,
            SETTLING_CYCLES => 10
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            piece_present => piece_present,
            diag_mode     => '0',
            tcs_out       => tcs_out,
            S0            => S0,
            S1            => S1,
            S2            => S2,
            S3            => S3,
            led_R         => led_R,
            led_G         => led_G,
            led_B         => led_B,
            color_code    => color_code,
            color_ready   => color_ready,
            busy          => busy,
            diag_r        => open,
            diag_g        => open,
            diag_b        => open
        );

    -- Generador de senal de reloj de 50 MHz
    p_clk: process
    begin
        while not sim_terminada loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Emulacion del transductor de frecuencia optica TCS3200
    p_tcs_model: process
        variable semipe : time := 200 ns;
    begin
        while not sim_terminada loop
            case pieza_sim is
                when COLOR_ROJO =>
                    if S2 = '0' and S3 = '0' then
                        semipe := 100 ns; -- Alta frecuencia (periodo 200 ns) en canal Rojo
                    else
                        semipe := 400 ns; -- Baja frecuencia (periodo 800 ns) en otros canales
                    end if;
                when COLOR_VERDE =>
                    if S2 = '1' and S3 = '1' then
                        semipe := 120 ns; -- Alta frecuencia (periodo 240 ns) en canal Verde
                    else
                        semipe := 450 ns; -- Baja frecuencia (periodo 900 ns) en otros canales
                    end if;
                when COLOR_AZUL =>
                    if S2 = '0' and S3 = '1' then
                        semipe := 110 ns; -- Alta frecuencia (periodo 220 ns) en canal Azul
                    else
                        semipe := 480 ns; -- Baja frecuencia (periodo 960 ns) en otros canales
                    end if;
            end case;

            tcs_out <= '1'; wait for semipe;
            tcs_out <= '0'; wait for semipe;
        end loop;
        wait;
    end process;

    -- Secuencia de estimulos y aserciones
    p_stim: process
    begin
        rst           <= '0';
        start         <= '0';
        piece_present <= '0';
        wait for 80 ns;
        rst <= '1';
        wait for 40 ns;

        -- Caso de prueba 1: Discriminacion de pieza Roja
        report "Verificando clasificacion de pieza ROJA..." severity note;
        pieza_sim     <= COLOR_ROJO;
        piece_present <= '1';
        start         <= '1';
        wait for 20 ns;
        start         <= '0';

        wait until color_ready = '1';
        wait for 20 ns;
        assert (led_R = '1' and led_G = '0' and led_B = '0' and color_code = "01")
            report "Fallo en clasificacion de pieza ROJA" severity error;
        report "Pieza ROJA clasificada correctamente (Codigo: 01)" severity note;

        piece_present <= '0';
        wait for 100 ns;

        -- Caso de prueba 2: Discriminacion de pieza Verde
        report "Verificando clasificacion de pieza VERDE..." severity note;
        pieza_sim     <= COLOR_VERDE;
        piece_present <= '1';
        start         <= '1';
        wait for 20 ns;
        start         <= '0';

        wait until color_ready = '1';
        wait for 20 ns;
        assert (led_R = '0' and led_G = '1' and led_B = '0' and color_code = "10")
            report "Fallo en clasificacion de pieza VERDE" severity error;
        report "Pieza VERDE clasificada correctamente (Codigo: 10)" severity note;

        piece_present <= '0';
        wait for 100 ns;

        -- Caso de prueba 3: Discriminacion de pieza Azul
        report "Verificando clasificacion de pieza AZUL..." severity note;
        pieza_sim     <= COLOR_AZUL;
        piece_present <= '1';
        start         <= '1';
        wait for 20 ns;
        start         <= '0';

        wait until color_ready = '1';
        wait for 20 ns;
        assert (led_R = '0' and led_G = '0' and led_B = '1' and color_code = "11")
            report "Fallo en clasificacion de pieza AZUL" severity error;
        report "Pieza AZUL clasificada correctamente (Codigo: 11)" severity note;

        sim_terminada <= true;
        report "Verificacion funcional completada exitosamente." severity note;
        wait;
    end process;

end architecture;
