-- ============================================================================
-- Modulo: AdaptadorRAMVistas.vhd
-- Descripcion:
--   Interfaz de conversion y exploracion ciclica entre la memoria RAM y el
--   multiplexor de visualizacion (MultiplexorVistas).
--   Realiza un barrido periodico (scan) de las 11 posiciones activas de memoria
--   y retiene sus valores en registros BCD de 4 bits.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity AdaptadorRAMVistas is
    port (
        Clock    : in  std_logic;                    -- Reloj maestro del sistema
        Reset    : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        
        -- Interfaz de lectura con MemoriaRAM
        ram_addr_rd  : out std_logic_vector(3 downto 0); -- Bus de direccion de barrido
        ram_data_rd  : in  std_logic_vector(7 downto 0); -- Bus de dato leido
        
        -- Buses BCD de salida hacia MultiplexorVistas
        reg_r_s  : out std_logic_vector(3 downto 0); -- Direccion 0: Rojo Pequenas
        reg_r_g  : out std_logic_vector(3 downto 0); -- Direccion 1: Rojo Grandes
        reg_r_t  : out std_logic_vector(3 downto 0); -- Direccion 2: Rojo Total
        reg_v_s  : out std_logic_vector(3 downto 0); -- Direccion 3: Verde Pequenas
        reg_v_g  : out std_logic_vector(3 downto 0); -- Direccion 4: Verde Grandes
        reg_v_t  : out std_logic_vector(3 downto 0); -- Direccion 5: Verde Total
        reg_a_s  : out std_logic_vector(3 downto 0); -- Direccion 6: Azul Pequenas
        reg_a_g  : out std_logic_vector(3 downto 0); -- Direccion 7: Azul Grandes
        reg_a_t  : out std_logic_vector(3 downto 0); -- Direccion 8: Azul Total
        reg_tot_u: out std_logic_vector(3 downto 0); -- Direccion 9: Total Unidades
        reg_tot_d: out std_logic_vector(3 downto 0)  -- Direccion 10: Total Decenas
    );
end entity;

architecture rtl of AdaptadorRAMVistas is

    signal scan_addr   : unsigned(3 downto 0) := (others => '0');
    signal scan_addr_d : unsigned(3 downto 0) := (others => '0');
    
    signal r_r_s, r_r_g, r_r_t : std_logic_vector(3 downto 0) := "0000";
    signal r_v_s, r_v_g, r_v_t : std_logic_vector(3 downto 0) := "0000";
    signal r_a_s, r_a_g, r_a_t : std_logic_vector(3 downto 0) := "0000";
    signal r_tot_u, r_tot_d    : std_logic_vector(3 downto 0) := "0000";

begin

    ram_addr_rd <= std_logic_vector(scan_addr);

    -- -------------------------------------------------------------------------
    -- Proceso de Barrido Ciclico y Captura Pipeline
    -- -------------------------------------------------------------------------
    process(Clock, Reset)
    begin
        if Reset = '0' then
            scan_addr   <= (others => '0');
            scan_addr_d <= (others => '0');
            r_r_s <= (others => '0'); r_r_g <= (others => '0'); r_r_t <= (others => '0');
            r_v_s <= (others => '0'); r_v_g <= (others => '0'); r_v_t <= (others => '0');
            r_a_s <= (others => '0'); r_a_g <= (others => '0'); r_a_t <= (others => '0');
            r_tot_u <= (others => '0'); r_tot_d <= (others => '0');
        elsif rising_edge(Clock) then
            -- Retardo de 1 ciclo para sincronizar con la latencia de lectura de RAM
            scan_addr_d <= scan_addr;
            
            -- Contador de barrido secuencial de 0 a 10
            if scan_addr = 10 then
                scan_addr <= (others => '0');
            else
                scan_addr <= scan_addr + 1;
            end if;
            
            -- Demultiplexacion de datos hacia registros de retencion
            case to_integer(scan_addr_d) is
                when 0  => r_r_s   <= ram_data_rd(3 downto 0);
                when 1  => r_r_g   <= ram_data_rd(3 downto 0);
                when 2  => r_r_t   <= ram_data_rd(3 downto 0);
                when 3  => r_v_s   <= ram_data_rd(3 downto 0);
                when 4  => r_v_g   <= ram_data_rd(3 downto 0);
                when 5  => r_v_t   <= ram_data_rd(3 downto 0);
                when 6  => r_a_s   <= ram_data_rd(3 downto 0);
                when 7  => r_a_g   <= ram_data_rd(3 downto 0);
                when 8  => r_a_t   <= ram_data_rd(3 downto 0);
                when 9  => r_tot_u <= ram_data_rd(3 downto 0);
                when 10 => r_tot_d <= ram_data_rd(3 downto 0);
                when others => null;
            end case;
        end if;
    end process;

    -- Conexiones concurrentes de salida
    reg_r_s   <= r_r_s;   reg_r_g   <= r_r_g;   reg_r_t   <= r_r_t;
    reg_v_s   <= r_v_s;   reg_v_g   <= r_v_g;   reg_v_t   <= r_v_t;
    reg_a_s   <= r_a_s;   reg_a_g   <= r_a_g;   reg_a_t   <= r_a_t;
    reg_tot_u <= r_tot_u; reg_tot_d <= r_tot_d;

end architecture;
