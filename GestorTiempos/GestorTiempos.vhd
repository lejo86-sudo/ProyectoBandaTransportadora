-- ============================================================================
-- Modulo: GestorTiempos.vhd
-- Descripcion:
--   Generador de bases de tiempo y cronometria del sistema:
--   1. tick_10ms: Base de pulsos de 100 Hz (cada 10 ms = 500,000 ciclos @ 50 MHz)
--      utilizada como reloj de muestreo para los filtros antirrebote.
--   2. tick_1hz: Base de pulsos de 1 Hz (cada 1 segundo = 50,000,000 ciclos @ 50 MHz).
--   3. Cronometro de operacion (c_c, c_t, c_u): Registro decimal BCD de tiempo
--      transcurrido (centenas, decenas, unidades de segundo) con limite en 180 s.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity GestorTiempos is
    port (
        Clock       : in  std_logic;                    -- Reloj maestro del sistema (50 MHz)
        Reset       : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        SW_Modo     : in  std_logic_vector(1 downto 0); -- Selector de modo de operacion
        
        -- Salidas de sincronizacion y cronometria
        tick_10ms   : out std_logic;                    -- Base de tiempo de 10 ms para filtros
        count_s_c   : out integer range 0 to 1;         -- Cronometro: Centenas de segundo
        count_s_t   : out integer range 0 to 9;         -- Cronometro: Decenas de segundo
        count_s_u   : out integer range 0 to 9          -- Cronometro: Unidades de segundo
    );
end entity;

architecture rtl of GestorTiempos is

    signal div_10ms : integer range 0 to 500_000 := 0;
    signal div_1hz  : integer range 0 to 50_000_000 := 0;
    signal tick_1hz : std_logic := '0';
    
    signal c_c    : integer range 0 to 1 := 0;
    signal c_t    : integer range 0 to 9 := 0;
    signal c_u    : integer range 0 to 9 := 0;
    signal t_10ms : std_logic := '0';

begin

    -- -------------------------------------------------------------------------
    -- 1. Divisores de Frecuencia Sincronos
    -- -------------------------------------------------------------------------
    process(Clock)
    begin
        if rising_edge(Clock) then
            -- Base de 10 ms (100 Hz)
            if div_10ms >= 500_000 - 1 then
                div_10ms <= 0;
                t_10ms   <= '1';
            else
                div_10ms <= div_10ms + 1;
                t_10ms   <= '0';
            end if;

            -- Base de 1 segundo (1 Hz)
            if div_1hz >= 50_000_000 - 1 then
                div_1hz  <= 0;
                tick_1hz <= '1';
            else
                div_1hz  <= div_1hz + 1;
                tick_1hz <= '0';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- 2. Cronometro de Tiempo de Operacion
    -- -------------------------------------------------------------------------
    process(Clock, Reset)
    begin
        if Reset = '0' then
            c_u <= 0;
            c_t <= 0;
            c_c <= 0;
        elsif rising_edge(Clock) then
            if tick_1hz = '1' and SW_Modo /= "11" then
                -- Limite maximo de cronometro: 180 segundos
                if c_c = 1 and c_t = 8 and c_u = 0 then
                    null;
                else
                    if c_u = 9 then
                        c_u <= 0;
                        if c_t = 9 then
                            c_t <= 0;
                            c_c <= 1;
                        else
                            c_t <= c_t + 1;
                        end if;
                    else
                        c_u <= c_u + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Asignacion de puertos
    tick_10ms <= t_10ms;
    count_s_c <= c_c;
    count_s_t <= c_t;
    count_s_u <= c_u;

end architecture;
