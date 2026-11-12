-- ============================================================================
-- Modulo: Decodificador7seg.vhd
-- Descripcion:
--   Decodificador combinacional de 5 bits a visualizador de 7 segmentos de
--   anodo comun (logica activa en bajo: '0'=encendido, '1'=apagado).
--   Asignacion de segmentos: SEG(6 downto 0) = g, f, e, d, c, b, a.
--
-- Mapa de Caracteres:
--   - 0..9: Digitos numericos decimales.
--   - 10:   Caracter 'r' (Rojo).
--   - 11:   Caracter 'U'/'V' (Verde).
--   - 12:   Caracter 'A' (Azul).
--   - 13:   Caracter 't' (Total).
--   - 14:   Caracter 'P' (Pequeno).
--   - 15:   Caracter 'L' (Grande / Large).
--   - 16:   Caracter '-' (Guion medio).
--   - 17:   Caracter 'd' (Descarte).
--   - 18:   Caracter 'E' (Estado).
--   - 19:   Caracter 'C' (Calibracion).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity Decodificador7Seg is
    port (
        BCD : in  std_logic_vector(4 downto 0); -- Codigo de entrada de 5 bits
        SEG : out std_logic_vector(6 downto 0)  -- Salidas a segmentos (g downto a)
    );
end entity;

architecture rtl of Decodificador7Seg is
begin
    process(BCD)
    begin
        case BCD is
            when "00000" => SEG <= "1000000"; -- Digito '0'
            when "00001" => SEG <= "1111001"; -- Digito '1'
            when "00010" => SEG <= "0100100"; -- Digito '2'
            when "00011" => SEG <= "0110000"; -- Digito '3'
            when "00100" => SEG <= "0011001"; -- Digito '4'
            when "00101" => SEG <= "0010010"; -- Digito '5' / Caracter 'S'
            when "00110" => SEG <= "0000010"; -- Digito '6'
            when "00111" => SEG <= "1111000"; -- Digito '7'
            when "01000" => SEG <= "0000000"; -- Digito '8'
            when "01001" => SEG <= "0010000"; -- Digito '9'
            
            -- Caracteres Alfanumericos de Interfaz
            when "01010" => SEG <= "0101111"; -- Caracter 'r'
            when "01011" => SEG <= "1000001"; -- Caracter 'U'
            when "01100" => SEG <= "0001000"; -- Caracter 'A'
            when "01101" => SEG <= "0000111"; -- Caracter 't'
            when "01110" => SEG <= "0001100"; -- Caracter 'P'
            when "01111" => SEG <= "1000111"; -- Caracter 'L'
            when "10000" => SEG <= "0111111"; -- Caracter '-'
            when "10001" => SEG <= "0100001"; -- Caracter 'd'
            when "10010" => SEG <= "0000110"; -- Caracter 'E'
            when "10011" => SEG <= "1000110"; -- Caracter 'C'
            
            when others  => SEG <= "1111111"; -- Visualizador apagado
        end case;
    end process;
end architecture;
