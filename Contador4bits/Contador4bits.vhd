-- ============================================================================
-- Modulo: Contador4bits.vhd
-- Descripcion:
--   Contador sincrono de modulo 10 (conteo decimal BCD de 0 a 9) con reset
--   asincrono activo en bajo y entrada de habilitacion (EN).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all; 

entity Contador4bits is
    port (
        Clock : in  std_logic;                    -- Reloj maestro del sistema
        Reset : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        EN    : in  std_logic;                    -- Habilitacion sincrona de conteo
        CNT   : out std_logic_vector(3 downto 0)  -- Salida BCD cuantizada (0 a 9)
    );
end entity;

architecture rtl of Contador4bits is
    signal CNT_int : integer range 0 to 9 := 0;
begin

    process(Clock, Reset)
    begin
        if Reset = '0' then
            CNT_int <= 0;
        elsif rising_edge(Clock) then
            if EN = '1' then
                if CNT_int = 9 then
                    CNT_int <= 0;
                else
                    CNT_int <= CNT_int + 1;
                end if;
            end if;
        end if;
    end process;

    CNT <= std_logic_vector(to_unsigned(CNT_int, 4));

end architecture;
