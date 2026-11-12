-- ============================================================================
-- Proyecto: Sistema Automatizado de Clasificacion en Banda Transportadora
-- Modulo:   SystemAlfa.vhd (Top-Level del Sistema)
-- Tarjeta:  Terasic DE0 (FPGA Cyclone III EP3C16F484C6)
-- Descripcion:
--   Unidad integradora de nivel superior para la clasificacion automatica
--   de piezas por color y tamano en una linea de transporte continuo.
--
-- Subsistemas Integrados:
--   1. Transduccion Optica y Espectral:
--      - Sensor de presencia base por infrarrojos (DetectorPresenciaIR).
--      - Sensor de discriminacion geometrica por altura (haz IR superior).
--      - Sensor optoelectronico de conversion luz a frecuencia (TCS3200).
--   2. Modulacion y Potencia de Traccion:
--      - Regulador de velocidad digital (ControladorFrecuencia).
--      - Modulador PWM de 200 Hz para puente H L293D / L298N (ControladorMotorPWM).
--   3. Actuacion y Desvio Mecanico:
--      - Controlador PWM de 50 Hz con rampa suave (ControladorServosClasificador)
--        para desvio a rampas mediante servomotores.
--   4. Logica de Clasificacion e Inventario:
--      - Enrutador central sincrono (EnrutadorCentral).
--      - Tres bancos independientes de conteo y retencion (BancoColor).
--      - Acumuladores de gran total (unidades y decenas BCD).
--   5. Interfaz de Usuario y Diagnostico:
--      - Multiplexor de visualizacion de 4 displays de 7 segmentos (MultiplexorVistas).
--      - Arreglo de diodos LED (LEDG) para monitoreo en tiempo real.
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity SystemAlfa is
    port (
        -- Senales de Reloj y Control Manual de Placa
        Clock         : in  std_logic;                     -- Reloj maestro del oscilador (50 MHz, PIN_G21)
        Reset         : in  std_logic;                     -- Pulsador de reset general (activo en bajo, PIN_J6)
        SW_Modo       : in  std_logic_vector(1 downto 0);  -- Selector de modo de operacion (SW9, SW8)
        SW_Color      : in  std_logic_vector(1 downto 0);  -- Selector manual de color (SW1, SW0)
        SW_Tamano     : in  std_logic;                     -- Selector manual de tamano (SW2)
        SW_Vista      : in  std_logic_vector(1 downto 0);  -- Selector de sub-vista de visualizacion (SW5, SW4)
        SW_Banda      : in  std_logic;                     -- Habilitador de traccion de la banda (SW6, PIN_H7)
        BTN_Contar    : in  std_logic;                     -- Pulsador manual de incremento (BUTTON0, PIN_H2)
        BTN_FrecUp    : in  std_logic;                     -- Pulsador incremento de velocidad (BUTTON1, PIN_F1)
        BTN_FrecDown  : in  std_logic;                     -- Pulsador decremento de velocidad (BUTTON2, PIN_G3)

        -- Interfaz de Visualizacion en Placa
        HEX0          : out std_logic_vector(6 downto 0);  -- Visualizador 7 segmentos digito 0 (Unidades)
        HEX1          : out std_logic_vector(6 downto 0);  -- Visualizador 7 segmentos digito 1 (Decenas)
        HEX2          : out std_logic_vector(6 downto 0);  -- Visualizador 7 segmentos digito 2 (Centenas)
        HEX3          : out std_logic_vector(6 downto 0);  -- Visualizador 7 segmentos digito 3 (Miles/Modo)
        DP0           : out std_logic;                     -- Punto decimal HEX0
        DP1           : out std_logic;                     -- Punto decimal HEX1
        DP2           : out std_logic;                     -- Punto decimal HEX2
        DP3           : out std_logic;                     -- Punto decimal HEX3
        LEDG          : out std_logic_vector(9 downto 0);  -- Arreglo de 10 diodos LED verdes de diagnostico

        -- Interfaz con Sensores Externos (Header J4 / GPIO 0)
        ir_sensor_out : in  std_logic;                     -- Sensor IR 1: Presencia base (J4 Pin 1, PIN_AB12)
        ir_size_out   : in  std_logic;                     -- Sensor IR 2: Altura de pieza (J4 Pin 5, PIN_AA15)
        tcs_out       : in  std_logic;                     -- Salida de frecuencia TCS3200 (J4 Pin 3, PIN_AA12)
        S0            : out std_logic;                     -- Seleccion escala TCS3200 (J4 Pin 2, PIN_AB16)
        S1            : out std_logic;                     -- Seleccion escala TCS3200 (J4 Pin 4, PIN_AA16)
        S2            : out std_logic;                     -- Seleccion filtro TCS3200 (J4 Pin 6, PIN_AB15)
        S3            : out std_logic;                     -- Seleccion filtro TCS3200 (J4 Pin 8, PIN_AB14)

        -- Interfaz de Potencia Puente H (Traccion de Banda)
        motor_pwm     : out std_logic;                     -- Modulacion PWM hacia driver (J4 Pin 9, PIN_AB13)
        motor_in1     : out std_logic;                     -- Senal de control de direccion IN1 (J4 Pin 10, PIN_AA13)
        motor_in2     : out std_logic;                     -- Referencia de nivel bajo IN2 (J4 Pin 13, PIN_AB10)

        -- Interfaz de Control de Actuadores (Servomotores Clasificadores)
        servo1_pwm    : out std_logic;                     -- Senal PWM Servo 1 (Rojo / Rampa 1, J4 Pin 7, PIN_AA14)
        servo2_pwm    : out std_logic                      -- Senal PWM Servo 2 (Verde / Rampa 2, J4 Pin 14, PIN_AA10)
    );
end entity;

architecture Estructural of SystemAlfa is

    -- -------------------------------------------------------------------------
    -- Declaraciones de Componentes Modulares
    -- -------------------------------------------------------------------------
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

    component Decodificador7Seg is
        port (
            BCD : in  std_logic_vector(4 downto 0);
            SEG : out std_logic_vector(6 downto 0)
        );
    end component;

    component GestorTiempos is
        port (
            Clock     : in  std_logic;
            Reset     : in  std_logic;
            SW_Modo   : in  std_logic_vector(1 downto 0);
            tick_10ms : out std_logic;
            count_s_c : out integer range 0 to 1;
            count_s_t : out integer range 0 to 9;
            count_s_u : out integer range 0 to 9
        );
    end component;

    component BancoColor is
        port (
            Clock        : in  std_logic;
            Reset        : in  std_logic;
            Pulse_In     : in  std_logic;
            Tamano_In    : in  std_logic;
            Reg_Pequenas : out std_logic_vector(3 downto 0);
            Reg_Grandes  : out std_logic_vector(3 downto 0);
            Reg_Total    : out std_logic_vector(3 downto 0)
        );
    end component;

    component FiltroBoton is
        port (
            Clock     : in  std_logic;
            Reset     : in  std_logic;
            tick_10ms : in  std_logic;
            BTN_In    : in  std_logic;
            Pulse_Out : out std_logic
        );
    end component;

    component ControladorFrecuencia is
        port (
            Clock      : in  std_logic;
            Reset      : in  std_logic;
            SW_Modo    : in  std_logic_vector(1 downto 0);
            pulse_up   : in  std_logic;
            pulse_down : in  std_logic;
            frec_int   : out std_logic;
            vel_out    : out std_logic_vector(1 downto 0);
            reg_frec   : out std_logic_vector(3 downto 0)
        );
    end component;
    
    component ControladorMotorPWM is
        generic (
            CLK_FREQ_HZ : integer := 50_000_000;
            PWM_FREQ_HZ : integer := 200
        );
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            enable_sw  : in  std_logic;
            vel_state  : in  std_logic_vector(1 downto 0);
            motor_pwm  : out std_logic;
            motor_in1  : out std_logic;
            motor_in2  : out std_logic
        );
    end component;

    component MultiplexorVistas is 
        port ( 
            SW_Modo        : in  std_logic_vector(1 downto 0);
            SW_Color       : in  std_logic_vector(1 downto 0);
            SW_Tamano      : in  std_logic;
            SW_Vista       : in  std_logic_vector(1 downto 0);
            last_color_reg : in  std_logic_vector(1 downto 0);
            last_size_reg  : in  std_logic;
            count_s_c      : in  integer range 0 to 1;
            count_s_t      : in  integer range 0 to 9;
            count_s_u      : in  integer range 0 to 9;
            reg_frec       : in  std_logic_vector(3 downto 0);
            reg_r_s        : in  std_logic_vector(3 downto 0);
            reg_r_g        : in  std_logic_vector(3 downto 0);
            reg_r_t        : in  std_logic_vector(3 downto 0);
            reg_v_s        : in  std_logic_vector(3 downto 0);
            reg_v_g        : in  std_logic_vector(3 downto 0);
            reg_v_t        : in  std_logic_vector(3 downto 0);
            reg_a_s        : in  std_logic_vector(3 downto 0);
            reg_a_g        : in  std_logic_vector(3 downto 0);
            reg_a_t        : in  std_logic_vector(3 downto 0);
            reg_tot_u      : in  std_logic_vector(3 downto 0);
            reg_tot_d      : in  std_logic_vector(3 downto 0);
            diag_r         : in  std_logic_vector(15 downto 0);
            diag_g         : in  std_logic_vector(15 downto 0);
            diag_b         : in  std_logic_vector(15 downto 0);
            diag_color     : in  std_logic_vector(1 downto 0);
            mux_hex3       : out std_logic_vector(4 downto 0);
            mux_hex2       : out std_logic_vector(4 downto 0);
            mux_hex1       : out std_logic_vector(4 downto 0);
            mux_hex0       : out std_logic_vector(4 downto 0);
            DP3            : out std_logic;
            DP2            : out std_logic;
            DP1            : out std_logic;
            DP0            : out std_logic 
        ); 
    end component;

    component ControladorLEDs is
        port (
            Reset     : in  std_logic;
            SW_Modo   : in  std_logic_vector(1 downto 0);
            SW_Color  : in  std_logic_vector(1 downto 0);
            SW_Tamano : in  std_logic;
            frec_int  : in  std_logic;
            LEDG      : out std_logic_vector(9 downto 0)
        );
    end component;

    component EnrutadorCentral is
        port (
            Clock          : in  std_logic;
            Reset          : in  std_logic;
            pulse_btn      : in  std_logic;
            SW_Color       : in  std_logic_vector(1 downto 0);
            SW_Tamano      : in  std_logic;
            cnt_tot_u      : in  std_logic_vector(3 downto 0);
            pulse_r        : out std_logic;
            pulse_v        : out std_logic;
            pulse_a        : out std_logic;
            pulse_tot      : out std_logic;
            pulse_tot_d    : out std_logic;
            last_color_reg : out std_logic_vector(1 downto 0);
            last_size_reg  : out std_logic
        );
    end component;

    component SistemaClasificadorColor is
        generic (
            CLK_FREQ_HZ     : integer   := 50_000_000;
            SETTLING_CYCLES : integer   := 10_000;
            DEBOUNCE_CYCLES : integer   := 50_000;
            IR_ACTIVE_LEVEL : std_logic := '0'
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            diag_mode     : in  std_logic;
            ir_sensor_out : in  std_logic;
            ir_size_out   : in  std_logic;
            tcs_out       : in  std_logic;
            S0            : out std_logic;
            S1            : out std_logic;
            S2            : out std_logic;
            S3            : out std_logic;
            color_code    : out std_logic_vector(1 downto 0);
            color_ready   : out std_logic;
            size_code     : out std_logic;
            presence_led  : out std_logic;
            size_led      : out std_logic;
            diag_r        : out std_logic_vector(15 downto 0);
            diag_g        : out std_logic_vector(15 downto 0);
            diag_b        : out std_logic_vector(15 downto 0)
        );
    end component;

    component ControladorServosClasificador is
        generic (
            CLK_FREQ_HZ       : integer := 50_000_000;
            DELAY_SERVO1_MS   : integer := 1050;
            DELAY_SERVO2_MS   : integer := 1750;
            PUSH_HOLD_MS      : integer := 500;
            SERVO_RETRACT_CYC : integer := 50_000;
            SERVO_EXTEND_CYC  : integer := 100_000
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            belt_enable   : in  std_logic;
            test_mode     : in  std_logic;
            is_manual_btn : in  std_logic;
            color_code    : in  std_logic_vector(1 downto 0);
            color_ready   : in  std_logic;
            servo1_pwm    : out std_logic;
            servo2_pwm    : out std_logic;
            servo1_busy   : out std_logic;
            servo2_busy   : out std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Senales Internas de Interconexion
    -- -------------------------------------------------------------------------
    signal tick_10ms : std_logic;
    signal count_s_c : integer range 0 to 1;
    signal count_s_t : integer range 0 to 9;
    signal count_s_u : integer range 0 to 9;

    signal raw_pulse_btn  : std_logic;
    signal raw_pulse_up   : std_logic;
    signal raw_pulse_down : std_logic;
    signal pulse_btn      : std_logic;
    signal pulse_up       : std_logic;
    signal pulse_down     : std_logic;

    signal frec_int  : std_logic;
    signal reg_frec  : std_logic_vector(3 downto 0);
    signal pulse_r   : std_logic;
    signal pulse_v   : std_logic;
    signal pulse_a   : std_logic;
    signal pulse_tot : std_logic;
    signal pulse_tot_d : std_logic;

    signal last_color_reg : std_logic_vector(1 downto 0);
    signal last_size_reg  : std_logic;

    -- Registros modulares de inventario (Pequenas, Grandes, Total)
    signal reg_r_s, reg_r_g, reg_r_t : std_logic_vector(3 downto 0);
    signal reg_v_s, reg_v_g, reg_v_t : std_logic_vector(3 downto 0);
    signal reg_a_s, reg_a_g, reg_a_t : std_logic_vector(3 downto 0);

    -- Registros de total acumulado global
    signal cnt_tot_u, reg_tot_u : std_logic_vector(3 downto 0);
    signal cnt_tot_d, reg_tot_d : std_logic_vector(3 downto 0);

    -- Bus de conexion entre multiplexor y decodificadores de visualizacion
    signal mux_hex3, mux_hex2, mux_hex1, mux_hex0 : std_logic_vector(4 downto 0);

    -- Senales provenientes del subsistema sensorial
    signal sensor_color_code  : std_logic_vector(1 downto 0);
    signal sensor_color_ready : std_logic;
    signal sensor_presence    : std_logic;
    signal sensor_size_code   : std_logic;
    signal sensor_size_led    : std_logic;

    -- Senales de actuacion y traccion
    signal motor_vel_s   : std_logic_vector(1 downto 0);
    signal servo1_busy_s : std_logic;
    signal servo2_busy_s : std_logic;

    -- Senales efectivas de arbitraje (seleccion automatica o manual)
    signal effective_color  : std_logic_vector(1 downto 0);
    signal effective_tamano : std_logic;
    signal effective_pulse  : std_logic;
    signal ledg_internal    : std_logic_vector(9 downto 0);

    -- Monitoreo de actividad de pulsos opticos (TCS3200)
    signal tcs_prev_s         : std_logic := '0';
    signal tcs_pulse_activity : std_logic := '0';
    signal tcs_act_cnt        : integer range 0 to 25_000_000 := 0;

    -- Bus de diagnostico espectral (microsegundos)
    signal diag_mode_s : std_logic;
    signal diag_r_s    : std_logic_vector(15 downto 0);
    signal diag_g_s    : std_logic_vector(15 downto 0);
    signal diag_b_s    : std_logic_vector(15 downto 0);

begin

    -- Habilitacion del modo diagnostico continuo en SW_Modo = "11"
    diag_mode_s <= '1' when SW_Modo = "11" else '0';

    -- -------------------------------------------------------------------------
    -- 1. Bases de Tiempo y Acondicionamiento Antirrebote de Pulsadores
    -- -------------------------------------------------------------------------
    MODULO_TIEMPOS: GestorTiempos
        port map (
            Clock     => Clock,
            Reset     => Reset,
            SW_Modo   => SW_Modo,
            tick_10ms => tick_10ms,
            count_s_c => count_s_c,
            count_s_t => count_s_t,
            count_s_u => count_s_u
        );

    BOTON_PIEZAS: FiltroBoton
        port map (
            Clock     => Clock,
            Reset     => Reset,
            tick_10ms => tick_10ms,
            BTN_In    => BTN_Contar,
            Pulse_Out => raw_pulse_btn
        );

    BOTON_MAS: FiltroBoton
        port map (
            Clock     => Clock,
            Reset     => Reset,
            tick_10ms => tick_10ms,
            BTN_In    => BTN_FrecUp,
            Pulse_Out => raw_pulse_up
        );

    BOTON_MENOS: FiltroBoton
        port map (
            Clock     => Clock,
            Reset     => Reset,
            tick_10ms => tick_10ms,
            BTN_In    => BTN_FrecDown,
            Pulse_Out => raw_pulse_down
        );

    pulse_btn  <= raw_pulse_btn  when SW_Modo = "00" else '0';
    pulse_up   <= raw_pulse_up   when SW_Modo /= "11" else '0';
    pulse_down <= raw_pulse_down when SW_Modo /= "11" else '0';

    -- -------------------------------------------------------------------------
    -- 2. Integracion Sensorial y Arbitraje (Modo Automatico vs Manual)
    -- -------------------------------------------------------------------------
    effective_color  <= sensor_color_code when sensor_color_ready = '1' else SW_Color;
    effective_tamano <= sensor_size_code  when sensor_color_ready = '1' else SW_Tamano;
    effective_pulse  <= sensor_color_ready or pulse_btn;

    -- -------------------------------------------------------------------------
    -- 3. Control de Velocidad y Modulacion PWM del Motor de Traccion
    -- -------------------------------------------------------------------------
    MODULO_FRECUENCIA: ControladorFrecuencia
        port map (
            Clock      => Clock,
            Reset      => Reset,
            SW_Modo    => SW_Modo,
            pulse_up   => pulse_up,
            pulse_down => pulse_down,
            frec_int   => frec_int,
            vel_out    => motor_vel_s,
            reg_frec   => reg_frec
        );
    
    MODULO_BANDA: ControladorMotorPWM
        generic map (
            CLK_FREQ_HZ => 50_000_000,
            PWM_FREQ_HZ => 200
        )
        port map (
            clk       => Clock,
            rst       => Reset,
            enable_sw => SW_Banda,
            vel_state => motor_vel_s,
            motor_pwm => motor_pwm,
            motor_in1 => motor_in1,
            motor_in2 => motor_in2
        );

    -- -------------------------------------------------------------------------
    -- 4. Modulador PWM y Temporizador de Servomotores Clasificadores
    -- -------------------------------------------------------------------------
    MODULO_SERVOS: ControladorServosClasificador
        generic map (
            CLK_FREQ_HZ       => 50_000_000,
            DELAY_SERVO1_MS   => 1050,
            DELAY_SERVO2_MS   => 1750,
            PUSH_HOLD_MS      => 500,
            SERVO_RETRACT_CYC => 50_000,
            SERVO_EXTEND_CYC  => 100_000
        )
        port map (
            clk           => Clock,
            rst           => Reset,
            belt_enable   => SW_Banda,
            test_mode     => '0',
            is_manual_btn => pulse_btn,
            color_code    => effective_color,
            color_ready   => effective_pulse,
            servo1_pwm    => servo1_pwm,
            servo2_pwm    => servo2_pwm,
            servo1_busy   => servo1_busy_s,
            servo2_busy   => servo2_busy_s
        );

    -- -------------------------------------------------------------------------
    -- 5. Enrutamiento Sincrono y Bancos de Conteo de Inventario
    -- -------------------------------------------------------------------------
    MODULO_ENRUTADOR: EnrutadorCentral
        port map (
            Clock          => Clock,
            Reset          => Reset,
            pulse_btn      => effective_pulse,
            SW_Color       => effective_color,
            SW_Tamano      => effective_tamano,
            cnt_tot_u      => cnt_tot_u,
            pulse_r        => pulse_r,
            pulse_v        => pulse_v,
            pulse_a        => pulse_a,
            pulse_tot      => pulse_tot,
            pulse_tot_d    => pulse_tot_d,
            last_color_reg => last_color_reg,
            last_size_reg  => last_size_reg
        );

    BANCO_ROJO:  BancoColor port map (Clock, Reset, pulse_r, effective_tamano, reg_r_s, reg_r_g, reg_r_t);
    BANCO_VERDE: BancoColor port map (Clock, Reset, pulse_v, effective_tamano, reg_v_s, reg_v_g, reg_v_t);
    BANCO_AZUL:  BancoColor port map (Clock, Reset, pulse_a, effective_tamano, reg_a_s, reg_a_g, reg_a_t);

    -- Acumuladores BCD de Conteo Total
    C_TT_U: Contador4bits port map (Clock, Reset, pulse_tot, cnt_tot_u);
    R_TT_U: Registro4bits port map (Clock, Reset, '1', cnt_tot_u, reg_tot_u);
    C_TT_D: Contador4bits port map (Clock, Reset, pulse_tot_d, cnt_tot_d);
    R_TT_D: Registro4bits port map (Clock, Reset, '1', cnt_tot_d, reg_tot_d);

    -- -------------------------------------------------------------------------
    -- 6. Subsistema de Sensores Opticos (Presencia IR, Altura y Color TCS3200)
    -- -------------------------------------------------------------------------
    MODULO_SENSOR_COLOR: SistemaClasificadorColor
        generic map (
            CLK_FREQ_HZ     => 50_000_000,
            SETTLING_CYCLES => 10_000,
            DEBOUNCE_CYCLES => 50_000,
            IR_ACTIVE_LEVEL => '0'
        )
        port map (
            clk           => Clock,
            rst           => Reset,
            diag_mode     => diag_mode_s,
            ir_sensor_out => ir_sensor_out,
            ir_size_out   => ir_size_out,
            tcs_out       => tcs_out,
            S0            => S0,
            S1            => S1,
            S2            => S2,
            S3            => S3,
            color_code    => sensor_color_code,
            color_ready   => sensor_color_ready,
            size_code     => sensor_size_code,
            presence_led  => sensor_presence,
            size_led      => sensor_size_led,
            diag_r        => diag_r_s,
            diag_g        => diag_g_s,
            diag_b        => diag_b_s
        );

    -- -------------------------------------------------------------------------
    -- 7. Visualizacion Multiplexada en Displays de 7 Segmentos
    -- -------------------------------------------------------------------------
    MODULO_VISTAS: MultiplexorVistas
        port map (
            SW_Modo        => SW_Modo,
            SW_Color       => SW_Color,
            SW_Tamano      => SW_Tamano,
            SW_Vista       => SW_Vista,
            last_color_reg => last_color_reg,
            last_size_reg  => last_size_reg,
            count_s_c      => count_s_c,
            count_s_t      => count_s_t,
            count_s_u      => count_s_u,
            reg_frec       => reg_frec,
            reg_r_s        => reg_r_s,
            reg_r_g        => reg_r_g,
            reg_r_t        => reg_r_t,
            reg_v_s        => reg_v_s,
            reg_v_g        => reg_v_g,
            reg_v_t        => reg_v_t,
            reg_a_s        => reg_a_s,
            reg_a_g        => reg_a_g,
            reg_a_t        => reg_a_t,
            reg_tot_u      => reg_tot_u,
            reg_tot_d      => reg_tot_d,
            diag_r         => diag_r_s,
            diag_g         => diag_g_s,
            diag_b         => diag_b_s,
            diag_color     => sensor_color_code,
            mux_hex3       => mux_hex3,
            mux_hex2       => mux_hex2,
            mux_hex1       => mux_hex1,
            mux_hex0       => mux_hex0,
            DP3            => DP3,
            DP2            => DP2,
            DP1            => DP1,
            DP0            => DP0
        );

    DECO_3: Decodificador7Seg port map (mux_hex3, HEX3);
    DECO_2: Decodificador7Seg port map (mux_hex2, HEX2);
    DECO_1: Decodificador7Seg port map (mux_hex1, HEX1);
    DECO_0: Decodificador7Seg port map (mux_hex0, HEX0);

    -- -------------------------------------------------------------------------
    -- 8. Monitoreo e Indicadores Luminosos LEDG
    -- -------------------------------------------------------------------------
    MODULO_LEDS: ControladorLEDs
        port map (
            Reset     => Reset,
            SW_Modo   => SW_Modo,
            SW_Color  => effective_color,
            SW_Tamano => effective_tamano,
            frec_int  => frec_int,
            LEDG      => ledg_internal
        );
    
    -- Detector dinamico de pulsos en linea tcs_out
    process(Clock, Reset)
    begin
        if Reset = '0' then
            tcs_pulse_activity <= '0';
            tcs_act_cnt        <= 0;
            tcs_prev_s         <= '0';
        elsif rising_edge(Clock) then
            tcs_prev_s <= tcs_out;
            if tcs_prev_s /= tcs_out then
                tcs_act_cnt        <= 25_000_000; -- Intervalo de persistencia visual (0.5 s)
                tcs_pulse_activity <= '1';
            elsif tcs_act_cnt > 0 then
                tcs_act_cnt        <= tcs_act_cnt - 1;
                tcs_pulse_activity <= '1';
            else
                tcs_pulse_activity <= '0';
            end if;
        end if;
    end process;

    -- Asignacion de lineas de diagnostico al bus LEDG:
    -- LEDG[9]: Marcha de la banda (SW_Banda)
    -- LEDG[8]: Actividad de pulsos del sensor TCS3200
    -- LEDG[7]: Deteccion del sensor IR 1 (Presencia Base)
    -- LEDG[6]: Deteccion del sensor IR 2 (Criterio Altura / Objeto Grande)
    -- LEDG[5]: Estado activo Servo 1 (Desvio Rampa 1 - Rojo)
    -- LEDG[4]: Estado activo Servo 2 (Desvio Rampa 2 - Verde)
    -- LEDG[3..0]: Senalizacion de estado interno de control
    LEDG <= SW_Banda & tcs_pulse_activity & sensor_presence & sensor_size_led & 
            servo1_busy_s & servo2_busy_s & ledg_internal(3 downto 0);

end architecture;
