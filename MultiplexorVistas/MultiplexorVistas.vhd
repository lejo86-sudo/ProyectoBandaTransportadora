-- ============================================================================
-- Modulo: MultiplexorVistas.vhd
-- Descripcion:
--   Multiplexor de enrutamiento y formato para los cuatro visualizadores de
--   7 segmentos (HEX3..HEX0) y puntos decimales (DP3..DP0).
--
-- Modos de Visualizacion (SW_Modo):
--   1. Modo "00" (Operacion Normal e Inventario - Seleccion via SW_Vista):
--      - "00": Resumen global: [Velocidad] [Total Azul] [Total Verde] [Total Rojo].
--      - "01": Desglose Rojo:  ['r'] [Pequenas] [Grandes] [Total Rojo].
--      - "10": Desglose Verde: ['U'] [Pequenas] [Grandes] [Total Verde].
--      - "11": Desglose Azul:  ['A'] [Pequenas] [Grandes] [Total Azul].
--   2. Modo "01" (Metricas Temporales y Conteo Total):
--      Visualizacion de cronometros del sistema y desglose selectivo.
--   3. Modo "10" (Consulta Manual):
--      Inspeccion por switch de color y tamano.
--   4. Modo "11" (Diagnostico y Calibracion Espectral en Tiempo Real):
--      - SW_Color="00": Estado de clasificacion ("rEd-", "VErd", "A2UL", "----").
--      - SW_Color="01": Periodo canal Rojo en microsegundos (formato 'r' + D2..D0).
--      - SW_Color="10": Periodo canal Verde en microsegundos (formato 'V' + D2..D0).
--      - SW_Color="11": Periodo canal Azul en microsegundos (formato 'A' + D2..D0).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MultiplexorVistas is
    port (
        -- Entradas de seleccion y control por conmutadores
        SW_Modo        : in std_logic_vector(1 downto 0);
        SW_Color       : in std_logic_vector(1 downto 0);
        SW_Tamano      : in std_logic;
        SW_Vista       : in std_logic_vector(1 downto 0);
        
        -- Registros de ultimo estado registrado
        last_color_reg : in std_logic_vector(1 downto 0);
        last_size_reg  : in std_logic;
        
        -- Cronometraje y registro de velocidad
        count_s_c      : in integer range 0 to 1;
        count_s_t      : in integer range 0 to 9;
        count_s_u      : in integer range 0 to 9;
        reg_frec       : in std_logic_vector(3 downto 0);
        
        -- Registros de inventario modular clasificado
        reg_r_s, reg_r_g, reg_r_t : in std_logic_vector(3 downto 0);
        reg_v_s, reg_v_g, reg_v_t : in std_logic_vector(3 downto 0);
        reg_a_s, reg_a_g, reg_a_t : in std_logic_vector(3 downto 0);
        
        -- Registros de acumulacion total
        reg_tot_u, reg_tot_d      : in std_logic_vector(3 downto 0);
        
        -- Entradas de diagnostico espectral en microsegundos
        diag_r         : in std_logic_vector(15 downto 0);
        diag_g         : in std_logic_vector(15 downto 0);
        diag_b         : in std_logic_vector(15 downto 0);
        diag_color     : in std_logic_vector(1 downto 0);
        
        -- Salidas codificadas hacia decodificadores de 7 segmentos y DP
        mux_hex3, mux_hex2, mux_hex1, mux_hex0 : out std_logic_vector(4 downto 0);
        DP3, DP2, DP1, DP0                     : out std_logic
    );
end entity;

architecture rtl of MultiplexorVistas is
begin
    process(SW_Modo, SW_Color, SW_Vista, SW_Tamano, last_color_reg, last_size_reg, 
            count_s_c, count_s_t, count_s_u, reg_frec, reg_r_s, reg_r_g, reg_r_t, 
            reg_v_s, reg_v_g, reg_v_t, reg_a_s, reg_a_g, reg_a_t, reg_tot_u, reg_tot_d,
            diag_r, diag_g, diag_b, diag_color)
        variable val : integer range 0 to 9999;
    begin
        -- Inicializacion de salidas por defecto (evita generacion de latches)
        DP3 <= '1'; DP2 <= '1'; DP1 <= '1'; DP0 <= '1';
        mux_hex3 <= "11111"; mux_hex2 <= "11111"; mux_hex1 <= "11111"; mux_hex0 <= "11111"; 

        case SW_Modo is
            -- MODO 00: Visualizacion de Inventario en Tiempo Real
            when "00" => 
                case SW_Vista is
                    -- Vista "00": Resumen global
                    when "00" =>
                        mux_hex3 <= "0" & reg_frec; 
                        mux_hex2 <= "0" & reg_a_t; 
                        mux_hex1 <= "0" & reg_v_t; 
                        mux_hex0 <= "0" & reg_r_t;
                    
                    -- Vista "01": Desglose clasificacion Rojo
                    when "01" =>
                        mux_hex3 <= "01010";         -- Caracter 'r'
                        mux_hex2 <= "0" & reg_r_s;   -- Cantidad Pequenas
                        mux_hex1 <= "0" & reg_r_g;   -- Cantidad Grandes
                        mux_hex0 <= "0" & reg_r_t;   -- Total Acumulado
                    
                    -- Vista "10": Desglose clasificacion Verde
                    when "10" =>
                        mux_hex3 <= "01011";         -- Caracter 'U' (representacion visual Verde)
                        mux_hex2 <= "0" & reg_v_s;   -- Cantidad Pequenas
                        mux_hex1 <= "0" & reg_v_g;   -- Cantidad Grandes
                        mux_hex0 <= "0" & reg_v_t;   -- Total Acumulado
                    
                    -- Vista "11": Desglose clasificacion Azul
                    when others =>
                        mux_hex3 <= "01100";         -- Caracter 'A' (representacion visual Azul)
                        mux_hex2 <= "0" & reg_a_s;   -- Cantidad Pequenas
                        mux_hex1 <= "0" & reg_a_g;   -- Cantidad Grandes
                        mux_hex0 <= "0" & reg_a_t;   -- Total Acumulado
                end case;

            -- MODO 01: Cronometria de Proceso y Conteo Total
            when "01" => 
                if SW_Vista = "11" then 
                    mux_hex3 <= "0" & std_logic_vector(to_unsigned(count_s_t, 4));
                    mux_hex2 <= "0" & std_logic_vector(to_unsigned(count_s_u, 4));
                    mux_hex1 <= "0" & reg_tot_d;
                    mux_hex0 <= "0" & reg_tot_u;
                elsif SW_Color = "00" then
                    mux_hex3 <= "10000"; mux_hex2 <= "10000"; mux_hex1 <= "10000"; mux_hex0 <= "10000";
                else
                    if SW_Vista = "00" then      
                        mux_hex3 <= "0" & std_logic_vector(to_unsigned(count_s_c, 4));
                        mux_hex2 <= "0" & std_logic_vector(to_unsigned(count_s_t, 4));
                        mux_hex1 <= "0" & std_logic_vector(to_unsigned(count_s_u, 4));
                        if SW_Color = "01" then 
                            mux_hex0 <= "0" & reg_r_t; DP3 <= '0'; 
                        elsif SW_Color = "10" then 
                            mux_hex0 <= "0" & reg_v_t; DP2 <= '0'; 
                        elsif SW_Color = "11" then 
                            mux_hex0 <= "0" & reg_a_t; DP1 <= '0'; 
                        end if;
                    elsif SW_Vista = "01" then   
                        mux_hex2 <= "01110"; mux_hex1 <= "10000"; DP0 <= '0';
                        if SW_Color = "01" then 
                            mux_hex3 <= "01010"; mux_hex0 <= "0" & reg_r_s; 
                        elsif SW_Color = "10" then 
                            mux_hex3 <= "01011"; mux_hex0 <= "0" & reg_v_s; 
                        elsif SW_Color = "11" then 
                            mux_hex3 <= "01100"; mux_hex0 <= "0" & reg_a_s; 
                        end if;
                    elsif SW_Vista = "10" then   
                        mux_hex2 <= "01111"; mux_hex1 <= "10000"; DP0 <= '0';
                        if SW_Color = "01" then 
                            mux_hex3 <= "01010"; mux_hex0 <= "0" & reg_r_g; 
                        elsif SW_Color = "10" then 
                            mux_hex3 <= "01011"; mux_hex0 <= "0" & reg_v_g; 
                        elsif SW_Color = "11" then 
                            mux_hex3 <= "01100"; mux_hex0 <= "0" & reg_a_g; 
                        end if;
                    end if;
                end if;

            -- MODO 10: Consulta Manual por Conmutadores
            when "10" => 
                mux_hex1 <= "10000"; 
                if SW_Color = "01" then
                    mux_hex3 <= "01010"; 
                    if SW_Tamano = '0' then 
                        mux_hex2 <= "01110"; mux_hex0 <= "0" & reg_r_s; 
                    else 
                        mux_hex2 <= "01111"; mux_hex0 <= "0" & reg_r_g; 
                    end if;
                elsif SW_Color = "10" then
                    mux_hex3 <= "01011"; 
                    if SW_Tamano = '0' then 
                        mux_hex2 <= "01110"; mux_hex0 <= "0" & reg_v_s; 
                    else 
                        mux_hex2 <= "01111"; mux_hex0 <= "0" & reg_v_g; 
                    end if;
                elsif SW_Color = "11" then
                    mux_hex3 <= "01100"; 
                    if SW_Tamano = '0' then 
                        mux_hex2 <= "01110"; mux_hex0 <= "0" & reg_a_s; 
                    else 
                        mux_hex2 <= "01111"; mux_hex0 <= "0" & reg_a_g; 
                    end if;
                else
                    mux_hex3 <= "10001"; mux_hex2 <= "10010"; mux_hex1 <= "00101"; mux_hex0 <= "10011";
                end if;

            -- MODO 11: Diagnostico Espectral en Tiempo Real (TCS3200)
            when "11" => 
                case SW_Color is
                    -- Canal Rojo: Periodo medido en us
                    when "01" => 
                        val := to_integer(unsigned(diag_r));
                        if val > 999 then val := 999; end if;
                        mux_hex3 <= "01010"; -- Identificador 'r'
                        mux_hex2 <= "0" & std_logic_vector(to_unsigned((val / 100) mod 10, 4));
                        mux_hex1 <= "0" & std_logic_vector(to_unsigned((val / 10) mod 10, 4));
                        mux_hex0 <= "0" & std_logic_vector(to_unsigned(val mod 10, 4));

                    -- Canal Verde: Periodo medido en us
                    when "10" => 
                        val := to_integer(unsigned(diag_g));
                        if val > 999 then val := 999; end if;
                        mux_hex3 <= "01011"; -- Identificador 'V'
                        mux_hex2 <= "0" & std_logic_vector(to_unsigned((val / 100) mod 10, 4));
                        mux_hex1 <= "0" & std_logic_vector(to_unsigned((val / 10) mod 10, 4));
                        mux_hex0 <= "0" & std_logic_vector(to_unsigned(val mod 10, 4));

                    -- Canal Azul: Periodo medido en us
                    when "11" => 
                        val := to_integer(unsigned(diag_b));
                        if val > 999 then val := 999; end if;
                        mux_hex3 <= "01100"; -- Identificador 'A'
                        mux_hex2 <= "0" & std_logic_vector(to_unsigned((val / 100) mod 10, 4));
                        mux_hex1 <= "0" & std_logic_vector(to_unsigned((val / 10) mod 10, 4));
                        mux_hex0 <= "0" & std_logic_vector(to_unsigned(val mod 10, 4));

                    -- Estado del Clasificador en Tiempo Real
                    when others => 
                        if diag_color = "01" then     -- Rojo: "r E d -"
                            mux_hex3 <= "01010"; -- 'r'
                            mux_hex2 <= "10010"; -- 'E'
                            mux_hex1 <= "10001"; -- 'd'
                            mux_hex0 <= "10000"; -- '-'
                        elsif diag_color = "10" then  -- Verde: "V E r d"
                            mux_hex3 <= "01011"; -- 'V'
                            mux_hex2 <= "10010"; -- 'E'
                            mux_hex1 <= "01010"; -- 'r'
                            mux_hex0 <= "10001"; -- 'd'
                        elsif diag_color = "11" then  -- Azul: "A 2 U L"
                            mux_hex3 <= "01100"; -- 'A'
                            mux_hex2 <= "00010"; -- '2'
                            mux_hex1 <= "01011"; -- 'U'
                            mux_hex0 <= "01111"; -- 'L'
                        else                          -- Reposo / Descarte: "- - - -"
                            mux_hex3 <= "10000"; -- '-'
                            mux_hex2 <= "10000"; -- '-'
                            mux_hex1 <= "10000"; -- '-'
                            mux_hex0 <= "10000"; -- '-'
                        end if;
                end case;

            when others => null;
        end case;
    end process;
end architecture;
