-- ============================================================================
-- Modulo: Registro4bits.vhd
-- Descripcion:
--   Registro sincrono de almacenamiento temporal de 4 bits con carga paralela,
--   entrada de habilitacion (EN) y reset asincrono activo en bajo.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity Registro4bits is
    port (
        Clock   : in  std_logic;                    -- Reloj maestro del sistema
        Reset   : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        EN      : in  std_logic;                    -- Habilitacion de carga de datos
        Reg_In  : in  std_logic_vector(3 downto 0); -- Bus de datos de entrada
        Reg_Out : out std_logic_vector(3 downto 0)  -- Bus de datos registrado
    );
end entity;

architecture rtl of Registro4bits is
begin

    process(Clock, Reset)
    begin
        if Reset = '0' then
            Reg_Out <= (others => '0');
        elsif rising_edge(Clock) then
            if EN = '1' then
                Reg_Out <= Reg_In;
            end if;
        end if;
    end process;

end architecture;
