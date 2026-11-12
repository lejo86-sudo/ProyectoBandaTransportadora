-- ============================================================================
-- Modulo: ControladorFrecuencia.vhd
-- Descripcion:
--   Unidad de gestion y regulacion de velocidad para el sistema transportador.
--   Permite el incremento y decremento incremental de la velocidad de marcha
--   mediante pulsadores filtrados (pulse_up, pulse_down), entregando el estado
--   de velocidad cuantizado (0 a 3) y la referencia de base temporal frec_int.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ControladorFrecuencia is
    port (
        Clock      : in  std_logic;                    -- Reloj maestro del sistema (50 MHz)
        Reset      : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        SW_Modo    : in  std_logic_vector(1 downto 0); -- Selector de modo de operacion
        pulse_up   : in  std_logic;                    -- Pulso monotiro de incremento de velocidad
        pulse_down : in  std_logic;                    -- Pulso monotiro de decremento de velocidad
        frec_int   : buffer std_logic;                 -- Frecuencia intermedia generada por divisor
        vel_out    : out std_logic_vector(1 downto 0); -- Nivel binario de velocidad hacia puente H
        reg_frec   : out std_logic_vector(3 downto 0)  -- Codigo de velocidad hacia visualizador
    );
end entity;

architecture rtl of ControladorFrecuencia is

    component DivisorFrecuencia is
        port (
            clk     : in  std_logic;
            Sel_Vel : in  std_logic_vector(1 downto 0);
            out1    : buffer std_logic
        );
    end component;

    component Contador4bits is
        port (
            Clock : in  std_logic;
            Reset : in  std_logic;
            EN    : in  std_logic;
            CNT   : out std_logic_vector(3 downto 0)
        );
    end component;

    -- Registro del estado de velocidad discreto (rango 0 a 3, inicial en 3)
    signal vel_state     : integer range 0 to 3 := 3;
    signal frec_int_last : std_logic := '0';
    signal pulse_frec    : std_logic := '0';
    signal cnt_frec      : std_logic_vector(3 downto 0);
    signal sel_vel_slv   : std_logic_vector(1 downto 0);

begin

    sel_vel_slv <= std_logic_vector(to_unsigned(vel_state, 2));
    vel_out     <= sel_vel_slv;

    -- -------------------------------------------------------------------------
    -- Actualizacion Sincrona del Nivel de Velocidad
    -- -------------------------------------------------------------------------
    process(Clock, Reset)
    begin
        if Reset = '0' then
            vel_state     <= 3;
            frec_int_last <= '0';
        elsif rising_edge(Clock) then
            if pulse_up = '1' and vel_state < 3 then
                vel_state <= vel_state + 1;
            elsif pulse_down = '1' and vel_state > 0 then
                vel_state <= vel_state - 1;
            end if;
            frec_int_last <= frec_int;
        end if;
    end process;

    -- Instanciacion del Divisor Programable de Reloj
    DIV_FREC: DivisorFrecuencia
        port map (
            clk     => Clock,
            Sel_Vel => sel_vel_slv,
            out1    => frec_int
        );

    -- Detector de flanco ascendente de la frecuencia generada
    pulse_frec <= '1' when (frec_int = '1' and frec_int_last = '0' and SW_Modo /= "11" and Reset = '1') else '0';

    C_FR: Contador4bits
        port map (
            Clock => Clock,
            Reset => Reset,
            EN    => pulse_frec,
            CNT   => cnt_frec
        );
    
    -- Representacion BCD de 4 bits del nivel de velocidad
    reg_frec <= "00" & sel_vel_slv;

end architecture;
