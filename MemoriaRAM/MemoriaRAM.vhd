-- ============================================================================
-- Modulo: MemoriaRAM.vhd
-- Descripcion:
--   Memoria de acceso aleatorio (RAM) de 16 palabras x 8 bits con escritura
--   sincrona y lectura asincrona.
--
-- Mapa de Direcciones:
--   Dir  0: Contador Rojo Pequenas  (reg_r_s)
--   Dir  1: Contador Rojo Grandes   (reg_r_g)
--   Dir  2: Contador Rojo Total     (reg_r_t)
--   Dir  3: Contador Verde Pequenas (reg_v_s)
--   Dir  4: Contador Verde Grandes  (reg_v_g)
--   Dir  5: Contador Verde Total    (reg_v_t)
--   Dir  6: Contador Azul Pequenas  (reg_a_s)
--   Dir  7: Contador Azul Grandes   (reg_a_g)
--   Dir  8: Contador Azul Total     (reg_a_t)
--   Dir  9: Total Global Unidades   (reg_tot_u)
--   Dir 10: Total Global Decenas    (reg_tot_d)
--   Dir 11-15: Direcciones reservadas
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MemoriaRAM is
    port (
        Clock    : in  std_logic;                    -- Reloj del sistema
        Reset    : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        WE       : in  std_logic;                    -- Habilitacion de escritura (Write Enable)
        addr     : in  std_logic_vector(3 downto 0); -- Bus de direcciones (4 bits = 16 palabras)
        data_in  : in  std_logic_vector(7 downto 0); -- Bus de datos de entrada (8 bits)
        data_out : out std_logic_vector(7 downto 0)  -- Bus de datos de salida (8 bits)
    );
end entity;

architecture rtl of MemoriaRAM is
    type ram_array is array (0 to 15) of std_logic_vector(7 downto 0);
    signal memoria : ram_array;
begin

    -- Proceso de escritura sincrona con inicializacion asincrona
    process(Clock, Reset)
    begin
        if Reset = '0' then
            for i in 0 to 15 loop
                memoria(i) <= (others => '0');
            end loop;
        elsif rising_edge(Clock) then
            if WE = '1' then
                memoria(to_integer(unsigned(addr))) <= data_in;
            end if;
        end if;
    end process;

    -- Lectura asincrona combinacional
    data_out <= memoria(to_integer(unsigned(addr)));

end architecture;
