-- ============================================================================
-- Modulo: DetectorPresenciaIR.vhd
-- Descripcion:
--   Acondicionador digital y sincronizador para sensores opticos de proximidad
--   por infrarrojos (transductor con salida a comparador LM393).
--
-- Principio de Operacion:
--   1. Mitigacion de Metaestabilidad:
--      Cadena de sincronizacion de doble biestable tipo D para senales asincronas.
--   2. Filtro Antirrebote y de Persistencia Temporal:
--      Contador de integracion de DEBOUNCE_CYCLES ciclos de reloj (1 ms @ 50 MHz)
--      para discriminar perturbaciones opticas transitorias, vibraciones
--      mecanicas y rebotes en la superficie de transporte.
--   3. Detector de Flanco y Salidas:
--      - piece_present: Nivel logico filtrado ('1' = pieza presente en la estacion).
--      - start_color_pulse: Pulso sincrono de duracion igual a un ciclo de reloj,
--        generado en la transicion de entrada (flanco de aproximacion).
--      - presence_led: Indicador optico directo de deteccion valida.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity DetectorPresenciaIR is
    generic (
        IR_ACTIVE_LEVEL : std_logic := '0';   -- Polaridad activa del sensor ('0' activo en bajo)
        DEBOUNCE_CYCLES : integer   := 50_000  -- Constante de integracion temporal (1 ms @ 50 MHz)
    );
    port (
        clk               : in  std_logic;
        rst               : in  std_logic;    -- Reset asincrono activo en bajo ('0')
        ir_sensor_out     : in  std_logic;    -- Senal digital cruda proveniente del sensor IR
        
        -- Salidas acondicionadas
        presence_led      : out std_logic;    -- Senal logica directa hacia diodo LED indicador
        piece_present     : out std_logic;    -- Nivel logico estandarizado hacia el clasificador
        start_color_pulse : out std_logic     -- Pulso estroboscopico para inicio de conversion
    );
end entity;

architecture rtl of DetectorPresenciaIR is

    -- Registros de sincronizacion de dos etapas
    signal sync1, sync2 : std_logic := '1';
    signal raw_detect   : std_logic := '0';

    -- Registros para filtro de persistencia temporal
    signal filter_cnt     : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal stable_detect  : std_logic := '0';
    signal last_stable    : std_logic := '0';

begin

    -- -------------------------------------------------------------------------
    -- 1. Etapa de Sincronizacion de Entrada Asincrona
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            sync1 <= '1';
            sync2 <= '1';
        elsif rising_edge(clk) then
            sync1 <= ir_sensor_out;
            sync2 <= sync1;
        end if;
    end process;

    -- Evaluacion de polaridad activa
    raw_detect <= '1' when (sync2 = IR_ACTIVE_LEVEL) else '0';

    -- -------------------------------------------------------------------------
    -- 2. Filtro Digital Integrador y Generador de Pulso de Flanco
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            filter_cnt        <= 0;
            stable_detect     <= '0';
            last_stable       <= '0';
            start_color_pulse <= '0';
        elsif rising_edge(clk) then
            -- Integrador de persistencia
            if raw_detect = stable_detect then
                filter_cnt <= 0;
            else
                if filter_cnt >= DEBOUNCE_CYCLES then
                    stable_detect <= raw_detect;
                    filter_cnt    <= 0;
                else
                    filter_cnt <= filter_cnt + 1;
                end if;
            end if;

            last_stable <= stable_detect;

            -- Generacion de pulso monotiro de 1 ciclo de reloj
            if (stable_detect = '1' and last_stable = '0') then
                start_color_pulse <= '1';
            else
                start_color_pulse <= '0';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- 3. Asignaciones Concurrentes de Salida
    -- -------------------------------------------------------------------------
    presence_led  <= stable_detect;
    piece_present <= stable_detect;

end architecture;
