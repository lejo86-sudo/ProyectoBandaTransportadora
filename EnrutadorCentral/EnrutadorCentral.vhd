-- ============================================================================
-- Modulo: EnrutadorCentral.vhd
-- Descripcion:
--   Unidad de decodificacion y enrutamiento sincrono de pulsos de clasificacion.
--   Canaliza los pulsos estroboscopicos hacia los bancos de inventario
--   especificos (Rojo, Verde, Azul) y genera las senales de acarreo para los
--   contadores decimales de acumulacion global (unidades y decenas).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity EnrutadorCentral is
    port (
        Clock          : in  std_logic;                    -- Reloj maestro del sistema (50 MHz)
        Reset          : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        pulse_btn      : in  std_logic;                    -- Pulso de clasificacion entrante
        SW_Color       : in  std_logic_vector(1 downto 0); -- Codigo de color clasificado
        SW_Tamano      : in  std_logic;                    -- Criterio de tamano de pieza
        cnt_tot_u      : in  std_logic_vector(3 downto 0); -- Conteo actual de unidades globales
        
        -- Pulsos de habilitacion discriminados por banco de color
        pulse_r        : out std_logic;                    -- Habilitacion banco Rojo
        pulse_v        : out std_logic;                    -- Habilitacion banco Verde
        pulse_a        : out std_logic;                    -- Habilitacion banco Azul
        pulse_tot      : out std_logic;                    -- Habilitacion conteo total unidades
        pulse_tot_d    : out std_logic;                    -- Pulso de acarreo hacia decenas totales
        last_color_reg : out std_logic_vector(1 downto 0); -- Registro del ultimo color clasificado
        last_size_reg  : out std_logic                     -- Registro del ultimo tamano clasificado
    );
end entity;

architecture rtl of EnrutadorCentral is
    signal p_tot : std_logic;
begin

    -- Enrutamiento condicional de pulso segun categoria espectral
    pulse_r <= pulse_btn when SW_Color = "01" else '0';
    pulse_v <= pulse_btn when SW_Color = "10" else '0';
    pulse_a <= pulse_btn when SW_Color = "11" else '0';
    
    -- Habilitacion de acumulador total para clasificaciones validas
    p_tot <= pulse_btn when (SW_Color = "01" or SW_Color = "10" or SW_Color = "11") else '0';
             
    pulse_tot <= p_tot;

    -- Generacion sincrona de acarreo decimal (cuando unidades = 9)
    pulse_tot_d <= '1' when (p_tot = '1' and cnt_tot_u = "1001") else '0';

    -- Registro del ultimo estado capturado
    process(Clock, Reset)
    begin
        if Reset = '0' then 
            last_color_reg <= "00"; 
            last_size_reg  <= '0';
        elsif rising_edge(Clock) then
            if p_tot = '1' then 
                last_color_reg <= SW_Color; 
                last_size_reg  <= SW_Tamano; 
            end if;
        end if;
    end process;

end architecture;
