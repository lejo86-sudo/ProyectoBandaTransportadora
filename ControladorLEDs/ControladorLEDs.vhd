-- ============================================================================
-- Modulo: ControladorLEDs.vhd
-- Descripcion:
--   Unidad de control para el arreglo de diodos emisores de luz verdes (LEDG)
--   integrados en la tarjeta de desarrollo FPGA DE0.
--   Proporciona senalizacion de latido de reloj/frecuencia (LEDG[0]) e indicacion
--   decodificada del estado de seleccion de color y tamano en modo manual.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity ControladorLEDs is
    port (
        Reset     : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        SW_Modo   : in  std_logic_vector(1 downto 0); -- Selector de modo de operacion
        SW_Color  : in  std_logic_vector(1 downto 0); -- Codigo de color seleccionado
        SW_Tamano : in  std_logic;                    -- Criterio de tamano ('0'=Pequeno, '1'=Grande)
        frec_int  : in  std_logic;                    -- Pulso de referencia de frecuencia
        LEDG      : out std_logic_vector(9 downto 0)  -- Bus de salida hacia LEDs verdes
    );
end entity;

architecture rtl of ControladorLEDs is
begin
    process(SW_Modo, frec_int, SW_Color, SW_Tamano, Reset)
    begin
        LEDG <= (others => '0'); 

        -- Indicador de actividad y referencia temporal en LEDG[0]
        if Reset = '1' and SW_Modo /= "11" then 
            LEDG(0) <= frec_int; 
        end if;

        -- Decodificacion de estado en Modo Manual (SW_Modo = "10")
        if SW_Modo = "10" then
            if SW_Color = "01" then 
                if SW_Tamano = '0' then LEDG(1) <= '1'; else LEDG(2) <= '1'; end if;
            elsif SW_Color = "10" then 
                if SW_Tamano = '0' then LEDG(3) <= '1'; else LEDG(4) <= '1'; end if;
            elsif SW_Color = "11" then 
                if SW_Tamano = '0' then LEDG(5) <= '1'; else LEDG(6) <= '1'; end if;
            else 
                LEDG(9) <= '1'; 
            end if; 
        end if;
    end process;
end architecture;
