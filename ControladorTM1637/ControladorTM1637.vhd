-- =============================================================================
-- ControladorTM1637.vhd
-- Controlador para Display de 4 digitos y 7 segmentos con chip TM1637
-- Desarrollado para Sistema Clasificador de Banda Transportadora
-- FPGA: Altera Cyclone III EP3C16F484C6 (Terasic DE0)
-- 
-- Caracteristicas:
-- 1. Auto-refresco interno continuo (~25 Hz) con pestillo asincrono de update.
-- 2. Maquina de estados con condiciones START y STOP estrictas de 3 fases segun norma I2C/TM1637.
-- 3. Velocidad segura de 50 kHz (inmune a capacitancias parasitas y cables jumper).
-- 4. Soporta caracteres 0-9, 'r', 'U', 'A', 't', 'P', 'G', '-', 'd', 'E', 'C'.
-- =============================================================================
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ControladorTM1637 is
    generic (
        CLK_FREQ_HZ : integer := 50_000_000;
        TM_CLK_HZ   : integer := 50_000        -- 50 kHz (semiperiodo = 10 us = 500 ciclos @ 50MHz)
    );
    port (
        clk      : in    std_logic;
        rst      : in    std_logic;
        -- Digitos con codificacion de 5 bits:
        -- 0-9: Numeros '0'..'9'
        -- 10 : 'r' (Rojo)
        -- 11 : 'U' (Verde)
        -- 12 : 'A' (Azul)
        -- 13 : 't' (Total)
        -- 14 : 'P' (Pequeno)
        -- 15 : 'G' (Grande)
        -- 16 : '-' (Guion)
        -- 17 : 'd' (Descarte)
        -- 18 : 'E'
        -- 19 : 'C'
        -- 31 : Apagado
        digit3   : in    std_logic_vector(4 downto 0);  -- Digito 3 (Extremo Izquierdo, Grid 1)
        digit2   : in    std_logic_vector(4 downto 0);  -- Digito 2 (Segundo, Grid 2 con dos puntos)
        digit1   : in    std_logic_vector(4 downto 0);  -- Digito 1 (Tercero, Grid 3)
        digit0   : in    std_logic_vector(4 downto 0);  -- Digito 0 (Extremo Derecho, Grid 4)
        colon    : in    std_logic;                     -- '1' = encender dos puntos centrales (:)
        bright   : in    std_logic_vector(2 downto 0);  -- Brillo: "000" (min) a "111" (max)
        update   : in    std_logic;                     -- Pulso opcional de actualizacion manual
        tm_clk   : out   std_logic;                     -- Salida de Reloj a pin TM1637
        tm_dio   : inout std_logic;                     -- Linea de Datos bidireccional (con tristate)
        busy     : out   std_logic                      -- '1' cuando esta transmitiendo
    );
end entity;

architecture RTL of ControladorTM1637 is

    constant HALF_PER : integer := CLK_FREQ_HZ / (TM_CLK_HZ * 2); -- 500 ciclos @ 50MHz/50kHz
    constant AUTO_REFRESH_CYCLES : integer := CLK_FREQ_HZ / 25;   -- Refresco automatico cada 40 ms (25 Hz)

    -- Decodificacion 5-bit BCD/Char -> Segmentos TM1637 (Activo Alto)
    -- Formato TM1637: bit0=A, bit1=B, bit2=C, bit3=D, bit4=E, bit5=F, bit6=G, bit7=DP
    function decode_tm1637(bcd : std_logic_vector(4 downto 0)) return std_logic_vector is
    begin
        case bcd is
            when "00000" => return "00111111"; -- 0: A B C D E F
            when "00001" => return "00000110"; -- 1: B C
            when "00010" => return "01011011"; -- 2: A B D E G
            when "00011" => return "01001111"; -- 3: A B C D G
            when "00100" => return "01100110"; -- 4: B C F G
            when "00101" => return "01101101"; -- 5: A C D F G
            when "00110" => return "01111101"; -- 6: A C D E F G
            when "00111" => return "00000111"; -- 7: A B C
            when "01000" => return "01111111"; -- 8: A B C D E F G
            when "01001" => return "01101111"; -- 9: A B C D F G

            -- Caracteres especiales
            when "01010" => return "01010000"; -- 10: 'r' (Rojo: e, g)
            when "01011" => return "00111110"; -- 11: 'U' (Verde: b, c, d, e, f)
            when "01100" => return "01110111"; -- 12: 'A' (Azul: a, b, c, e, f, g)
            when "01101" => return "01111000"; -- 13: 't' (Total: d, e, f, g)
            when "01110" => return "01110011"; -- 14: 'P' (Pequeno: a, b, e, f, g)
            when "01111" => return "00111101"; -- 15: 'G' (Grande: a, c, d, e, f)
            when "10000" => return "01000000"; -- 16: '-' (Guion: g)
            when "10001" => return "01011110"; -- 17: 'd' (Descarte: b, c, d, e, g)
            when "10010" => return "01111001"; -- 18: 'E' (a, d, e, f, g)
            when "10011" => return "00111001"; -- 19: 'C' (a, d, e, f)
            when others  => return "00000000"; -- Apagado
        end case;
    end function;

    -- Estados de la FSM
    type t_state is (
        ST_IDLE,
        -- START condition de 3 fases
        ST_START_1,
        ST_START_2,
        ST_START_3,
        -- Transmision de bits
        ST_BIT_LOW,
        ST_BIT_HIGH,
        -- ACK de 3 fases
        ST_ACK_1,
        ST_ACK_2,
        ST_ACK_3,
        -- STOP condition de 3 fases
        ST_STOP_1,
        ST_STOP_2,
        ST_STOP_3,
        -- Pausa entre paquetes
        ST_GAP
    );

    signal state     : t_state := ST_IDLE;
    signal tick      : std_logic := '0';
    signal tick_cnt  : integer range 0 to HALF_PER := 0;

    -- Pestillo de actualizacion y temporizador continuo
    signal update_latched   : std_logic := '1'; -- Inicialmente '1' para arrancar de inmediato
    signal auto_refresh_cnt : integer range 0 to AUTO_REFRESH_CYCLES := 0;

    -- Buffers de transmision
    type t_buf is array(0 to 3) of std_logic_vector(7 downto 0);
    signal seg_buf   : t_buf := (others => (others => '0'));
    signal bright_r  : std_logic_vector(2 downto 0) := "111";

    -- Control de paquete y bits
    signal pkt_idx   : integer range 0 to 2 := 0;  -- 0=0x40, 1=Datos(0xC0..), 2=Control Display(0x8F)
    signal byte_idx  : integer range 0 to 4 := 0;
    signal bit_idx   : integer range 0 to 7 := 0;
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Registros de salidas fisicas
    signal r_clk     : std_logic := '1';
    signal r_dio_out : std_logic := '1';
    signal r_dio_oe  : std_logic := '1';

    -- Obtencion del byte segun paquete y posicion
    function get_byte(pkt : integer; b_idx : integer; s0, s1, s2, s3 : std_logic_vector(7 downto 0); br : std_logic_vector(2 downto 0)) return std_logic_vector is
    begin
        if pkt = 0 then
            return x"40"; -- Data command: auto-increment de direccion
        elsif pkt = 1 then
            case b_idx is
                when 0      => return x"C0"; -- Address command: iniciar en direccion 00H
                when 1      => return s0;    -- Digito 3 (Extremo Izquierdo)
                when 2      => return s1;    -- Digito 2 (Segundo, con colon en bit 7)
                when 3      => return s2;    -- Digito 1 (Tercero)
                when others => return s3;    -- Digito 0 (Extremo Derecho)
            end case;
        else
            return "10001" & br; -- 0x88 | brillo: Display ON (bit 3='1') con brillo configurado
        end if;
    end function;

    function get_len(pkt : integer) return integer is
    begin
        if pkt = 0 then
            return 1;
        elsif pkt = 1 then
            return 5;
        else
            return 1;
        end if;
    end function;

begin

    -- Generador de ticks de semiperiodo a frecuencia 2 * TM_CLK (cada HALF_PER ciclos de 50 MHz)
    p_tick: process(clk, rst)
    begin
        if rst = '0' then
            tick_cnt <= 0;
            tick     <= '0';
        elsif rising_edge(clk) then
            tick <= '0';
            if tick_cnt = HALF_PER - 1 then
                tick_cnt <= 0;
                tick     <= '1';
            else
                tick_cnt <= tick_cnt + 1;
            end if;
        end if;
    end process;

    -- Pestillo asincrono de update y temporizador de auto-refresco
    p_trigger: process(clk, rst)
    begin
        if rst = '0' then
            update_latched   <= '1'; -- Dispara transmision de arranque
            auto_refresh_cnt <= 0;
        elsif rising_edge(clk) then
            -- Si llega pulso de update externo, guardarlo en el pestillo
            if update = '1' then
                update_latched <= '1';
            end if;

            -- Auto-refresco periodico (cada ~40ms) para garantizar que la pantalla siempre este viva
            if auto_refresh_cnt = AUTO_REFRESH_CYCLES - 1 then
                auto_refresh_cnt <= 0;
                update_latched   <= '1';
            else
                auto_refresh_cnt <= auto_refresh_cnt + 1;
            end if;

            -- Limpiar pestillo cuando la FSM entra en transmision
            if state = ST_START_1 then
                update_latched <= '0';
            end if;
        end if;
    end process;

    -- Maquina de Estados de Transmision Serial TM1637
    p_fsm: process(clk, rst)
    begin
        if rst = '0' then
            state     <= ST_IDLE;
            r_clk     <= '1';
            r_dio_out <= '1';
            r_dio_oe  <= '1';
            pkt_idx   <= 0;
            byte_idx  <= 0;
            bit_idx   <= 0;
            shift_reg <= (others => '0');
        elsif rising_edge(clk) then
            if tick = '1' then
                case state is

                    -- =========================================================
                    -- REPOSO: Espera disparador de refresco (interno o externo)
                    -- =========================================================
                    when ST_IDLE =>
                        r_clk     <= '1';
                        r_dio_out <= '1';
                        r_dio_oe  <= '1';
                        if update_latched = '1' then
                            -- Capturar y decodificar los 4 digitos
                            seg_buf(0) <= decode_tm1637(digit3);
                            seg_buf(1) <= decode_tm1637(digit2);
                            seg_buf(2) <= decode_tm1637(digit1);
                            seg_buf(3) <= decode_tm1637(digit0);
                            -- Colon: bit 7 del segundo digito
                            if colon = '1' then
                                seg_buf(1)(7) <= '1';
                            end if;
                            bright_r <= bright;
                            pkt_idx  <= 0;
                            state    <= ST_START_1;
                        end if;

                    -- =========================================================
                    -- START CONDITION: 
                    -- Fase 1: CLK=1, DIO=1 (garantizar bus en reposo alto)
                    -- Fase 2: CLK=1, DIO=0 (flanco de bajada de DIO con CLK alto)
                    -- Fase 3: CLK=0, DIO=0 (preparar transmision)
                    -- =========================================================
                    when ST_START_1 =>
                        r_clk     <= '1';
                        r_dio_out <= '1';
                        r_dio_oe  <= '1';
                        byte_idx  <= 0;
                        bit_idx   <= 0;
                        shift_reg <= get_byte(pkt_idx, 0, seg_buf(0), seg_buf(1), seg_buf(2), seg_buf(3), bright_r);
                        state     <= ST_START_2;

                    when ST_START_2 =>
                        r_clk     <= '1';
                        r_dio_out <= '0'; -- START: DIO cae mientras CLK esta en alto
                        r_dio_oe  <= '1';
                        state     <= ST_START_3;

                    when ST_START_3 =>
                        r_clk     <= '0'; -- CLK baja
                        r_dio_out <= '0';
                        state     <= ST_BIT_LOW;

                    -- =========================================================
                    -- TRANSMISION DE BIT:
                    -- LOW : CLK bajo presenta el dato (LSB primero)
                    -- HIGH: CLK alto valida el dato para que el chip lo muestree
                    -- =========================================================
                    when ST_BIT_LOW =>
                        r_clk     <= '0';
                        r_dio_out <= shift_reg(0);
                        r_dio_oe  <= '1';
                        state     <= ST_BIT_HIGH;

                    when ST_BIT_HIGH =>
                        r_clk     <= '1';
                        shift_reg <= '0' & shift_reg(7 downto 1);
                        if bit_idx = 7 then
                            bit_idx <= 0;
                            state   <= ST_ACK_1;
                        else
                            bit_idx <= bit_idx + 1;
                            state   <= ST_BIT_LOW;
                        end if;

                    -- =========================================================
                    -- ACK 9no CICLO:
                    -- Fase 1: CLK=0, DIO='Z' (liberar bus en alta impedancia)
                    -- Fase 2: CLK=1, DIO='Z' (pulso de reloj donde TM1637 hace ACK)
                    -- Fase 3: CLK=0, DIO=0   (terminar 9no ciclo y retomar bus)
                    -- =========================================================
                    when ST_ACK_1 =>
                        r_clk     <= '0';
                        r_dio_oe  <= '0'; -- Tristate
                        state     <= ST_ACK_2;

                    when ST_ACK_2 =>
                        r_clk     <= '1'; -- Muestreo de ACK
                        state     <= ST_ACK_3;

                    when ST_ACK_3 =>
                        r_clk     <= '0'; -- CLK baja terminando el ciclo de ACK
                        r_dio_out <= '0';
                        r_dio_oe  <= '1';
                        if byte_idx = get_len(pkt_idx) - 1 then
                            -- Fin del paquete actual -> ir a condicion STOP
                            state <= ST_STOP_1;
                        else
                            -- Siguiente byte dentro del mismo paquete
                            byte_idx  <= byte_idx + 1;
                            bit_idx   <= 0;
                            shift_reg <= get_byte(pkt_idx, byte_idx + 1, seg_buf(0), seg_buf(1), seg_buf(2), seg_buf(3), bright_r);
                            state     <= ST_BIT_LOW;
                        end if;

                    -- =========================================================
                    -- STOP CONDITION:
                    -- Fase 1: CLK=0, DIO=0 (preparar lineas en bajo)
                    -- Fase 2: CLK=1, DIO=0 (CLK sube primero)
                    -- Fase 3: CLK=1, DIO=1 (DIO sube mientras CLK esta en alto = STOP!)
                    -- =========================================================
                    when ST_STOP_1 =>
                        r_clk     <= '0';
                        r_dio_out <= '0';
                        r_dio_oe  <= '1';
                        state     <= ST_STOP_2;

                    when ST_STOP_2 =>
                        r_clk     <= '1'; -- CLK sube primero
                        r_dio_out <= '0'; -- DIO sigue en bajo
                        r_dio_oe  <= '1';
                        state     <= ST_STOP_3;

                    when ST_STOP_3 =>
                        r_clk     <= '1'; -- CLK sigue en alto
                        r_dio_out <= '1'; -- STOP: DIO sube con CLK alto
                        r_dio_oe  <= '1';
                        if pkt_idx = 2 then
                            -- Se enviaron los 3 paquetes (0x40, 0xC0+datos, 0x88|brillo)
                            state <= ST_IDLE;
                        else
                            pkt_idx <= pkt_idx + 1;
                            state   <= ST_GAP;
                        end if;

                    -- =========================================================
                    -- GAP: Pausa entre paquetes (CLK=1, DIO=1)
                    -- =========================================================
                    when ST_GAP =>
                        r_clk     <= '1';
                        r_dio_out <= '1';
                        r_dio_oe  <= '1';
                        state     <= ST_START_1;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Asignacion a pines fisicos
    tm_clk <= r_clk;
    tm_dio <= r_dio_out when r_dio_oe = '1' else 'Z';
    busy   <= '0' when state = ST_IDLE else '1';

end architecture;
