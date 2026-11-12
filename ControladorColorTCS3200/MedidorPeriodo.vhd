-- ============================================================================
-- Modulo: MedidorPeriodo.vhd
-- Descripcion:
--   Medidor digital de intervalo temporal (periodo T) para trenes de pulsos
--   asincronos provenientes de transductores optoelectronicos (TCS3200).
--
-- Principio de Funcionamiento:
--   1. Sincronizacion de Entrada:
--      Cadena de dos flip-flops tipo D para mitigar metaestabilidad y detector
--      de flanco ascendente (rising_edge_sig).
--   2. Etapa de Estabilizacion Optica (ST_SETTLE):
--      Retardo de SETTLING_CYCLES ciclos de reloj (200 us @ 50 MHz) que asegura
--      el asentamiento termico y optico de la matriz de fotodiodos tras la
--      conmutacion de los filtros S2/S3.
--   3. Base de Tiempo en Microsegundos:
--      Prescaler de modulo 50 (50 ciclos de reloj @ 50 MHz = 1.0 us).
--      El acumulador temporal cycle_cnt registra la duracion entre dos flancos
--      ascendentes consecutivos expresada directamente en microsegundos (us).
--   4. Temporizador de Seguridad (Timeout):
--      Previene bloqueos del sistema en caso de desconexion del sensor o ausencia
--      de pulsos, asignando un valor centinela (9999 us).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MedidorPeriodo is
    generic (
        SETTLING_CYCLES : integer := 10_000;    -- Tiempo de estabilizacion (200 us @ 50 MHz)
        MAX_TIMEOUT     : integer := 5_000_000  -- Limite maximo de espera (100 ms @ 50 MHz)
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;                     -- Reset asincrono activo en bajo ('0')
        start       : in  std_logic;                     -- Pulso estroboscopico de inicio de medicion
        sig_in      : in  std_logic;                     -- Entrada digital del transductor (tcs_out)
        busy        : out std_logic;                     -- Estado ocupado durante adquisicion
        done        : out std_logic;                     -- Pulso de finalizacion de medicion valida
        period_data : out std_logic_vector(23 downto 0)  -- Periodo temporal en microsegundos (us)
    );
end entity;

architecture rtl of MedidorPeriodo is

    -- Etapas de sincronizacion anti-metaestabilidad
    signal sync_stage1 : std_logic := '0';
    signal sync_stage2 : std_logic := '0';
    signal sync_prev   : std_logic := '0';
    signal rising_edge_sig : std_logic;

    -- Estados de la FSM de Medicion Temporal
    type estado_med_t is (
        ST_IDLE,
        ST_SETTLE,
        ST_WAIT_EDGE_1,
        ST_COUNTING,
        ST_DONE
    );
    signal estado_actual : estado_med_t := ST_IDLE;

    signal settle_cnt  : integer range 0 to SETTLING_CYCLES := 0;
    signal prescaler   : integer range 0 to 49 := 0;        -- Base: 50 ciclos @ 50 MHz = 1 us
    signal cycle_cnt   : unsigned(23 downto 0) := (others => '0');
    signal timeout_cnt : integer range 0 to MAX_TIMEOUT := 0;
    signal reg_period  : unsigned(23 downto 0) := (others => '0');

begin

    -- -------------------------------------------------------------------------
    -- Sincronizador de Entrada de Dos Etapas y Detector de Flancos
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            sync_stage1 <= '0';
            sync_stage2 <= '0';
            sync_prev   <= '0';
        elsif rising_edge(clk) then
            sync_stage1 <= sig_in;
            sync_stage2 <= sync_stage1;
            sync_prev   <= sync_stage2;
        end if;
    end process;

    rising_edge_sig <= '1' when (sync_stage2 = '1' and sync_prev = '0') else '0';

    -- -------------------------------------------------------------------------
    -- FSM de Cronometraje y Determinacion de Periodo
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            estado_actual <= ST_IDLE;
            settle_cnt    <= 0;
            prescaler     <= 0;
            cycle_cnt     <= (others => '0');
            timeout_cnt   <= 0;
            reg_period    <= to_unsigned(9999, 24);
            done          <= '0';
            busy          <= '0';
        elsif rising_edge(clk) then
            done <= '0';

            case estado_actual is
                
                when ST_IDLE =>
                    busy <= '0';
                    if start = '1' then
                        busy          <= '1';
                        settle_cnt    <= 0;
                        prescaler     <= 0;
                        timeout_cnt   <= 0;
                        cycle_cnt     <= (others => '0');
                        estado_actual <= ST_SETTLE;
                    end if;

                -- Periodo de reposo para estabilizacion de conmutacion optica
                when ST_SETTLE =>
                    busy <= '1';
                    if settle_cnt >= SETTLING_CYCLES then
                        estado_actual <= ST_WAIT_EDGE_1;
                    else
                        settle_cnt <= settle_cnt + 1;
                    end if;

                -- Captura del primer flanco ascendente de referencia
                when ST_WAIT_EDGE_1 =>
                    busy <= '1';
                    timeout_cnt <= timeout_cnt + 1;
                    if rising_edge_sig = '1' then
                        cycle_cnt     <= (others => '0');
                        prescaler     <= 0;
                        timeout_cnt   <= 0;
                        estado_actual <= ST_COUNTING;
                    elsif timeout_cnt >= MAX_TIMEOUT then
                        reg_period    <= to_unsigned(9999, 24); -- Indicador de desborde/timeout
                        estado_actual <= ST_DONE;
                    end if;

                -- Acumulacion de microsegundos hasta el segundo flanco ascendente
                when ST_COUNTING =>
                    busy <= '1';
                    timeout_cnt <= timeout_cnt + 1;

                    if prescaler >= 49 then
                        prescaler <= 0;
                        if cycle_cnt < 9999 then
                            cycle_cnt <= cycle_cnt + 1;
                        end if;
                    else
                        prescaler <= prescaler + 1;
                    end if;

                    if rising_edge_sig = '1' then
                        reg_period    <= cycle_cnt;
                        estado_actual <= ST_DONE;
                    elsif timeout_cnt >= MAX_TIMEOUT then
                        reg_period    <= to_unsigned(9999, 24);
                        estado_actual <= ST_DONE;
                    end if;

                when ST_DONE =>
                    busy          <= '0';
                    done          <= '1';
                    estado_actual <= ST_IDLE;

                when others =>
                    estado_actual <= ST_IDLE;

            end case;
        end if;
    end process;

    period_data <= std_logic_vector(reg_period);

end architecture;
