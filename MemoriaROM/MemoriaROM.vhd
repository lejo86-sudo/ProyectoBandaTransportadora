-- ============================================================================
-- Modulo: MemoriaROM.vhd
-- Descripcion:
--   Memoria de solo lectura (ROM) combinacional de 16 palabras x 8 bits.
--   Almacena la tabla de patrones de caracteristicas de piezas validas.
--
-- Formato de Palabra de Datos (8 bits):
--   Bits 7-6: Reservado ("00")
--   Bits 5-4: Codigo de color ("01"=Rojo, "10"=Verde, "11"=Azul)
--   Bit    3: Indicador de dimension ('0'=Pequeno, '1'=Grande)
--   Bits 2-0: Reservado para clasificacion extendida ("000")
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity MemoriaROM is
    port (
        addr     : in  std_logic_vector(3 downto 0); -- Bus de direcciones (4 bits)
        data_out : out std_logic_vector(7 downto 0)  -- Bus de datos de salida (8 bits)
    );
end entity;

architecture rtl of MemoriaROM is
begin

    -- Decodificacion combinacional de lectura ROM
    process(addr)
    begin
        case addr is
            -- Clasificacion Piezas Rojas
            when "0000" => data_out <= "00010000"; -- Direccion 0: Rojo Pequeno
            when "0001" => data_out <= "00011000"; -- Direccion 1: Rojo Grande
            
            -- Clasificacion Piezas Verdes
            when "0010" => data_out <= "00100000"; -- Direccion 2: Verde Pequeno
            when "0011" => data_out <= "00101000"; -- Direccion 3: Verde Grande
            
            -- Clasificacion Piezas Azules
            when "0100" => data_out <= "00110000"; -- Direccion 4: Azul Pequeno
            when "0101" => data_out <= "00111000"; -- Direccion 5: Azul Grande
            
            when others => data_out <= "00000000"; -- Direcciones no asignadas
        end case;
    end process;

end architecture;
