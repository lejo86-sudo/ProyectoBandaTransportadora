-- ============================================================================
-- Modulo: FSMHarvard.vhd
-- Descripcion:
--   Unidad de control y procesamiento secuencial bajo arquitectura Harvard
--   (buses de instrucciones/patrones en ROM y datos de conteo en RAM separados).
--
-- Secuencia de Operacion por Pieza Detectada:
--   1. IDLE:                Espera de pulso estroboscopico de clasificacion valida.
--   2. CALC_ADDR:           Calculo indexado de punteros de memoria ROM y RAM.
--   3. READ_ROM:            Lectura de patrones de caracteristicas desde ROM.
--   4. READ_RAM_INDIV:      Lectura del contador especifico (Color x Tamano).
--   5. WRITE_RAM_INDIV:     Incremento BCD y escritura en RAM.
--   6. READ_RAM_COLOR_TOT:  Lectura del contador total de la categoria de color.
--   7. WRITE_RAM_COLOR_TOT: Incremento BCD y actualizacion en RAM.
--   8. READ_RAM_GLOB_U:     Lectura de unidades del total global.
--   9. WRITE_RAM_GLOB_U:    Incremento y evaluacion de acarreo decimal.
--  10. READ/WRITE_GLOB_D:   Actualizacion condicional de decenas globales.
--  11. DONE:                Fin de ciclo y retorno a estado de reposo (IDLE).
-- ============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity FSMHarvard is
    port (
        Clock          : in  std_logic;                        -- Reloj maestro del sistema
        Reset          : in  std_logic;                        -- Reset asincrono activo en bajo ('0')
        pulse_btn      : in  std_logic;                        -- Pulso de clasificacion validado
        SW_Color       : in  std_logic_vector(1 downto 0);     -- Codigo de color ("01", "10", "11")
        SW_Tamano      : in  std_logic;                        -- Criterio de dimension ('0'=Pequeno, '1'=Grande)
        
        -- Interfaz con Memoria ROM de Caracteristicas
        rom_addr       : out std_logic_vector(3 downto 0);     -- Bus de direcciones hacia ROM
        rom_data       : in  std_logic_vector(7 downto 0);     -- Bus de datos procedente de ROM
        
        -- Interfaz con Memoria RAM de Conteo
        ram_addr       : out std_logic_vector(3 downto 0);     -- Bus de direcciones hacia RAM
        ram_data_in    : out std_logic_vector(7 downto 0);     -- Bus de datos de escritura hacia RAM
        ram_data_out   : in  std_logic_vector(7 downto 0);     -- Bus de datos de lectura desde RAM
        ram_we         : out std_logic;                        -- Habilitacion de escritura en RAM
        
        -- Salidas de Registro y Monitoreo de Estado
        last_color_reg : out std_logic_vector(1 downto 0);     -- Registro del ultimo color procesado
        last_size_reg  : out std_logic;                        -- Registro del ultimo tamano procesado
        busy           : out std_logic                         -- Indicador de ejecucion de ciclo en curso
    );
end entity;

architecture rtl of FSMHarvard is

    type estado_t is (
        IDLE,
        CALC_ADDR,
        READ_ROM,
        READ_RAM_INDIV,
        WRITE_RAM_INDIV,
        READ_RAM_COLOR_TOT,
        WRITE_RAM_COLOR_TOT,
        READ_RAM_GLOB_U,
        WRITE_RAM_GLOB_U,
        READ_RAM_GLOB_D,
        WRITE_RAM_GLOB_D,
        DONE
    );
    signal estado_actual : estado_t;

    signal color_latched   : std_logic_vector(1 downto 0);
    signal tamano_latched  : std_logic;
    signal rom_addr_calc   : unsigned(3 downto 0);
    signal ram_addr_indiv  : unsigned(3 downto 0);
    signal ram_addr_total  : unsigned(3 downto 0);
    signal dato_leido      : unsigned(7 downto 0);
    signal carry_decenas   : std_logic;

begin

    -- -------------------------------------------------------------------------
    -- Maquina de Estados Finitos de Control de Acceso a Memoria
    -- -------------------------------------------------------------------------
    process(Clock, Reset)
        variable color_base : unsigned(3 downto 0);
    begin
        if Reset = '0' then
            estado_actual  <= IDLE;
            color_latched  <= "00";
            tamano_latched <= '0';
            rom_addr       <= "0000";
            ram_addr       <= "0000";
            ram_data_in    <= (others => '0');
            ram_we         <= '0';
            last_color_reg <= "00";
            last_size_reg  <= '0';
            busy           <= '0';
            dato_leido     <= (others => '0');
            carry_decenas  <= '0';
            rom_addr_calc  <= (others => '0');
            ram_addr_indiv <= (others => '0');
            ram_addr_total <= (others => '0');

        elsif rising_edge(Clock) then
            ram_we <= '0'; -- Deshabilitacion por defecto

            case estado_actual is

                -- Estado IDLE: Espera de disparo
                when IDLE =>
                    busy <= '0';
                    if pulse_btn = '1' then
                        if SW_Color = "01" or SW_Color = "10" or SW_Color = "11" then
                            color_latched  <= SW_Color;
                            tamano_latched <= SW_Tamano;
                            busy           <= '1';
                            estado_actual  <= CALC_ADDR;
                        end if;
                    end if;

                -- Estado CALC_ADDR: Calculo aritmetico de direcciones de memoria
                when CALC_ADDR =>
                    case color_latched is
                        when "01"   => color_base := to_unsigned(0, 4); -- Rojo (base 0)
                        when "10"   => color_base := to_unsigned(1, 4); -- Verde (base 1)
                        when "11"   => color_base := to_unsigned(2, 4); -- Azul (base 2)
                        when others => color_base := to_unsigned(0, 4);
                    end case;
                    
                    rom_addr_calc  <= resize(color_base * 2, 4) + unsigned'("000" & tamano_latched);
                    ram_addr_indiv <= resize(color_base * 3, 4) + unsigned'("000" & tamano_latched);
                    ram_addr_total <= resize(color_base * 3 + 2, 4);
                    
                    last_color_reg <= color_latched;
                    last_size_reg  <= tamano_latched;
                    
                    estado_actual  <= READ_ROM;

                -- Estado READ_ROM: Direccionamiento de memoria ROM
                when READ_ROM =>
                    rom_addr      <= std_logic_vector(rom_addr_calc);
                    estado_actual <= READ_RAM_INDIV;

                -- Estado READ_RAM_INDIV: Lectura de contador individual
                when READ_RAM_INDIV =>
                    ram_addr      <= std_logic_vector(ram_addr_indiv);
                    estado_actual <= WRITE_RAM_INDIV;

                -- Estado WRITE_RAM_INDIV: Actualizacion BCD de contador individual
                when WRITE_RAM_INDIV =>
                    ram_addr   <= std_logic_vector(ram_addr_indiv);
                    dato_leido <= unsigned(ram_data_out);
                    
                    if unsigned(ram_data_out) >= 9 then
                        ram_data_in <= (others => '0');
                    else
                        ram_data_in <= std_logic_vector(unsigned(ram_data_out) + 1);
                    end if;
                    ram_we        <= '1';
                    estado_actual <= READ_RAM_COLOR_TOT;

                -- Estado READ_RAM_COLOR_TOT: Lectura del total acumulado del color
                when READ_RAM_COLOR_TOT =>
                    ram_addr      <= std_logic_vector(ram_addr_total);
                    estado_actual <= WRITE_RAM_COLOR_TOT;

                -- Estado WRITE_RAM_COLOR_TOT: Actualizacion BCD del total por color
                when WRITE_RAM_COLOR_TOT =>
                    ram_addr <= std_logic_vector(ram_addr_total);
                    
                    if unsigned(ram_data_out) >= 9 then
                        ram_data_in <= (others => '0');
                    else
                        ram_data_in <= std_logic_vector(unsigned(ram_data_out) + 1);
                    end if;
                    ram_we        <= '1';
                    estado_actual <= READ_RAM_GLOB_U;

                -- Estado READ_RAM_GLOB_U: Lectura de unidades globales (Dir 9)
                when READ_RAM_GLOB_U =>
                    ram_addr      <= "1001";
                    estado_actual <= WRITE_RAM_GLOB_U;

                -- Estado WRITE_RAM_GLOB_U: Actualizacion de unidades y evaluacion de acarreo
                when WRITE_RAM_GLOB_U =>
                    ram_addr <= "1001";
                    
                    if unsigned(ram_data_out) >= 9 then
                        ram_data_in   <= (others => '0');
                        carry_decenas <= '1';
                    else
                        ram_data_in   <= std_logic_vector(unsigned(ram_data_out) + 1);
                        carry_decenas <= '0';
                    end if;
                    ram_we <= '1';
                    
                    if unsigned(ram_data_out) >= 9 then
                        estado_actual <= READ_RAM_GLOB_D;
                    else
                        estado_actual <= DONE;
                    end if;

                -- Estado READ_RAM_GLOB_D: Lectura de decenas globales (Dir 10)
                when READ_RAM_GLOB_D =>
                    ram_addr      <= "1010";
                    estado_actual <= WRITE_RAM_GLOB_D;

                -- Estado WRITE_RAM_GLOB_D: Actualizacion de decenas globales
                when WRITE_RAM_GLOB_D =>
                    ram_addr <= "1010";
                    
                    if unsigned(ram_data_out) >= 9 then
                        ram_data_in <= (others => '0');
                    else
                        ram_data_in <= std_logic_vector(unsigned(ram_data_out) + 1);
                    end if;
                    ram_we        <= '1';
                    estado_actual <= DONE;

                -- Estado DONE: Finalizacion de secuencia
                when DONE =>
                    busy          <= '0';
                    estado_actual <= IDLE;

                when others =>
                    estado_actual <= IDLE;
            end case;
        end if;
    end process;

end architecture;
