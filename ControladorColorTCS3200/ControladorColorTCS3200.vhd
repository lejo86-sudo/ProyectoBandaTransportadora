-- ============================================================================
-- Modulo: ControladorColorTCS3200.vhd
-- Descripcion:
--   Controlador secuencial y clasificador optoelectronico para el sensor de
--   color TCS3200 (matriz de fotodiodos con conversion luz a frecuencia).
--
-- Principio de Operacion:
--   1. Multiplexacion Espectral (Lineas S2 y S3):
--      - Filtro Rojo:  S2 = '0', S3 = '0'
--      - Filtro Verde: S2 = '1', S3 = '1'
--      - Filtro Azul:  S2 = '0', S3 = '1'
--      - Escala de Frecuencia (S0='1', S1='0'): 20% de f_max (~100-120 kHz max)
--   2. Medicion de Periodo:
--      El modulo subordinado MedidorPeriodo mide el periodo de la senal generada
--      por el sensor para cada componente espectral en microsegundos (us).
--      Una mayor radiancia monocromatica produce una mayor frecuencia y, por ende,
--      un menor periodo temporal T.
--   3. Criterios de Discriminacion y Clasificacion Espectral:
--      - Umbral de Base / Descarte (Ausencia de Pieza / Radiacion Ambiente):
--        Suma(T_R + T_G + T_B) >= 800 us  O  (T_R >= 300 us, T_G >= 350 us, T_B >= 350 us).
--      - Clasificacion Rojo ("01"):
--        T_R <= 125 us  Y  (10 * T_G > 13 * T_R)  Y  (T_R < T_B).
--      - Clasificacion Azul ("11"):
--        T_B <= 115 us  Y  (T_B < T_R)  Y  (T_B < T_G).
--      - Clasificacion Verde ("10"):
--        (T_G < T_R)  Y  (T_G < T_B)  Y  (T_R >= 135 us).
--   4. Modo de Diagnostico (diag_mode = '1'):
--      Permite la adquisicion ciclica y continua de los periodos espectrales
--      para su monitoreo en displays de 7 segmentos.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ControladorColorTCS3200 is
    generic (
        CLK_FREQ_HZ     : integer := 50_000_000; -- Frecuencia de reloj del sistema (50 MHz)
        SETTLING_CYCLES : integer := 10_000      -- Tiempo de estabilizacion de fotodiodos (200 us @ 50 MHz)
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;                     -- Reset asincrono activo en bajo ('0')
        start         : in  std_logic;                     -- Pulso de inicio de conversion (disparo IR)
        piece_present : in  std_logic;                     -- Nivel logico de presencia de pieza ('1'=presente)
        diag_mode     : in  std_logic;                     -- Modo de medicion continua para diagnostico
        tcs_out       : in  std_logic;                     -- Tren de pulsos proveniente del sensor TCS3200
        
        -- Lineas de seleccion de escala y filtro optico hacia TCS3200
        S0            : out std_logic;                     -- Seleccion de escala de frecuencia (S0='1', S1='0' -> 20%)
        S1            : out std_logic;
        S2            : out std_logic;                     -- Seleccion de matriz de fotodiodos espectrales
        S3            : out std_logic;
        
        -- Salidas decodificadas de clasificacion
        led_R         : out std_logic;                     -- Indicador de deteccion espectral Rojo
        led_G         : out std_logic;                     -- Indicador de deteccion espectral Verde
        led_B         : out std_logic;                     -- Indicador de deteccion espectral Azul
        color_code    : out std_logic_vector(1 downto 0);  -- Codigo de color: "01"=Rojo, "10"=Verde, "11"=Azul
        color_ready   : out std_logic;                     -- Pulso de sincronizacion de dato valido
        busy          : out std_logic;                     -- Bandera de proceso de conversion en curso
        
        -- Vectores de diagnostico espectral (periodo medido en microsegundos)
        diag_r        : out std_logic_vector(15 downto 0); -- Periodo componente Roja en us
        diag_g        : out std_logic_vector(15 downto 0); -- Periodo componente Verde en us
        diag_b        : out std_logic_vector(15 downto 0)  -- Periodo componente Azul en us
    );
end entity;

architecture rtl of ControladorColorTCS3200 is

    component MedidorPeriodo is
        generic (
            SETTLING_CYCLES : integer := 10_000;
            MAX_TIMEOUT     : integer := 5_000_000
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            start       : in  std_logic;
            sig_in      : in  std_logic;
            busy        : out std_logic;
            done        : out std_logic;
            period_data : out std_logic_vector(23 downto 0)
        );
    end component;

    -- Estados de la FSM de Adquisicion Espectral
    type estado_color_t is (
        ST_IDLE,
        ST_FILTRO_ROJO,
        ST_FILTRO_VERDE,
        ST_FILTRO_AZUL,
        ST_DECISION,
        ST_SALIDA
    );

    signal estado_actual : estado_color_t := ST_IDLE;
    signal sub_fase      : std_logic := '0';

    -- Senales de control para el submodulo MedidorPeriodo
    signal start_med   : std_logic := '0';
    signal done_med    : std_logic := '0';
    signal busy_med    : std_logic := '0';
    signal period_data : std_logic_vector(23 downto 0) := (others => '0');

    -- Registros de captura de periodo por canal (microsegundos)
    signal reg_per_R   : unsigned(23 downto 0) := to_unsigned(9999, 24);
    signal reg_per_G   : unsigned(23 downto 0) := to_unsigned(9999, 24);
    signal reg_per_B   : unsigned(23 downto 0) := to_unsigned(9999, 24);

    signal reg_leds    : std_logic_vector(2 downto 0) := "000";
    signal reg_code    : std_logic_vector(1 downto 0) := "00";

begin

    -- Configuracion estatica de escala de frecuencia al 20%
    S0 <= '1';
    S1 <= '0';

    -- Instanciacion del modulo medidor de periodo de senal
    U_MEDIDOR: MedidorPeriodo
        generic map (
            SETTLING_CYCLES => SETTLING_CYCLES,
            MAX_TIMEOUT     => CLK_FREQ_HZ / 10 -- Limite temporal maximo: 100 ms
        )
        port map (
            clk         => clk,
            rst         => rst,
            start       => start_med,
            sig_in      => tcs_out,
            busy        => busy_med,
            done        => done_med,
            period_data => period_data
        );

    -- Proceso secuencial principal: Control FSM y Algoritmo de Decision
    process(clk, rst)
        variable sum_tot : unsigned(23 downto 0);
        variable v_x10   : unsigned(23 downto 0);
        variable r_x13   : unsigned(23 downto 0);
    begin
        if rst = '0' then
            estado_actual <= ST_IDLE;
            sub_fase      <= '0';
            start_med     <= '0';
            reg_per_R     <= to_unsigned(9999, 24);
            reg_per_G     <= to_unsigned(9999, 24);
            reg_per_B     <= to_unsigned(9999, 24);
            reg_leds      <= "000";
            reg_code      <= "00";
            color_ready   <= '0';
            busy          <= '0';
            S2            <= '0';
            S3            <= '0';

        elsif rising_edge(clk) then
            start_med   <= '0';
            color_ready <= '0';

            case estado_actual is

                -- Estado 0: Reposo y espera de condiciones de disparo
                when ST_IDLE =>
                    busy     <= '0';
                    S2       <= '0';
                    S3       <= '0';

                    if (start = '1') or (diag_mode = '1') then
                        busy          <= '1';
                        sub_fase      <= '0';
                        estado_actual <= ST_FILTRO_ROJO;
                    end if;

                -- Estado 1: Medicion de Canal Rojo (S2='0', S3='0')
                when ST_FILTRO_ROJO =>
                    busy <= '1';
                    S2   <= '0';
                    S3   <= '0';

                    if sub_fase = '0' then
                        start_med <= '1';
                        sub_fase  <= '1';
                    else
                        if done_med = '1' then
                            reg_per_R     <= unsigned(period_data);
                            sub_fase      <= '0';
                            estado_actual <= ST_FILTRO_VERDE;
                        end if;
                    end if;

                -- Estado 2: Medicion de Canal Verde (S2='1', S3='1')
                when ST_FILTRO_VERDE =>
                    busy <= '1';
                    S2   <= '1';
                    S3   <= '1';

                    if sub_fase = '0' then
                        start_med <= '1';
                        sub_fase  <= '1';
                    else
                        if done_med = '1' then
                            reg_per_G     <= unsigned(period_data);
                            sub_fase      <= '0';
                            estado_actual <= ST_FILTRO_AZUL;
                        end if;
                    end if;

                -- Estado 3: Medicion de Canal Azul (S2='0', S3='1')
                when ST_FILTRO_AZUL =>
                    busy <= '1';
                    S2   <= '0';
                    S3   <= '1';

                    if sub_fase = '0' then
                        start_med <= '1';
                        sub_fase  <= '1';
                    else
                        if done_med = '1' then
                            reg_per_B     <= unsigned(period_data);
                            sub_fase      <= '0';
                            estado_actual <= ST_DECISION;
                        end if;
                    end if;

                -- Estado 4: Evaluacion de Umbrales Espectrales y Decision
                when ST_DECISION =>
                    busy <= '1';

                    sum_tot := reg_per_R + reg_per_G + reg_per_B;
                    v_x10   := resize(reg_per_G * 10, 24);
                    r_x13   := resize(reg_per_R * 13, 24);

                    -- Condicion A: Ausencia de pieza valida (deteccion optica infrarroja inactiva)
                    if (diag_mode = '0' and piece_present = '0') or (reg_per_R = 0) then
                        reg_leds    <= "000";
                        reg_code    <= "00";
                        color_ready <= '0';

                    -- Condicion B: Filtro de dispersion luminosa ambiental / superficie de transporte
                    elsif (sum_tot >= 800) or (reg_per_R >= 300) or (reg_per_G >= 350) or (reg_per_B >= 350) then
                        reg_leds    <= "000";
                        reg_code    <= "00";
                        color_ready <= '0';

                    -- Condicion C: Discriminacion de Pieza Roja ("01")
                    elsif (reg_per_R <= 125) and (v_x10 > r_x13) and (reg_per_R < reg_per_B) then
                        reg_leds <= "100";
                        reg_code <= "01";
                        if diag_mode = '0' then color_ready <= '1'; else color_ready <= '0'; end if;

                    -- Condicion D: Discriminacion de Pieza Azul ("11")
                    elsif (reg_per_B <= 115) and (reg_per_B < reg_per_R) and (reg_per_B < reg_per_G) then
                        reg_leds <= "001";
                        reg_code <= "11";
                        if diag_mode = '0' then color_ready <= '1'; else color_ready <= '0'; end if;

                    -- Condicion E: Discriminacion de Pieza Verde ("10")
                    elsif (reg_per_G < reg_per_R) and (reg_per_G < reg_per_B) and (reg_per_R >= 135) then
                        reg_leds <= "010";
                        reg_code <= "10";
                        if diag_mode = '0' then color_ready <= '1'; else color_ready <= '0'; end if;

                    -- Condicion F: Descarte / No clasificado
                    else
                        reg_leds    <= "000";
                        reg_code    <= "00";
                        color_ready <= '0';
                    end if;

                    estado_actual <= ST_SALIDA;

                -- Estado 5: Retencion y sincronizacion de salida
                when ST_SALIDA =>
                    busy <= '0';
                    if diag_mode = '1' then
                        -- Retorno inmediato para muestreo continuo en modo diagnostico
                        estado_actual <= ST_IDLE;
                    elsif piece_present = '0' then
                        -- Espera de liberacion de la zona de deteccion para la siguiente pieza
                        reg_leds      <= "000";
                        estado_actual <= ST_IDLE;
                    end if;

                when others =>
                    estado_actual <= ST_IDLE;

            end case;
        end if;
    end process;

    -- Asignacion concurrente de salidas
    led_R      <= reg_leds(2);
    led_G      <= reg_leds(1);
    led_B      <= reg_leds(0);
    color_code <= reg_code;

    -- Salidas de diagnostico en microsegundos (truncadas a 16 bits)
    diag_r <= std_logic_vector(reg_per_R(15 downto 0));
    diag_g <= std_logic_vector(reg_per_G(15 downto 0));
    diag_b <= std_logic_vector(reg_per_B(15 downto 0));

end architecture;
