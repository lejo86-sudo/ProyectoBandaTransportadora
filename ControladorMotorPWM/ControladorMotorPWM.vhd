-- ============================================================================
-- Modulo: ControladorMotorPWM.vhd
-- Descripcion:
--   Modulador de Ancho de Pulso (PWM) y controlador de potencia para el motor
--   de traccion de la banda transportadora (interfaz con puente H L293D / L298N).
--
-- Principio de Operacion:
--   1. Base de Frecuencia PWM:
--      Configurada a PWM_FREQ_HZ = 200 Hz (Periodo T = 5 ms = 250,000 ciclos @ 50 MHz),
--      optimizada para la respuesta en frecuencia inductiva de micromotores DC.
--   2. Modulacion de Ciclo de Trabajo (Duty Cycle):
--      - Nivel "00" (Velocidad 0):  40% (100,000 ciclos) - Marcha baja.
--      - Nivel "01" (Velocidad 1):  60% (150,000 ciclos) - Marcha media.
--      - Nivel "10" (Velocidad 2):  80% (200,000 ciclos) - Marcha media-alta.
--      - Nivel "11" (Velocidad 3): 100% (250,000 ciclos) - Conduccion continua DC.
--   3. Logica de Sentido de Giro y Paro:
--      - Habilitado (enable_sw = '1'): motor_in1 = PWM, motor_in2 = '0' (giro directo).
--      - Deshabilitado (enable_sw = '0'): motor_in1 = '0', motor_in2 = '0' (freno pasivo).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ControladorMotorPWM is
    generic (
        CLK_FREQ_HZ : integer := 50_000_000;
        PWM_FREQ_HZ : integer := 200           -- Frecuencia portadora PWM (200 Hz)
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;                    -- Reset asincrono activo en bajo ('0')
        enable_sw  : in  std_logic;                    -- Entrada de marcha/parada
        vel_state  : in  std_logic_vector(1 downto 0); -- Selector binario de velocidad (0 a 3)
        
        -- Interfaz digital hacia el driver de potencia
        motor_pwm  : out std_logic;                    -- Salida PWM modulada
        motor_in1  : out std_logic;                    -- Linea de control directo IN1
        motor_in2  : out std_logic                     -- Linea de control a referencia IN2 ('0')
    );
end entity;

architecture rtl of ControladorMotorPWM is

    constant PERIOD_CYCLES : integer := CLK_FREQ_HZ / PWM_FREQ_HZ; -- 250,000 ciclos = 5 ms

    signal pwm_cnt   : integer range 0 to PERIOD_CYCLES := 0;
    signal duty_limit: integer range 0 to PERIOD_CYCLES := PERIOD_CYCLES;
    signal pwm_raw   : std_logic := '1';

begin

    -- -------------------------------------------------------------------------
    -- Decodificacion de Ciclo Util segun Nivel de Velocidad
    -- -------------------------------------------------------------------------
    process(vel_state)
    begin
        case vel_state is
            when "00" => duty_limit <= 100_000;      -- 40% Ciclo de trabajo
            when "01" => duty_limit <= 150_000;      -- 60% Ciclo de trabajo
            when "10" => duty_limit <= 200_000;      -- 80% Ciclo de trabajo
            when "11" => duty_limit <= PERIOD_CYCLES; -- 100% Nivel logico continuo
            when others => duty_limit <= PERIOD_CYCLES;
        end case;
    end process;

    -- -------------------------------------------------------------------------
    -- Generador Concurrente de Onda PWM
    -- -------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '0' then
            pwm_cnt <= 0;
            pwm_raw <= '1';
        elsif rising_edge(clk) then
            if pwm_cnt >= PERIOD_CYCLES - 1 then
                pwm_cnt <= 0;
            else
                pwm_cnt <= pwm_cnt + 1;
            end if;

            if duty_limit = PERIOD_CYCLES then
                pwm_raw <= '1';
            elsif pwm_cnt < duty_limit then
                pwm_raw <= '1';
            else
                pwm_raw <= '0';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Conmutacion de Potencia y Marcha/Parada
    -- -------------------------------------------------------------------------
    process(enable_sw, pwm_raw)
    begin
        if enable_sw = '1' then
            motor_pwm <= pwm_raw;
            motor_in1 <= pwm_raw;
            motor_in2 <= '0';
        else
            motor_pwm <= '0';
            motor_in1 <= '0';
            motor_in2 <= '0';
        end if;
    end process;

end architecture;
