-- ============================================================================
-- Modulo: SistemaClasificadorColor.vhd
-- Descripcion:
--   Entidad estructural que integra el conjunto de transductores sensoriales
--   de la estacion de clasificacion:
--   1. Sensor Infrarrojo de Base (DetectorPresenciaIR):
--      Detecta la aproximacion fisica de cualquier pieza en la linea de ensamble.
--   2. Sensor Infrarrojo Superior (ir_size_out):
--      Realiza la discriminacion geometrica por altura de pieza:
--      '0' = Tamano pequeno (haz superior libre).
--      '1' = Tamano grande (haz superior interrumpido).
--   3. Sensor Optoelectronico de Color (ControladorColorTCS3200):
--      Adquisicion y discriminacion espectral (Rojo, Verde, Azul).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity SistemaClasificadorColor is
    generic (
        CLK_FREQ_HZ     : integer   := 50_000_000;
        SETTLING_CYCLES : integer   := 10_000;
        DEBOUNCE_CYCLES : integer   := 50_000;
        IR_ACTIVE_LEVEL : std_logic := '0'
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;                     -- Reset asincrono activo en bajo ('0')
        diag_mode     : in  std_logic;                     -- Habilitacion de diagnostico en tiempo real
        
        -- Entradas fisicas desde transductores
        ir_sensor_out : in  std_logic;                     -- Sensor IR 1: Presencia base en transportador
        ir_size_out   : in  std_logic;                     -- Sensor IR 2: Criterio optico de altura/tamano
        tcs_out       : in  std_logic;                     -- Tren de frecuencia del sensor TCS3200
        
        -- Lineas de seleccion hacia TCS3200
        S0            : out std_logic;
        S1            : out std_logic;
        S2            : out std_logic;
        S3            : out std_logic;
        
        -- Salidas clasificadas hacia subsistemas de control y actuacion
        color_code    : out std_logic_vector(1 downto 0);  -- "01"=Rojo, "10"=Verde, "11"=Azul
        color_ready   : out std_logic;                     -- Pulso estroboscopico de clasificacion completada
        size_code     : out std_logic;                     -- '0' = Pequeno, '1' = Grande
        presence_led  : out std_logic;                     -- Monitor de presencia base
        size_led      : out std_logic;                     -- Monitor de presencia por altura
        
        -- Bus de diagnostico espectral hacia multiplexor de visualizacion (en microsegundos)
        diag_r        : out std_logic_vector(15 downto 0);
        diag_g        : out std_logic_vector(15 downto 0);
        diag_b        : out std_logic_vector(15 downto 0)
    );
end entity;

architecture Estructural of SistemaClasificadorColor is

    component DetectorPresenciaIR is
        generic (
            IR_ACTIVE_LEVEL : std_logic := '0';
            DEBOUNCE_CYCLES : integer   := 50_000
        );
        port (
            clk               : in  std_logic;
            rst               : in  std_logic;
            ir_sensor_out     : in  std_logic;
            presence_led      : out std_logic;
            piece_present     : out std_logic;
            start_color_pulse : out std_logic
        );
    end component;

    component ControladorColorTCS3200 is
        generic (
            CLK_FREQ_HZ     : integer := 50_000_000;
            SETTLING_CYCLES : integer := 10_000
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            start         : in  std_logic;
            piece_present : in  std_logic;
            diag_mode     : in  std_logic;
            tcs_out       : in  std_logic;
            S0            : out std_logic;
            S1            : out std_logic;
            S2            : out std_logic;
            S3            : out std_logic;
            led_R         : out std_logic;
            led_G         : out std_logic;
            led_B         : out std_logic;
            color_code    : out std_logic_vector(1 downto 0);
            color_ready   : out std_logic;
            busy          : out std_logic;
            diag_r        : out std_logic_vector(15 downto 0);
            diag_g        : out std_logic_vector(15 downto 0);
            diag_b        : out std_logic_vector(15 downto 0)
        );
    end component;

    signal piece_present_sig : std_logic;
    signal start_color_sig   : std_logic;

    -- Sincronizacion y filtrado del sensor optico de altura (Tamano)
    signal size_sync1, size_sync2 : std_logic := '1';
    signal size_raw_detect        : std_logic := '0';
    signal size_filter_cnt        : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal size_stable_detect     : std_logic := '0';
    signal latched_large          : std_logic := '0';

begin

    -- -------------------------------------------------------------------------
    -- Sincronizacion, Acondicionamiento y Retencion de Tamano (Sensor IR 2)
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            size_sync1         <= '1';
            size_sync2         <= '1';
            size_raw_detect    <= '0';
            size_filter_cnt    <= 0;
            size_stable_detect <= '0';
            latched_large      <= '0';
        elsif rising_edge(clk) then
            -- Sincronizador de 2 etapas
            size_sync1 <= ir_size_out;
            size_sync2 <= size_sync1;

            -- Evaluacion de polaridad logica activa
            if size_sync2 = IR_ACTIVE_LEVEL then
                size_raw_detect <= '1';
            else
                size_raw_detect <= '0';
            end if;

            -- Filtro digital integrador de transitorios
            if size_raw_detect /= size_stable_detect then
                if size_filter_cnt >= DEBOUNCE_CYCLES - 1 then
                    size_filter_cnt    <= 0;
                    size_stable_detect <= size_raw_detect;
                else
                    size_filter_cnt    <= size_filter_cnt + 1;
                end if;
            else
                size_filter_cnt <= 0;
            end if;

            -- Registro con retencion de tamano durante el intervalo de transito
            if size_raw_detect = '1' or size_stable_detect = '1' then
                latched_large <= '1';
            elsif piece_present_sig = '0' and size_raw_detect = '0' then
                latched_large <= '0';
            end if;
        end if;
    end process;

    size_led  <= size_stable_detect or size_raw_detect;
    size_code <= latched_large or size_stable_detect or size_raw_detect;

    -- -------------------------------------------------------------------------
    -- Instanciacion de Submodulos Estructurales
    -- -------------------------------------------------------------------------
    SUBSISTEMA_PRESENCIA_IR: DetectorPresenciaIR
        generic map (
            IR_ACTIVE_LEVEL => IR_ACTIVE_LEVEL,
            DEBOUNCE_CYCLES => DEBOUNCE_CYCLES
        )
        port map (
            clk               => clk,
            rst               => rst,
            ir_sensor_out     => ir_sensor_out,
            presence_led      => presence_led,
            piece_present     => piece_present_sig,
            start_color_pulse => start_color_sig
        );

    SUBSISTEMA_COLOR_TCS: ControladorColorTCS3200
        generic map (
            CLK_FREQ_HZ     => CLK_FREQ_HZ,
            SETTLING_CYCLES => SETTLING_CYCLES
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start_color_sig,
            piece_present => piece_present_sig,
            diag_mode     => diag_mode,
            tcs_out       => tcs_out,
            S0            => S0,
            S1            => S1,
            S2            => S2,
            S3            => S3,
            led_R         => open,
            led_G         => open,
            led_B         => open,
            color_code    => color_code,
            color_ready   => color_ready,
            busy          => open,
            diag_r        => diag_r,
            diag_g        => diag_g,
            diag_b        => diag_b
        );

end architecture;
