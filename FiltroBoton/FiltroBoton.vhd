-- ============================================================================
-- Modulo: FiltroBoton.vhd
-- Descripcion:
--   Acondicionador y detector de flanco monotiro para pulsadores mecanicos.
--   Incorpora:
--   1. Inversion logica (pulsadores de la tarjeta DE0 son activos en bajo '0').
--   2. Sincronizador de 2 etapas contra metaestabilidad.
--   3. Muestreador de baja frecuencia (tick_10ms = 100 Hz) para filtrado antirrebote.
--   4. Detector de flanco ascendente que genera un pulso de 1 ciclo de reloj.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;

entity FiltroBoton is
    port (
        Clock      : in  std_logic; -- Reloj maestro del sistema (50 MHz)
        Reset      : in  std_logic; -- Reset asincrono activo en bajo ('0')
        tick_10ms  : in  std_logic; -- Pulso de muestreo antirrebote (cada 10 ms)
        BTN_In     : in  std_logic; -- Entrada asincrona del pulsador fisico
        Pulse_Out  : out std_logic  -- Pulso monotiro sincrono de duracion 1 ciclo
    );
end entity;

architecture rtl of FiltroBoton is
    signal sync        : std_logic_vector(1 downto 0) := "00";
    signal stable      : std_logic := '0';
    signal last_stable : std_logic := '0';
begin

    -- Sincronizacion y filtrado por muestreo
    process(Clock, Reset)
    begin
        if Reset = '0' then
            sync        <= "00";
            stable      <= '0';
            last_stable <= '0';
        elsif rising_edge(Clock) then
            sync(0) <= not BTN_In; -- Inversion de logica activa en bajo
            sync(1) <= sync(0);
            
            if tick_10ms = '1' then
                stable <= sync(1);
            end if;
            
            last_stable <= stable;
        end if;
    end process;

    -- Generacion de pulso monotiro sincrono
    Pulse_Out <= '1' when (stable = '1' and last_stable = '0') else '0';

end architecture;
