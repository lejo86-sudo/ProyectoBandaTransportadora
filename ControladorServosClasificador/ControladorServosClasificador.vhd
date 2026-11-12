-- ============================================================================
-- Modulo: ControladorServosClasificador.vhd
-- Descripcion:
--   Controlador PWM con modulacion trapezoidal (rampa suave) para servomotores
--   estandar de 50 Hz (SG90 / MG90S). Implementa la secuencia temporal de
--   desvio y clasificacion de piezas hacia rampas de descarga.
--
-- Principio de Funcionamiento:
--   1. Base de Tiempo: Genera una referencia temporal periodica de 20 ms (50 Hz)
--      y una base de pulsos de 1 ms para la sincronizacion de temporizadores.
--   2. Modulacion de Pulso con Aceleracion Controlada (Soft Ramp):
--      El ancho de pulso varia progresivamente desde reposo (1.0 ms = 50,000 ciclos)
--      hasta extension completa (2.0 ms = 100,000 ciclos) con paso configurable
--      (RAMP_STEP ciclos/ms), reduciendo picos de corriente e inercias mecanicas.
--   3. Maquinas de Estados Finitos (FSM) Independientes:
--      - Servo 1: Control de desvio para piezas de color Rojo (Rampa 1).
--      - Servo 2: Control de desvio para piezas de color Verde (Rampa 2).
--      - Las piezas de color Azul continuan su trayecto directo hacia la Rampa 3.
--   4. Sincronizacion de Viaje:
--      El conteo de retardo de transporte solo avanza si la banda transportadora
--      se encuentra habilitada (belt_enable = '1'). En caso de activacion manual
--      o banda detenida, el actuador responde de forma inmediata.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ControladorServosClasificador is
    generic (
        CLK_FREQ_HZ       : integer := 50_000_000;
        -- Tiempos de transporte desde estacion de deteccion a rampas (en ms)
        DELAY_SERVO1_MS   : integer := 1050;   -- Tiempo de transporte a Rampa 1 (Servo 1)
        DELAY_SERVO2_MS   : integer := 1750;   -- Tiempo de transporte a Rampa 2 (Servo 2)
        PUSH_HOLD_MS      : integer := 500;    -- Tiempo de retencion en extension completa
        
        -- Parametros PWM a 50 MHz (Periodo = 1,000,000 ciclos = 20 ms)
        SERVO_RETRACT_CYC : integer := 50_000; -- Ancho de pulso en reposo (1.0 ms)
        SERVO_EXTEND_CYC  : integer := 100_000;-- Ancho de pulso en extension (2.0 ms)
        RAMP_STEP         : integer := 250     -- Tasa de variacion de ciclo util (ciclos/ms)
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;                     -- Reset asincrono activo en bajo ('0')
        belt_enable   : in  std_logic;                     -- Senal de habilitacion de marcha de banda
        test_mode     : in  std_logic;                     -- Modo de prueba continuo ('1')
        is_manual_btn : in  std_logic;                     -- Bandera de clasificacion por pulsador manual
        
        -- Interfaz con el subsistema de clasificacion de color
        color_code    : in  std_logic_vector(1 downto 0);  -- "01"=Rojo, "10"=Verde, "11"=Azul
        color_ready   : in  std_logic;                     -- Pulso estroboscopico de clasificacion valida
        
        -- Salidas moduladas por ancho de pulso (PWM) hacia actuadores
        servo1_pwm    : out std_logic;                     -- Senal PWM para Servo 1 (Rojo)
        servo2_pwm    : out std_logic;                     -- Senal PWM para Servo 2 (Verde)
        
        -- Senales de estado hacia monitores e indicadores luminosos
        servo1_busy   : out std_logic;                     -- Estado activo de Servo 1
        servo2_busy   : out std_logic                      -- Estado activo de Servo 2
    );
end entity;

architecture rtl of ControladorServosClasificador is

    constant PERIOD_20MS   : integer := CLK_FREQ_HZ / 50;   -- 1,000,000 ciclos = 20 ms (50 Hz)
    constant TICKS_PER_1MS : integer := CLK_FREQ_HZ / 1000; -- 50,000 ciclos = 1 ms

    -- Contador de periodo PWM principal (20 ms)
    signal pwm_cnt : integer range 0 to PERIOD_20MS := 0;

    -- Generador de pulso de habilitacion de 1 ms
    signal ms_cnt  : integer range 0 to TICKS_PER_1MS := 0;
    signal tick_1ms: std_logic := '0';

    -- Estados de la FSM de control de trayectoria
    type t_servo_state is (IDLE, WAITING_TRAVEL, RAMP_EXTENDING, PUSH_HOLD, RAMP_RETRACTING);
    signal state_s1 : t_servo_state := IDLE;
    signal state_s2 : t_servo_state := IDLE;

    -- Temporizadores discretos de transporte y retencion (en ms)
    signal timer_travel1 : integer range 0 to 10_000 := 0;
    signal timer_hold1   : integer range 0 to 2_000  := 0;
    signal timer_travel2 : integer range 0 to 10_000 := 0;
    signal timer_hold2   : integer range 0 to 2_000  := 0;

    -- Temporizador para secuencia de diagnostico/prueba
    signal test_timer_ms : integer range 0 to 4_000 := 0;

    -- Registros dinamicos de ancho de pulso activo
    signal width_s1 : integer range 0 to PERIOD_20MS := SERVO_RETRACT_CYC;
    signal width_s2 : integer range 0 to PERIOD_20MS := SERVO_RETRACT_CYC;

begin

    -- -------------------------------------------------------------------------
    -- 1. Divisor de Reloj para Base de Tiempo de 1 ms
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            ms_cnt   <= 0;
            tick_1ms <= '0';
        elsif rising_edge(clk) then
            if ms_cnt >= TICKS_PER_1MS - 1 then
                ms_cnt   <= 0;
                tick_1ms <= '1';
            else
                ms_cnt   <= ms_cnt + 1;
                tick_1ms <= '0';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- 2. Modulador PWM Periodico a 50 Hz (Base de 20 ms)
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            pwm_cnt <= 0;
        elsif rising_edge(clk) then
            if pwm_cnt >= PERIOD_20MS - 1 then
                pwm_cnt <= 0;
            else
                pwm_cnt <= pwm_cnt + 1;
            end if;
        end if;
    end process;

    -- Comparadores de coincidencia para generacion de forma de onda PWM
    servo1_pwm <= '1' when pwm_cnt < width_s1 else '0';
    servo2_pwm <= '1' when pwm_cnt < width_s2 else '0';

    -- -------------------------------------------------------------------------
    -- 3. Maquinas de Estados Finitos para Trayectoria de Actuadores
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            state_s1      <= IDLE;
            state_s2      <= IDLE;
            width_s1      <= SERVO_RETRACT_CYC;
            width_s2      <= SERVO_RETRACT_CYC;
            timer_travel1 <= 0;
            timer_hold1   <= 0;
            timer_travel2 <= 0;
            timer_hold2   <= 0;
            test_timer_ms <= 0;
            servo1_busy   <= '0';
            servo2_busy   <= '0';

        elsif rising_edge(clk) then

            -- Modo de Diagnostico / Prueba Continua
            if test_mode = '1' then
                if tick_1ms = '1' then
                    if test_timer_ms >= 3000 then
                        test_timer_ms <= 0;
                    else
                        test_timer_ms <= test_timer_ms + 1;
                    end if;
                end if;

                -- Secuencia de prueba Servo 1
                if test_timer_ms < 600 then
                    width_s1    <= SERVO_EXTEND_CYC;
                    servo1_busy <= '1';
                else
                    width_s1    <= SERVO_RETRACT_CYC;
                    servo1_busy <= '0';
                end if;

                -- Secuencia de prueba Servo 2
                if test_timer_ms >= 1500 and test_timer_ms < 2100 then
                    width_s2    <= SERVO_EXTEND_CYC;
                    servo2_busy <= '1';
                else
                    width_s2    <= SERVO_RETRACT_CYC;
                    servo2_busy <= '0';
                end if;

            -- Modo de Operacion Normal: Clasificacion con Rampa Trapezoidal
            else
                test_timer_ms <= 0;

                -- -------------------------------------------------------------
                -- FSM SERVO 1: Desvio de Piezas Color Rojo (Rampa 1)
                -- -------------------------------------------------------------
                case state_s1 is
                    when IDLE =>
                        width_s1    <= SERVO_RETRACT_CYC;
                        servo1_busy <= '0';
                        if color_ready = '1' and color_code = "01" then
                            servo1_busy <= '1';
                            if is_manual_btn = '1' or belt_enable = '0' then
                                -- Activacion inmediata bajo prueba estatica o pulsador manual
                                state_s1 <= RAMP_EXTENDING;
                            else
                                -- Sincronizacion de retardo de transporte dinamico
                                timer_travel1 <= 0;
                                state_s1      <= WAITING_TRAVEL;
                            end if;
                        end if;

                    when WAITING_TRAVEL =>
                        width_s1    <= SERVO_RETRACT_CYC;
                        servo1_busy <= '1';
                        if tick_1ms = '1' then
                            if belt_enable = '1' then
                                if timer_travel1 >= DELAY_SERVO1_MS then
                                    state_s1 <= RAMP_EXTENDING;
                                else
                                    timer_travel1 <= timer_travel1 + 1;
                                end if;
                            end if;
                        end if;

                    when RAMP_EXTENDING =>
                        servo1_busy <= '1';
                        if tick_1ms = '1' then
                            if width_s1 + RAMP_STEP >= SERVO_EXTEND_CYC then
                                width_s1    <= SERVO_EXTEND_CYC;
                                timer_hold1 <= 0;
                                state_s1    <= PUSH_HOLD;
                            else
                                width_s1 <= width_s1 + RAMP_STEP;
                            end if;
                        end if;

                    when PUSH_HOLD =>
                        width_s1    <= SERVO_EXTEND_CYC;
                        servo1_busy <= '1';
                        if tick_1ms = '1' then
                            if timer_hold1 >= PUSH_HOLD_MS then
                                state_s1 <= RAMP_RETRACTING;
                            else
                                timer_hold1 <= timer_hold1 + 1;
                            end if;
                        end if;

                    when RAMP_RETRACTING =>
                        servo1_busy <= '1';
                        if tick_1ms = '1' then
                            if width_s1 - RAMP_STEP <= SERVO_RETRACT_CYC then
                                width_s1 <= SERVO_RETRACT_CYC;
                                state_s1 <= IDLE;
                            else
                                width_s1 <= width_s1 - RAMP_STEP;
                            end if;
                        end if;

                    when others =>
                        state_s1 <= IDLE;
                end case;

                -- -------------------------------------------------------------
                -- FSM SERVO 2: Desvio de Piezas Color Verde (Rampa 2)
                -- -------------------------------------------------------------
                case state_s2 is
                    when IDLE =>
                        width_s2    <= SERVO_RETRACT_CYC;
                        servo2_busy <= '0';
                        if color_ready = '1' and color_code = "10" then
                            servo2_busy <= '1';
                            if is_manual_btn = '1' or belt_enable = '0' then
                                -- Activacion inmediata bajo prueba estatica o pulsador manual
                                state_s2 <= RAMP_EXTENDING;
                            else
                                -- Sincronizacion de retardo de transporte dinamico
                                timer_travel2 <= 0;
                                state_s2      <= WAITING_TRAVEL;
                            end if;
                        end if;

                    when WAITING_TRAVEL =>
                        width_s2    <= SERVO_RETRACT_CYC;
                        servo2_busy <= '1';
                        if tick_1ms = '1' then
                            if belt_enable = '1' then
                                if timer_travel2 >= DELAY_SERVO2_MS then
                                    state_s2 <= RAMP_EXTENDING;
                                else
                                    timer_travel2 <= timer_travel2 + 1;
                                end if;
                            end if;
                        end if;

                    when RAMP_EXTENDING =>
                        servo2_busy <= '1';
                        if tick_1ms = '1' then
                            if width_s2 + RAMP_STEP >= SERVO_EXTEND_CYC then
                                width_s2    <= SERVO_EXTEND_CYC;
                                timer_hold2 <= 0;
                                state_s2    <= PUSH_HOLD;
                            else
                                width_s2 <= width_s2 + RAMP_STEP;
                            end if;
                        end if;

                    when PUSH_HOLD =>
                        width_s2    <= SERVO_EXTEND_CYC;
                        servo2_busy <= '1';
                        if tick_1ms = '1' then
                            if timer_hold2 >= PUSH_HOLD_MS then
                                state_s2 <= RAMP_RETRACTING;
                            else
                                timer_hold2 <= timer_hold2 + 1;
                            end if;
                        end if;

                    when RAMP_RETRACTING =>
                        servo2_busy <= '1';
                        if tick_1ms = '1' then
                            if width_s2 - RAMP_STEP <= SERVO_RETRACT_CYC then
                                width_s2 <= SERVO_RETRACT_CYC;
                                state_s2 <= IDLE;
                            else
                                width_s2 <= width_s2 - RAMP_STEP;
                            end if;
                        end if;

                    when others =>
                        state_s2 <= IDLE;
                end case;

            end if;
        end if;
    end process;

end architecture;
