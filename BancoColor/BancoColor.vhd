-- ============================================================================
-- Modulo: BancoColor.vhd
-- Descripcion:
--   Unidad modular de inventario para una categoria de color individual.
--   Integra tres canales independientes de conteo y retencion en registros:
--   1. Piezas de tamano pequeno (Tamano_In = '0').
--   2. Piezas de tamano grande   (Tamano_In = '1').
--   3. Total acumulado para dicha categoria de color.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity BancoColor is
    port (
        Clock        : in  std_logic;                    -- Reloj maestro del sistema (50 MHz)
        Reset        : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        Pulse_In     : in  std_logic;                    -- Pulso de clasificacion validado
        Tamano_In    : in  std_logic;                    -- Criterio de dimension ('0'=Pequeno, '1'=Grande)
        
        -- Salidas registradas de inventario en formato BCD (4 bits)
        Reg_Pequenas : out std_logic_vector(3 downto 0); -- Cantidad acumulada piezas pequenas
        Reg_Grandes  : out std_logic_vector(3 downto 0); -- Cantidad acumulada piezas grandes
        Reg_Total    : out std_logic_vector(3 downto 0)  -- Cantidad total acumulada del color
    );
end entity;

architecture rtl of BancoColor is

    component Contador4bits is
        port (
            Clock : in  std_logic;
            Reset : in  std_logic;
            EN    : in  std_logic;
            CNT   : out std_logic_vector(3 downto 0)
        );
    end component;

    component Registro4bits is
        port (
            Clock   : in  std_logic;
            Reset   : in  std_logic;
            EN      : in  std_logic;
            Reg_In  : in  std_logic_vector(3 downto 0);
            Reg_Out : out std_logic_vector(3 downto 0)
        );
    end component;

    signal p_peq, p_gra, p_tot : std_logic;
    signal cnt_p, cnt_g, cnt_t : std_logic_vector(3 downto 0);

begin

    -- Discriminacion interna segun tamano
    p_peq <= Pulse_In when Tamano_In = '0' else '0';
    p_gra <= Pulse_In when Tamano_In = '1' else '0';
    p_tot <= p_peq or p_gra;

    -- Canal de Conteo y Registro: Piezas Pequenas
    C_P: Contador4bits port map (Clock, Reset, p_peq, cnt_p);
    R_P: Registro4bits port map (Clock, Reset, '1', cnt_p, Reg_Pequenas);
    
    -- Canal de Conteo y Registro: Piezas Grandes
    C_G: Contador4bits port map (Clock, Reset, p_gra, cnt_g);
    R_G: Registro4bits port map (Clock, Reset, '1', cnt_g, Reg_Grandes);
    
    -- Canal de Conteo y Registro: Total Acumulado del Color
    C_T: Contador4bits port map (Clock, Reset, p_tot, cnt_t);
    R_T: Registro4bits port map (Clock, Reset, '1', cnt_t, Reg_Total);

end architecture;
