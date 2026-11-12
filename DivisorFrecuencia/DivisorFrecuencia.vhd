-- ============================================================================
-- Modulo: DivisorFrecuencia.vhd
-- Descripcion:
--   Divisor programable de reloj para la generacion de base temporal intermedia
--   (frec_int). Permite conmutar la frecuencia de salida en funcion del selector
--   de velocidad Sel_Vel (1 Hz, 2 Hz, 4 Hz, 8 Hz nominales a partir de 50 MHz).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity DivisorFrecuencia is
    port ( 
        clk     : in    std_logic;                    -- Reloj maestro de entrada (50 MHz)
        Sel_Vel : in    std_logic_vector(1 downto 0); -- Selector de velocidad (0 a 3)
        out1    : buffer std_logic                    -- Senal de salida dividida
    );
end entity;

architecture rtl of DivisorFrecuencia is
    signal count1    : integer range 0 to 50_000_000 := 0;
    signal max_count : integer range 0 to 50_000_000 := 25_000_000;
begin

    -- Asignacion de valor de modulo segun la escala seleccionada
    process(Sel_Vel)
    begin
        case Sel_Vel is
            when "00" => max_count <= 25_000_000; -- Frecuencia base: ~1 Hz
            when "01" => max_count <= 12_500_000; -- Frecuencia base: ~2 Hz
            when "10" => max_count <= 6_250_000;  -- Frecuencia base: ~4 Hz
            when "11" => max_count <= 3_125_000;  -- Frecuencia base: ~8 Hz
            when others => max_count <= 25_000_000;
        end case;
    end process;

    -- Conteo sincrono y generacion de senal cuadrada
    process(clk)
    begin
        if rising_edge(clk) then
            count1 <= count1 + 1;
            if count1 >= max_count then
                out1   <= not out1;
                count1 <= 0;
            end if;
        end if;
    end process;

end architecture;
